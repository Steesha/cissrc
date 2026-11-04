# Native macOS/Linux tools producing Windows code. No Windows process is run.
set(CMAKE_SYSTEM_NAME Windows)
set(INNO_WINDOWS_ARCH x64 CACHE STRING "Windows target architecture: x64 or x86")
set_property(CACHE INNO_WINDOWS_ARCH PROPERTY STRINGS x64 x86)

if(INNO_WINDOWS_ARCH STREQUAL "x64")
  set(CMAKE_SYSTEM_PROCESSOR x86_64)
  set(_inno_mingw_prefix x86_64-w64-mingw32)
elseif(INNO_WINDOWS_ARCH STREQUAL "x86")
  set(CMAKE_SYSTEM_PROCESSOR x86)
  set(_inno_mingw_prefix i686-w64-mingw32)
else()
  message(FATAL_ERROR "INNO_WINDOWS_ARCH must be x64 or x86")
endif()

find_program(CMAKE_C_COMPILER NAMES ${_inno_mingw_prefix}-gcc REQUIRED)
find_program(CMAKE_RC_COMPILER NAMES ${_inno_mingw_prefix}-windres REQUIRED)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
# Preserve the architecture when CMake checks the cross compiler.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES INNO_WINDOWS_ARCH)
