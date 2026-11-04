find_package(Threads REQUIRED)
set(LZMA_SDK "${CMAKE_CURRENT_SOURCE_DIR}/../../../../Components/Lzma2")

add_library(islzma_native STATIC
  islzma.c
  "${LZMA_SDK}/7zStream.c"
  "${LZMA_SDK}/Alloc.c"
  "${LZMA_SDK}/CpuArch.c"
  "${LZMA_SDK}/LzFind.c"
  "${LZMA_SDK}/LzFindMt.c"
  "${LZMA_SDK}/LzFindOpt.c"
  "${LZMA_SDK}/LzmaEnc.c"
  "${LZMA_SDK}/Lzma2Enc.c"
  "${LZMA_SDK}/MtCoder.c"
  "${LZMA_SDK}/MtDec.c"
  "${LZMA_SDK}/Threads.c"
)
target_include_directories(islzma_native PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(islzma_native PUBLIC Threads::Threads)
target_compile_features(islzma_native PUBLIC c_std_99)

# Match the existing Win32 DLL's SDK callback calling convention.
if(MSVC AND CMAKE_SIZEOF_VOID_P EQUAL 4)
  target_compile_options(islzma_native PUBLIC /Gz)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_compile_definitions(islzma_native PRIVATE _GNU_SOURCE)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$" AND
     CMAKE_C_COMPILER_ID MATCHES "^(GNU|Clang)$")
    # Free Pascal links this archive directly without the C driver's atomic helpers.
    target_compile_options(islzma_native PRIVATE -mno-outline-atomics)
  endif()
endif()

if(MINGW AND CMAKE_SIZEOF_VOID_P EQUAL 4)
  # FPC 3.2.2's Win32 linker cannot link the MinGW encoder and CRT archives together.
  add_library(islzma_native_win32 SHARED islzma.c islzma.def)
  target_link_libraries(islzma_native_win32 PRIVATE islzma_native)
  target_link_options(islzma_native_win32 PRIVATE -static -Wl,--enable-stdcall-fixup)
  set_target_properties(islzma_native_win32 PROPERTIES PREFIX "" OUTPUT_NAME "islzma-native")
endif()
