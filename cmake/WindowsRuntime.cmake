# Source-built C objects used by Setup and SetupLdr. These targets are an
# intermediate migration step, not complete installer executables.
set(_inno_src "${PROJECT_SOURCE_DIR}/Projects/Src")
file(GLOB _pascal_sources CONFIGURE_DEPENDS
  "${PROJECT_SOURCE_DIR}/Components/*.pas" "${PROJECT_SOURCE_DIR}/Components/*.inc"
  "${_inno_src}/*.pas" "${_inno_src}/*.inc")
add_library(setup_lzma_decoder OBJECT
  "${_inno_src}/Compression.LZMADecompressor/Lzma2Decode/ISLzmaDec.c")
add_library(setupldr_lzma_decoder OBJECT
  "${_inno_src}/Compression.LZMA1SmallDecompressor/LzmaDecode/LzmaDecodeInno.c")
target_compile_definitions(setupldr_lzma_decoder PRIVATE _LZMA_OUT_READ _LZMA_IN_CB)
add_library(setup_7z_decoder OBJECT
  "${_inno_src}/Compression.SevenZipDecoder/7zDecode/IS7zDec.c")

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
  set(_inno_object_arch arm64)
elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(_inno_object_arch x64)
else()
  set(_inno_object_arch x86)
endif()
set(_inno_objects "${PROJECT_BINARY_DIR}/runtime-objects")
add_custom_target(setup_decoder_objects ALL
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${_inno_objects}"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    $<TARGET_OBJECTS:setup_lzma_decoder> "${_inno_objects}/ISLzmaDec-${_inno_object_arch}.obj"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    $<TARGET_OBJECTS:setupldr_lzma_decoder> "${_inno_objects}/LzmaDecodeInno-${_inno_object_arch}.obj"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    $<TARGET_OBJECTS:setup_7z_decoder> "${_inno_objects}/IS7zDec-${_inno_object_arch}.obj"
  DEPENDS setup_lzma_decoder setupldr_lzma_decoder setup_7z_decoder
  VERBATIM
)

# Delphi/FPC consume .res files; request that format explicitly from windres.
if(MINGW)
  set(_inno_resources)
  foreach(_inno_name Setup.version SetupLdr.version SetupLdr.offsettable)
    set(_inno_output "${PROJECT_BINARY_DIR}/runtime-resources/${_inno_name}.res")
    add_custom_command(OUTPUT "${_inno_output}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROJECT_BINARY_DIR}/runtime-resources"
      COMMAND "${CMAKE_RC_COMPILER}" -O res
        -I "${PROJECT_SOURCE_DIR}/Projects/Res"
        "${PROJECT_SOURCE_DIR}/Projects/Res/${_inno_name}.rc" "${_inno_output}"
      DEPENDS "${PROJECT_SOURCE_DIR}/Projects/Res/${_inno_name}.rc"
        "${PROJECT_SOURCE_DIR}/Projects/Res/SetupLdr.offsettable.txt"
      VERBATIM
    )
    list(APPEND _inno_resources "${_inno_output}")
  endforeach()
  set(_setup_resources_dir "${PROJECT_BINARY_DIR}/runtime-resources")
  # The archive decoder embeds its own LZMA implementation. Keep its symbols
  # local so it can link alongside Setup's separate streaming decoder.
  set(_setup_7z_object "${_inno_objects}/IS7zDec-fpc-${_inno_object_arch}.obj")
  add_custom_command(OUTPUT "${_setup_7z_object}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_inno_objects}"
    COMMAND "${CMAKE_OBJCOPY}" --wildcard "--localize-symbol=*Lzma*"
      $<TARGET_OBJECTS:setup_7z_decoder> "${_setup_7z_object}"
    DEPENDS setup_7z_decoder $<TARGET_OBJECTS:setup_7z_decoder>
    VERBATIM)
  add_custom_target(setup_7z_fpc_object ALL DEPENDS "${_setup_7z_object}")
  file(GENERATE OUTPUT "${_setup_resources_dir}/Setup.SevenZipObject.inc" CONTENT
    "{\$L '${_setup_7z_object}'}\n")
  set(_setup_icons "${_setup_resources_dir}/Setup.icons.res")
  set(_setup_manifest_name "Setup.XPTheme-${_inno_object_arch}")
  set(_setup_manifest "${_setup_resources_dir}/${_setup_manifest_name}.res")
  set(_setup_assets "${PROJECT_SOURCE_DIR}/Projects/Res")
  add_custom_command(OUTPUT "${_setup_icons}" "${_setup_manifest}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_setup_resources_dir}"
    COMMAND "${CMAKE_RC_COMPILER}" -O res -I "${_setup_assets}"
      "${_setup_assets}/Setup.icons.rc" "${_setup_icons}"
    COMMAND "${CMAKE_RC_COMPILER}" -O res -I "${_inno_src}"
      "${_inno_src}/${_setup_manifest_name}.rc" "${_setup_manifest}"
    DEPENDS "${_setup_assets}/Setup.icons.rc"
      "${_setup_assets}/Setup.icon.ico" "${_setup_assets}/Setup.group.ico"
      "${_setup_assets}/Setup.uninstall.ico"
      "${_inno_src}/${_setup_manifest_name}.rc" "${_inno_src}/${_setup_manifest_name}.manifest"
    VERBATIM)
  file(GENERATE OUTPUT "${_setup_resources_dir}/Setup.Resources.inc" CONTENT
    "{\$R '${_setup_icons}'}\n{\$R '${_setup_manifest}'}\n{\$R '${_setup_resources_dir}/Setup.version.res'}\n")
  list(APPEND _inno_resources "${_setup_icons}" "${_setup_manifest}")
  add_custom_target(setup_resources ALL DEPENDS ${_inno_resources})
endif()

if(MINGW AND CMAKE_CROSSCOMPILING AND TARGET inno_decoders)
  set(_loader_dir "${PROJECT_BINARY_DIR}/setupldr")
  set(_manifest "SetupLdr.XPTheme-${_inno_object_arch}")
  set(_loader_icons "${PROJECT_BINARY_DIR}/runtime-resources/SetupLdr.icons.res")
  set(_loader_manifest "${PROJECT_BINARY_DIR}/runtime-resources/${_manifest}.res")
  set(_res_dir "${PROJECT_SOURCE_DIR}/Projects/Res")
  file(MAKE_DIRECTORY "${_loader_dir}")
  add_custom_command(OUTPUT "${_loader_icons}" "${_loader_manifest}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROJECT_BINARY_DIR}/runtime-resources"
    COMMAND "${CMAKE_RC_COMPILER}" -O res -I "${_res_dir}"
      "${_res_dir}/SetupLdr.icons.rc" "${_loader_icons}"
    COMMAND "${CMAKE_RC_COMPILER}" -O res -I "${_inno_src}"
      "${_inno_src}/${_manifest}.rc" "${_loader_manifest}"
    DEPENDS "${_res_dir}/SetupLdr.icons.rc"
      "${_res_dir}/Setup.icon.ico" "${_res_dir}/Setup.icon.dark.ico"
      "${_inno_src}/${_manifest}.rc" "${_inno_src}/${_manifest}.manifest"
    VERBATIM)
  set(_loader_version "${PROJECT_BINARY_DIR}/runtime-resources/SetupLdr.version.res")
  set(_loader_offsets "${PROJECT_BINARY_DIR}/runtime-resources/SetupLdr.offsettable.res")
  set(_loader_include "${_loader_dir}/SetupLdr.Resources.inc")
  file(GENERATE OUTPUT "${_loader_include}" CONTENT
    "{\$R '${_loader_icons}'}\n{\$R '${_loader_manifest}'}\n{\$R '${_loader_version}'}\n{\$R '${_loader_offsets}'}\n")
  add_custom_command(OUTPUT "${_loader_dir}/SetupLdr.exe"
    COMMAND "${INNO_FPC}" ${_pascal_target_flags} -B -Mdelphiunicode
      -dSETUPLDRPROJ -dINNO_SOURCE_RESOURCES
      "-Fi${_loader_dir}" "-Fu${PROJECT_SOURCE_DIR}/Components" "-Fu${_inno_src}"
      "-FU${_loader_dir}" "-FE${_loader_dir}" "-Fl$<TARGET_FILE_DIR:inno_decoders>"
      "${PROJECT_SOURCE_DIR}/Projects/SetupLdr.dpr"
    DEPENDS ${_pascal_sources} Projects/SetupLdr.dpr inno_decoders
      "${_loader_icons}" "${_loader_manifest}" "${_loader_include}"
      "${_loader_version}" "${_loader_offsets}"
    VERBATIM)
  add_custom_target(setupldr ALL DEPENDS "${_loader_dir}/SetupLdr.exe")
endif()

# build_lcl_cross.py produces these Win32 widgetset units on the host.
set(INNO_LCL_CROSS_UNITS "" CACHE PATH "Source-built Lazarus Win32 LCL unit directory")
if(INNO_LCL_CROSS_UNITS)
  if(NOT MINGW OR NOT CMAKE_CROSSCOMPILING OR NOT TARGET inno_decoders)
    message(FATAL_ERROR "Setup requires the MinGW cross toolchain and INNO_FPC_CROSS_ROOT")
  endif()
  foreach(_unit IN ITEMS interfaces forms)
    if(NOT EXISTS "${INNO_LCL_CROSS_UNITS}/${_unit}.ppu")
      message(FATAL_ERROR "Missing LCL unit ${_unit}.ppu in ${INNO_LCL_CROSS_UNITS}")
    endif()
  endforeach()

  execute_process(COMMAND "${CMAKE_C_COMPILER}" -print-file-name=libkernel32.a
    OUTPUT_VARIABLE _kernel32_archive OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY)
  if(NOT EXISTS "${_kernel32_archive}")
    message(FATAL_ERROR "MinGW kernel32 import library not found: ${_kernel32_archive}")
  endif()
  get_filename_component(_mingw_lib_dir "${_kernel32_archive}" DIRECTORY)

  set(_setup_dir "${PROJECT_BINARY_DIR}/setup")
  set(_unips_dir "${PROJECT_SOURCE_DIR}/Components/UniPs/Source")
  file(GLOB _setup_dependencies CONFIGURE_DEPENDS
    "${_unips_dir}/*.pas" "${_unips_dir}/*.inc"
    "${PROJECT_SOURCE_DIR}/Components/*.inc"
    "${PROJECT_SOURCE_DIR}/Components/*.dfm" "${_inno_src}/*.dfm" "${_inno_src}/*.lfm"
    "${INNO_LCL_CROSS_UNITS}/*.ppu" "${INNO_LCL_CROSS_UNITS}/*.o"
    "${INNO_LCL_CROSS_UNITS}/*.a")
  set(_dark_icons_rc "${_setup_resources_dir}/SetupCustomStyle.icons.rc")
  set(_dark_icons "${_setup_resources_dir}/SetupCustomStyle.icons.res")
  file(GENERATE OUTPUT "${_dark_icons_rc}" CONTENT [=[
LANGUAGE 9, 1
MAINICON ICON "Setup.icon.ico"
Z_GROUPICON ICON "Setup.group.ico"
Z_UNINSTALLICON ICON "Setup.uninstall.ico"
MAINICON_DARK ICON "Setup.icon.dark.ico"
Z_GROUPICON_DARK ICON "Setup.group.ico"
Z_UNINSTALLICON_DARK ICON "Setup.uninstall.ico"
]=])
  add_custom_command(OUTPUT "${_dark_icons}"
    COMMAND "${CMAKE_RC_COMPILER}" -O res -I "${_setup_assets}" "${_dark_icons_rc}" "${_dark_icons}"
    DEPENDS "${_dark_icons_rc}" "${_setup_assets}/Setup.icon.dark.ico" "${_setup_assets}/Setup.icon.ico"
      "${_setup_assets}/Setup.group.ico" "${_setup_assets}/Setup.uninstall.ico"
    VERBATIM)
  set(INNO_VCL_STYLE_DIR "" CACHE PATH "Directory containing optional VSF preset data")
  set(_preset_include "")
  if(INNO_VCL_STYLE_DIR)
    set(_preset_resources "${_setup_resources_dir}/SetupCustomStyle.styles.res")
    set(_preset_rc "${_setup_resources_dir}/SetupCustomStyle.styles.rc")
    set(_preset_content "LANGUAGE 9, 1\n")
    set(_preset_dependencies "")
    set(_modern_dark_style "WINDOWSMODERNDARK|Windows11_Modern_Dark.vsf")
    if(NOT EXISTS "${INNO_VCL_STYLE_DIR}/Windows11_Modern_Dark.vsf" AND
        EXISTS "${INNO_VCL_STYLE_DIR}/Windows_Modern_Dark_SE.vsf")
      set(_modern_dark_style "WINDOWSMODERNDARKSE|Windows_Modern_Dark_SE.vsf")
    endif()
    foreach(_style IN ITEMS
      "SLATECLASSICO|SlateClassico.vsf"
      "${_modern_dark_style}"
      "WINDOWSMODERNLIGHT|Windows11_Modern_Light.vsf"
      "WINDOWSPOLARDARK|Windows11_Polar_Dark.vsf"
      "WINDOWSPOLARLIGHT|Windows11_Polar_Light.vsf"
      "STELLAR|Stellar.vsf"
      "ZIRCON|Zircon.vsf")
      string(REPLACE "|" ";" _style "${_style}")
      list(GET _style 0 _resource_name)
      list(GET _style 1 _style_file)
      set(_style_path "${INNO_VCL_STYLE_DIR}/${_style_file}")
      if(EXISTS "${_style_path}" AND NOT IS_DIRECTORY "${_style_path}")
        string(APPEND _preset_content "${_resource_name} VCLSTYLE \"${_style_file}\"\n")
        list(APPEND _preset_dependencies "${_style_path}")
      endif()
    endforeach()
    if(NOT _preset_dependencies)
      message(FATAL_ERROR "No recognized VSF presets found in ${INNO_VCL_STYLE_DIR}")
    endif()
    file(GENERATE OUTPUT "${_preset_rc}" CONTENT "${_preset_content}")
    add_custom_command(OUTPUT "${_preset_resources}"
      COMMAND "${CMAKE_RC_COMPILER}" -O res -I "${INNO_VCL_STYLE_DIR}" "${_preset_rc}" "${_preset_resources}"
      DEPENDS "${_preset_rc}" ${_preset_dependencies}
      VERBATIM)
    set(_preset_include "{\$R '${_preset_resources}'}\n")
  endif()
  set(_dark_include "${_setup_resources_dir}/SetupCustomStyle.Resources.inc")
  file(GENERATE OUTPUT "${_dark_include}" CONTENT
    "{\$R '${_dark_icons}'}\n{\$R '${_setup_manifest}'}\n{\$R '${_setup_resources_dir}/Setup.version.res'}\n${_preset_include}")

  foreach(_project IN ITEMS Setup SetupCustomStyle)
    string(TOLOWER "${_project}" _target)
    set(_runtime_dir "${PROJECT_BINARY_DIR}/${_target}")
    set(_extra_resources)
    set(_extra_defines)
    if(_project STREQUAL "SetupCustomStyle")
      set(_extra_resources "${_dark_icons}" "${_dark_include}" ${_preset_resources})
      set(_extra_defines -dINNO_LCL_DARK_RESOURCES)
    endif()
    add_custom_command(OUTPUT "${_runtime_dir}/${_project}.exe"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${_runtime_dir}"
      COMMAND "${INNO_FPC}" -B -Mdelphiunicode
        -dSETUPPROJ -dINNO_SOURCE_RESOURCES -dPS_MINIVCL -dPS_NOGRAPHCONST
        -dPS_PANSICHAR -dPS_NOINTERFACEGUIDBRACKETS ${_extra_defines}
        "-Fi${_setup_resources_dir}" "-Fu${INNO_LCL_CROSS_UNITS}"
        "-Fu${PROJECT_SOURCE_DIR}/Components" "-Fu${_unips_dir}" "-Fu${_inno_src}"
        ${_pascal_target_flags}
        "-FU${_runtime_dir}" "-FE${_runtime_dir}"
        "-Fl$<TARGET_FILE_DIR:inno_decoders>" "-Fl${_mingw_lib_dir}"
        "${PROJECT_SOURCE_DIR}/Projects/${_project}.dpr"
      DEPENDS ${_pascal_sources} ${_setup_dependencies} Projects/${_project}.dpr inno_decoders
        setup_7z_fpc_object setup_resources "${_setup_7z_object}" "${_kernel32_archive}"
        "${_setup_icons}" "${_setup_manifest}" "${_setup_resources_dir}/Setup.version.res"
        "${_setup_resources_dir}/Setup.Resources.inc"
        "${_setup_resources_dir}/Setup.SevenZipObject.inc" ${_extra_resources}
      VERBATIM)
    add_custom_target(${_target} ALL DEPENDS "${_runtime_dir}/${_project}.exe")

  endforeach()

  if(_inno_object_arch STREQUAL "x86")
    set(_template_extension e32)
    set(_codec_suffix "")
  else()
    set(_template_extension e64)
    set(_codec_suffix "-x64")
  endif()
  set(_compiler_assets_dir "${PROJECT_BINARY_DIR}/compiler-assets")
  set(_compiler_templates "${_compiler_assets_dir}/Setup.${_template_extension}"
    "${_compiler_assets_dir}/SetupLdr.${_template_extension}" "${_compiler_assets_dir}/SetupCustomStyle.${_template_extension}")
  inno_copy_compiler_data("${_compiler_assets_dir}" _compiler_data)
  set(INNO_IS7Z_SOURCE_DIR "" CACHE PATH "is7z source checkout for Windows archive DLLs")
  set(INNO_ISCOMPRESS_SOURCE_DIR "" CACHE PATH "iscompress source checkout for ZIP and BZip2 codecs")
  if(INNO_IS7Z_SOURCE_DIR OR INNO_ISCOMPRESS_SOURCE_DIR)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
  endif()
  set(_codec_outputs)
  if(INNO_IS7Z_SOURCE_DIR)
    if(NOT EXISTS "${INNO_IS7Z_SOURCE_DIR}/CPP/7zip/7zip_gcc.mak")
      message(FATAL_ERROR "INNO_IS7Z_SOURCE_DIR must point to an is7z source checkout")
    endif()
    set(_archive_outputs)
    foreach(_name IN ITEMS is7z is7zxa is7zxr)
      list(APPEND _archive_outputs "${_compiler_assets_dir}/${_name}${_codec_suffix}.dll")
    endforeach()
    file(GLOB_RECURSE _archive_sources CONFIGURE_DEPENDS LIST_DIRECTORIES false
      "${INNO_IS7Z_SOURCE_DIR}/C/*" "${INNO_IS7Z_SOURCE_DIR}/CPP/*")
    set(_archive_builder "${PROJECT_SOURCE_DIR}/tools/build_is7z_cross.py")
    add_custom_command(OUTPUT ${_archive_outputs}
      COMMAND "${Python3_EXECUTABLE}" "${_archive_builder}"
        "${INNO_IS7Z_SOURCE_DIR}" "${_compiler_assets_dir}" --arch "${_inno_object_arch}"
      DEPENDS "${_archive_builder}" ${_archive_sources} "${PROJECT_BINARY_DIR}/CMakeCache.txt"
      VERBATIM)
    list(APPEND _codec_outputs ${_archive_outputs})
  endif()
  if(INNO_ISCOMPRESS_SOURCE_DIR)
    if(NOT EXISTS "${INNO_ISCOMPRESS_SOURCE_DIR}/zlib/isunzlib.def" OR
       NOT EXISTS "${INNO_ISCOMPRESS_SOURCE_DIR}/bzlib/isbz2decomp.def")
      message(FATAL_ERROR "INNO_ISCOMPRESS_SOURCE_DIR must point to an iscompress source checkout")
    endif()
    set(_decoder_outputs "${_compiler_assets_dir}/isunzlib${_codec_suffix}.dll"
      "${_compiler_assets_dir}/isbunzip${_codec_suffix}.dll"
      "${_compiler_assets_dir}/iszlib${_codec_suffix}.dll"
      "${_compiler_assets_dir}/isbzip${_codec_suffix}.dll")
    file(GLOB_RECURSE _decoder_sources CONFIGURE_DEPENDS LIST_DIRECTORIES false
      "${INNO_ISCOMPRESS_SOURCE_DIR}/zlib/*" "${INNO_ISCOMPRESS_SOURCE_DIR}/bzlib/*")
    set(_decoder_builder "${PROJECT_SOURCE_DIR}/tools/build_iscompress_cross.py")
    add_custom_command(OUTPUT ${_decoder_outputs}
      COMMAND "${Python3_EXECUTABLE}" "${_decoder_builder}"
        "${INNO_ISCOMPRESS_SOURCE_DIR}" "${_compiler_assets_dir}" --arch "${_inno_object_arch}"
      DEPENDS "${_decoder_builder}" ${_decoder_sources} "${PROJECT_BINARY_DIR}/CMakeCache.txt"
      VERBATIM)
    list(APPEND _codec_outputs ${_decoder_outputs})
  endif()
  add_custom_command(OUTPUT ${_compiler_templates}
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_compiler_assets_dir}"
    COMMAND "${CMAKE_COMMAND}" -E copy
      "${_setup_dir}/Setup.exe" "${_compiler_assets_dir}/Setup.${_template_extension}"
    COMMAND "${CMAKE_COMMAND}" -E copy
      "${_loader_dir}/SetupLdr.exe" "${_compiler_assets_dir}/SetupLdr.${_template_extension}"
    COMMAND "${CMAKE_COMMAND}" -E copy
      "${PROJECT_BINARY_DIR}/setupcustomstyle/SetupCustomStyle.exe" "${_compiler_assets_dir}/SetupCustomStyle.${_template_extension}"
    DEPENDS setup setupldr setupcustomstyle "${PROJECT_BINARY_DIR}/setupcustomstyle/SetupCustomStyle.exe"
      "${_setup_dir}/Setup.exe" "${_loader_dir}/SetupLdr.exe"
    VERBATIM)
  add_custom_target(setup_compiler_assets ALL
    DEPENDS ${_compiler_templates} ${_compiler_data} ${_codec_outputs})
endif()
