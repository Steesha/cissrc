if(NOT CMAKE_CROSSCOMPILING)
  find_program(INNO_FPC fpc REQUIRED)
endif()
find_program(INNO_FPCRES fpcres REQUIRED)
set(_native_resource_sources "${PROJECT_SOURCE_DIR}/Projects/Res")
set(_native_resources "${PROJECT_BINARY_DIR}/native-resources")

function(inno_native_resource name)
  set(_output "${_native_resources}/${name}.res")
  add_custom_command(OUTPUT "${_output}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_native_resources}"
    COMMAND "${INNO_FPCRES}" -of res -o "${_output}" "${name}.rc"
    WORKING_DIRECTORY "${_native_resource_sources}"
    DEPENDS "${_native_resource_sources}/${name}.rc" ${ARGN}
    VERBATIM)
  file(GENERATE OUTPUT "${_native_resources}/${name}.inc"
    CONTENT "{\$R '${_output}'}\n")
endfunction()

inno_native_resource(ISCmplr.images
  "${_native_resource_sources}/wizardimage150.png"
  "${_native_resource_sources}/wizardimage150_dark.png"
  "${_native_resource_sources}/wizardsmallimage250.png"
  "${_native_resource_sources}/wizardsmallimage250_dark.png")
if(WIN32)
  inno_native_resource(ConsoleApp.manifest "${_native_resource_sources}/ConsoleApp.manifest")
  set(_issig_resource "${_native_resources}/ConsoleApp.manifest.res")
endif()

set(_iscc_link_flags "-Fl$<TARGET_FILE_DIR:islzma_native>")
set(_iscc_compiler_files)
if(WIN32)
  if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    foreach(_library IN ITEMS libgcc.a libmsvcrt.a)
      execute_process(COMMAND "${CMAKE_C_COMPILER}" "-print-file-name=${_library}"
        OUTPUT_VARIABLE _archive OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
      if(NOT EXISTS "${_archive}")
        message(FATAL_ERROR "MinGW library not found: ${_library}")
      endif()
      get_filename_component(_archive_dir "${_archive}" DIRECTORY)
      list(APPEND _iscc_link_flags "-Fl${_archive_dir}")
    endforeach()
  endif()
else()
  find_package(OpenSSL REQUIRED COMPONENTS Crypto)
  get_filename_component(_iscc_crypto_dir "${OPENSSL_CRYPTO_LIBRARY}" DIRECTORY)
  set(_issig_link_flags "-Fl${_iscc_crypto_dir}")
  list(APPEND _iscc_link_flags ${_issig_link_flags})
endif()

if(APPLE)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  find_program(INNO_DARWIN_LINKER NAMES ld64.lld REQUIRED)
  set(_native_linker_dir "${PROJECT_BINARY_DIR}/native-linker")
  file(MAKE_DIRECTORY "${_native_linker_dir}")
  configure_file("${PROJECT_SOURCE_DIR}/cmake/macos_fpc_link.py.in"
    "${_native_linker_dir}/ld" @ONLY)
  file(CHMOD "${_native_linker_dir}/ld" PERMISSIONS
    OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
  list(APPEND _pascal_target_flags "-FD${_native_linker_dir}" "-WM${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()

set(_iscc_dir "${PROJECT_BINARY_DIR}/iscc")
set(_iscc_name "iscc${CMAKE_EXECUTABLE_SUFFIX}")
set(_iscc_executable "${_iscc_dir}/${_iscc_name}")
if(TARGET islzma_native_win32)
  set(_iscc_compiler_files "${_iscc_dir}/islzma-native.dll")
  add_custom_command(OUTPUT "${_iscc_compiler_files}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_iscc_dir}"
    COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:islzma_native_win32>" "${_iscc_compiler_files}"
    DEPENDS islzma_native_win32
    VERBATIM)
endif()
file(GLOB _iscc_sources CONFIGURE_DEPENDS
  "${PROJECT_SOURCE_DIR}/Components/*.pas"
  "${PROJECT_SOURCE_DIR}/Components/*.inc"
  "${PROJECT_SOURCE_DIR}/Components/UniPs/Source/*.pas"
  "${PROJECT_SOURCE_DIR}/Components/UniPs/Source/*.inc"
  "${PROJECT_SOURCE_DIR}/Projects/Src/*.pas"
  "${PROJECT_SOURCE_DIR}/Projects/Src/*.inc")
inno_copy_compiler_data("${_iscc_dir}" _iscc_data)
add_custom_command(OUTPUT "${_iscc_executable}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${_iscc_dir}/units"
  COMMAND "${INNO_FPC}" -B -Mdelphiunicode -dSTATICPREPROC
    -dPS_INNO_WINDOWS_TARGET -dPS_MINIVCL -dPS_NOGRAPHCONST -dPS_PANSICHAR
    -dPS_NOINTERFACEGUIDBRACKETS
    "-Fu${PROJECT_SOURCE_DIR}/Components"
    "-Fu${PROJECT_SOURCE_DIR}/Components/UniPs/Source"
    "-Fu${PROJECT_SOURCE_DIR}/Projects/Src"
    ${_pascal_target_flags}
    "-FU${_iscc_dir}/units" "-FE${_iscc_dir}" "-o${_iscc_name}"
    ${_iscc_link_flags}
    "-Fi${_native_resources}" "${PROJECT_SOURCE_DIR}/Projects/NativeISCC.dpr"
  DEPENDS ${_iscc_sources} islzma_native
    Projects/NativeISCC.dpr "${_native_resources}/ISCmplr.images.res"
  VERBATIM)
add_custom_target(native_iscc ALL DEPENDS "${_iscc_executable}" ${_iscc_data} ${_iscc_compiler_files})

set(_issigtool_dir "${PROJECT_BINARY_DIR}/issigtool")
set(_issigtool_name "issigtool${CMAKE_EXECUTABLE_SUFFIX}")
set(_issigtool_executable "${_issigtool_dir}/${_issigtool_name}")
add_custom_command(OUTPUT "${_issigtool_executable}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${_issigtool_dir}/units"
  COMMAND "${INNO_FPC}" -B -Mdelphiunicode
    "-Fu${PROJECT_SOURCE_DIR}/Components" "-Fu${PROJECT_SOURCE_DIR}/Projects/Src"
    ${_pascal_target_flags}
    "-FU${_issigtool_dir}/units" "-FE${_issigtool_dir}" "-o${_issigtool_name}"
    ${_issig_link_flags} -dINNO_SOURCE_RESOURCES "-Fi${_native_resources}"
    "${PROJECT_SOURCE_DIR}/Projects/ISSigTool.dpr"
  DEPENDS ${_iscc_sources} Projects/ISSigTool.dpr ${_issig_resource}
  VERBATIM)
add_custom_target(native_issigtool ALL DEPENDS "${_issigtool_executable}")
