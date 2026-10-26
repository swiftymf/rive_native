#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rive_native.podspec` to validate before publishing.
#

# Toggle ASAN for debug builds - comment/uncomment one of these:
# USE_ASAN = true   # ASAN enabled (debug libs)
USE_ASAN = false  # ASAN disabled (release libs in debug mode)

Pod::Spec.new do |s|
  rive_build_type = USE_ASAN ? "debug" : "release"
  asan_flag = USE_ASAN ? "-fsanitize=address " : ""

  s.name = "rive_native"
  s.version = "0.0.1"
  s.summary = "Rive Flutter's native macOS plugin"
  s.description = <<-DESC
Rive Flutter's native macOS plugin
                       DESC
  s.homepage = "https://rive.app"
  s.license = { :file => "../LICENSE" }
  s.author = { "Rive" => "support@rive.app" }

  s.source = { :path => "." }
  # Use same source files as SPM package
  s.source_files = "rive_native/Sources/rive_native/**/*.{h,mm,swift}"
  s.public_header_files = "rive_native/Sources/rive_native/include/**/*.h"
  s.dependency "FlutterMacOS"

  s.platform = :osx, "10.11"
  # Using unconditional settings ensures this works with custom schemes/flavors
  # (e.g., Prod-debug, Staging-release). See: https://github.com/rive-app/rive-flutter/issues/594
  s.pod_target_xcconfig = { "USER_HEADER_SEARCH_PATHS" => '"$(PODS_TARGET_SRCROOT)/../native/include"',
                            "LIBRARY_SEARCH_PATHS" => "\"$(PODS_TARGET_SRCROOT)/../native/build/macosx/bin/#{rive_build_type}\"",
                            "OTHER_LDFLAGS" => "#{asan_flag}-Wl,-force_load,$(PODS_TARGET_SRCROOT)/../native/build/macosx/bin/#{rive_build_type}/librive_native.a -lrive -lrive_pls_renderer -lrive_yoga -lrive_harfbuzz -lrive_sheenbidi -lrive_decoders -llibpng -lzlib -llibjpeg -llibwebp -lrive_scripting_workspace -lspirv_cross -lluau_vm -lluau_compiler -lluau_analyzer -lrust_ffi -lminiaudio -lbrotli -lrive_pathops",
                            "OTHER_CFLAGS" => USE_ASAN ? "-fsanitize=address" : "",
                            "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
                            "CLANG_CXX_LIBRARY" => "libc++" }
  s.swift_version = "5.0"
 
  script = <<-SCRIPT
  #!/bin/sh
  set -e

  MARKER="${PODS_TARGET_SRCROOT}/rive_marker_macos_setup_complete"
  DEV_MARKER="${PODS_TARGET_SRCROOT}/rive_marker_macos_development"


  if [ -f "$MARKER" ] || [ -f "$DEV_MARKER" ]; then
    echo "[rive_native] Setup already complete. Skipping."
  else
    echo "[rive_native] Setup marker not found. Running setup script..."
    echo "[rive_native] If this fails, make sure you have Dart installed and available in your PATH."
    echo "[rive_native] You can run the setup manually with:"
    echo "  dart run rive_native:setup --verbose --platform macos"

    # macOS path to Flutter-Generated.xcconfig
    GENERATED_XCCONFIG="${SRCROOT}/../Flutter/ephemeral/Flutter-Generated.xcconfig"
    if [ -f "$GENERATED_XCCONFIG" ]; then
      FLUTTER_ROOT=$(grep FLUTTER_ROOT "$GENERATED_XCCONFIG" | cut -d '=' -f2 | tr -d '[:space:]')
    fi

    if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
      echo "[rive_native] Using dart from FLUTTER_ROOT: $FLUTTER_ROOT"
      "$FLUTTER_ROOT/bin/dart" run rive_native:setup --verbose --platform macos
    else
      echo "[rive_native] FLUTTER_ROOT not set or dart not found in FLUTTER_ROOT. Using system dart..."
      dart run rive_native:setup --verbose --platform macos
    fi
  fi
  SCRIPT

  s.script_phases = [
    {
      :name => 'Rive Native Compile',
      :script => script,
      :execution_position => :before_compile,
      :output_files => [
        '${PODS_TARGET_SRCROOT}/rive_marker_macos_setup_complete',
        '$(PODS_TARGET_SRCROOT)/../native/build/macosx/bin/release/librive_native.a'
      ]
    }
  ]

end
