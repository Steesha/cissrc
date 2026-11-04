if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(_fpc_cross_compiler ppcrossx64)
  set(_fpc_cross_target x86_64-win64)
  set(_fpc_cross_os win64)
  set(_fpc_cross_binutils x86_64-w64-mingw32)
else()
  set(_fpc_cross_compiler ppcross386)
  set(_fpc_cross_target i386-win32)
  set(_fpc_cross_os win32)
  set(_fpc_cross_binutils i686-w64-mingw32)
endif()
set(INNO_FPC "${INNO_FPC_CROSS_ROOT}/lib/fpc/3.2.2/${_fpc_cross_compiler}")
if(NOT EXISTS "${INNO_FPC}")
  message(FATAL_ERROR "Source-built cross compiler not found: ${INNO_FPC}")
endif()
get_filename_component(_binutils_dir "${CMAKE_C_COMPILER}" DIRECTORY)
set(_pascal_target_flags -n "-T${_fpc_cross_os}" "-XP${_fpc_cross_binutils}-" "-FD${_binutils_dir}"
  "-Fu${INNO_FPC_CROSS_ROOT}/lib/fpc/3.2.2/units/${_fpc_cross_target}/*")

add_library(inno_small_decoder OBJECT
  Projects/Src/Compression.LZMA1SmallDecompressor/LzmaDecode/LzmaDecodeInno.c)
target_compile_definitions(inno_small_decoder PRIVATE
  _LZMA_OUT_READ _LZMA_IN_CB LzmaDecode=IS_LzmaSmallDecode)
add_library(inno_decoders STATIC
  Projects/Src/Compression.LZMADecompressor/Lzma2Decode/ISLzmaDec.c
  $<TARGET_OBJECTS:inno_small_decoder>)
