# The Flutter tooling requires that developers have CMake 3.14 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "rive_native")
project(${PROJECT_NAME} LANGUAGES CXX C)

# Only run setup if no development marker exists (i.e., not built from source).
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/rive_marker_linux_development")
  execute_process(
    COMMAND ${CMAKE_COMMAND} -E env dart run rive_native:setup --verbose -p linux
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/../"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE
  )
endif()

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "rive_native_plugin")

set (CMAKE_CXX_STANDARD 17)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES} "rive_native_plugin.cpp")

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/include"
)
target_link_directories(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/bin/lib/release/")

# Set the library directory variable for easier reference
set(LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin/lib/release")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

# When building for editor, full scripting libraries are built and a marker file is created.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/rive_marker_linux_scripting")
  # Define RIVE_WITH_SCRIPTING so the plugin knows to call riveLuaDummyLinker
  target_compile_definitions(${PLUGIN_NAME} PRIVATE RIVE_WITH_SCRIPTING)
endif()

# Use --start-group/--end-group INLINE with the libraries so the linker
# resolves circular dependencies between the static archives.
# NOTE: target_link_options places flags BEFORE libraries in the link command,
# so we must inline the group flags via target_link_libraries instead.
# rive_native contains FFI symbols (riveVMCreate, riveFactory, etc.) that are
# only referenced at runtime via dlsym/Dart FFI, not at link time. Without
# --whole-archive the linker won't pull them from the .a into the .so.
target_link_libraries(${PLUGIN_NAME} PRIVATE
  -Wl,--start-group
  -Wl,--whole-archive
  rive_native
  -Wl,--no-whole-archive
  rive
  rive_harfbuzz
  rive_sheenbidi
  rive_decoders
  libpng
  zlib
  libjpeg
  libwebp
  rive_pls_renderer
  rive_yoga
  miniaudio
  rive_scripting_workspace
  luau_analyzer
  luau_compiler
  luau_vm
  rust_ffi
  brotli
  spirv_cross
  rive_pathops
  -Wl,--end-group
)

target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE GL EGL dl)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rive_native_bundled_libraries
  ""
  PARENT_SCOPE
)
