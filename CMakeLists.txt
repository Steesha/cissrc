cmake_minimum_required(VERSION 3.20)
project(InnoSetupNative VERSION 0.1 LANGUAGES C)

# Host tools must target the same macOS version as their native dependencies.
if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  execute_process(COMMAND sw_vers -productVersion OUTPUT_VARIABLE _host_macos
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "${_host_macos}" CACHE STRING "Minimum macOS version" FORCE)
endif()

add_subdirectory(Projects/Src/Compression.LZMACompressor/islzma)

function(inno_copy_compiler_data destination outputs)
  set(files Default.isl ISPPBuiltins.iss SetupClassicIcon.ico
    WizClassicImage.bmp WizClassicImage-IS.bmp
    WizClassicSmallImage.bmp WizClassicSmallImage-IS.bmp)
  file(GLOB_RECURSE languages CONFIGURE_DEPENDS RELATIVE "${PROJECT_SOURCE_DIR}/Files"
    "${PROJECT_SOURCE_DIR}/Files/Languages/*.isl"
    "${PROJECT_SOURCE_DIR}/Files/Languages/*.islu")
  foreach(file IN LISTS files languages)
    set(source "${PROJECT_SOURCE_DIR}/Files/${file}")
    set(output "${destination}/${file}")
    get_filename_component(directory "${output}" DIRECTORY)
    add_custom_command(OUTPUT "${output}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${directory}"
      COMMAND "${CMAKE_COMMAND}" -E copy "${source}" "${output}"
      DEPENDS "${source}"
      VERBATIM)
    list(APPEND copied "${output}")
  endforeach()
  set(${outputs} "${copied}" PARENT_SCOPE)
endfunction()

set(INNO_FPC_CROSS_ROOT "" CACHE PATH "Source-built FPC Windows installation prefix")
if(CMAKE_CROSSCOMPILING AND MINGW AND INNO_FPC_CROSS_ROOT)
  include(cmake/NativePascal.cmake)
endif()

option(INNO_BUILD_NATIVE_ISCC "Build the FPC ISCC front end and compiler" OFF)
if(INNO_BUILD_NATIVE_ISCC)
  if(WIN32 AND NOT MINGW)
    message(FATAL_ERROR "The Windows FPC compiler requires MinGW-w64")
  endif()
  if(CMAKE_CROSSCOMPILING AND NOT (MINGW AND INNO_FPC_CROSS_ROOT))
    message(FATAL_ERROR "The cross-built FPC compiler requires MinGW-w64 and INNO_FPC_CROSS_ROOT")
  endif()
  include(cmake/NativeISCC.cmake)
endif()

if(WIN32)
  include(cmake/WindowsRuntime.cmake)
endif()
