#!/bin/bash
#
# Build XCFrameworks for iOS and macOS SPM support
#
# Usage:
#   ./build_xcframework.sh ios      # Build iOS XCFramework
#   ./build_xcframework.sh macos    # Build macOS XCFramework
#   ./build_xcframework.sh all      # Build both
#
# Prerequisites:
#   - Run build.sh first to build the static libraries WITH no-lto flag
#   - iOS: ./build.sh release ios no-lto flutter-runtime && ./build.sh release ios emulator no-lto flutter-runtime
#   - macOS: ./build.sh release no-lto flutter-runtime
#
# After building, run update_spm_package.sh to update Package.swift with version and checksums.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/build"

# Output directories - XCFrameworks go alongside the platform builds
IOS_OUTPUT_DIR="$BUILD_DIR/iphoneos"
MACOS_OUTPUT_DIR="$BUILD_DIR/macosx"

# Libraries to include in the merged static library
# These must match what's linked in the podspec
IOS_LIBS=(
    "librive_native.a"
    "librive.a"
    "librive_pls_renderer.a"
    "librive_yoga.a"
    "librive_harfbuzz.a"
    "librive_sheenbidi.a"
    "librive_decoders.a"
    "liblibpng.a"
    "libzlib.a"
    "liblibjpeg.a"
    "liblibwebp.a"
    "libminiaudio.a"
    "libluau_vm.a"
)

# macOS has additional libraries for scripting workspace
MACOS_LIBS=(
    "${IOS_LIBS[@]}"
    "librive_scripting_workspace.a"
    "libspirv_cross.a"
    "libluau_compiler.a"
    "libluau_analyzer.a"
    "libstylua_ffi.a"
    "libbrotli.a"
)

FRAMEWORK_NAME="RiveNative"

# Check if a library contains LLVM bitcode (built with LTO)
check_for_bitcode() {
    local lib_path="$1"
    if otool -l "$lib_path" 2>&1 | grep -q "is an LLVM bit-code file"; then
        echo "ERROR: $lib_path contains LLVM bitcode (built with LTO)"
        echo "XCFramework requires native object code. Rebuild with 'no-lto' flag:"
        echo "  ./build.sh release no-lto flutter-runtime"
        return 1
    fi
    return 0
}

print_usage() {
    echo "Usage: $0 <platform>"
    echo "  platform: ios, macos, or all"
    echo ""
    echo "IMPORTANT: Libraries must be built with 'no-lto' flag for XCFramework compatibility!"
    echo ""
    echo "Prerequisites:"
    echo "  iOS:   ./build.sh release ios no-lto flutter-runtime && ./build.sh release ios emulator no-lto flutter-runtime"
    echo "  macOS: ./build.sh release no-lto flutter-runtime"
    echo ""
    echo "After building, run update_spm_package.sh to update Package.swift with version and checksums."
}

merge_static_libs() {
    local output_lib="$1"
    local lib_dir="$2"
    shift 2
    local libs=("$@")

    local lib_paths=()
    for lib in "${libs[@]}"; do
        local lib_path="$lib_dir/$lib"
        if [[ -f "$lib_path" ]]; then
            lib_paths+=("$lib_path")
        else
            echo "Warning: $lib not found in $lib_dir, skipping"
        fi
    done

    if [[ ${#lib_paths[@]} -eq 0 ]]; then
        echo "Error: No libraries found to merge"
        return 1
    fi

    echo "Merging ${#lib_paths[@]} libraries into $output_lib"
    libtool -static -o "$output_lib" "${lib_paths[@]}"
}

# Zip the XCFramework
zip_xcframework() {
    local platform="$1"
    local output_dir

    if [[ "$platform" == "ios" ]]; then
        output_dir="$IOS_OUTPUT_DIR"
    else
        output_dir="$MACOS_OUTPUT_DIR"
    fi

    local xcframework_path="$output_dir/${FRAMEWORK_NAME}_${platform}.xcframework"
    local zip_path="$output_dir/${FRAMEWORK_NAME}_${platform}.xcframework.zip"

    if [[ ! -d "$xcframework_path" ]]; then
        echo "Error: XCFramework not found at $xcframework_path"
        return 1
    fi

    echo "Zipping $xcframework_path..."

    # Remove old zip if exists
    rm -f "$zip_path"

    # Create zip (from the output directory to get correct paths)
    pushd "$output_dir" > /dev/null
    zip -r "$(basename "$zip_path")" "$(basename "$xcframework_path")"
    popd > /dev/null

    echo "Created $zip_path"
}

build_ios_xcframework() {
    echo "Building iOS XCFramework..."

    local IOS_DEVICE_DIR="$BUILD_DIR/iphoneos/bin/release"
    local IOS_SIM_DIR="$BUILD_DIR/iphoneos/bin/emulator"
    local TEMP_DIR="$IOS_OUTPUT_DIR/temp_ios"

    # Verify build directories exist
    if [[ ! -d "$IOS_DEVICE_DIR" ]]; then
        echo "Error: iOS device build not found at $IOS_DEVICE_DIR"
        echo "Run: ./build.sh release ios no-lto flutter-runtime"
        exit 1
    fi

    if [[ ! -d "$IOS_SIM_DIR" ]]; then
        echo "Error: iOS simulator build not found at $IOS_SIM_DIR"
        echo "Run: ./build.sh release ios emulator no-lto flutter-runtime"
        exit 1
    fi

    # Check for bitcode (LTO) - XCFramework doesn't support bitcode libraries
    echo "Checking for bitcode in libraries..."
    if ! check_for_bitcode "$IOS_DEVICE_DIR/librive_native.a"; then
        exit 1
    fi

    # Create temp directory
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR/device"
    mkdir -p "$TEMP_DIR/simulator"

    # Merge static libraries
    echo "Merging device libraries..."
    merge_static_libs "$TEMP_DIR/device/lib${FRAMEWORK_NAME}.a" "$IOS_DEVICE_DIR" "${IOS_LIBS[@]}"

    echo "Merging simulator libraries..."
    merge_static_libs "$TEMP_DIR/simulator/lib${FRAMEWORK_NAME}.a" "$IOS_SIM_DIR" "${IOS_LIBS[@]}"

    # Copy headers - preserve rive_native/ prefix for includes
    mkdir -p "$TEMP_DIR/headers/rive_native"
    cp -r "$SCRIPT_DIR/include/rive_native/"* "$TEMP_DIR/headers/rive_native/"

    # Create module.modulemap
    cat > "$TEMP_DIR/headers/module.modulemap" << 'EOF'
module RiveNative {
    header "rive_native/external.hpp"
    header "rive_native/external_objc.h"
    header "rive_native/rive_binding.hpp"
    export *
}
EOF

    # Create XCFramework
    local XCFRAMEWORK_PATH="$IOS_OUTPUT_DIR/${FRAMEWORK_NAME}_ios.xcframework"
    rm -rf "$XCFRAMEWORK_PATH"

    echo "Creating XCFramework..."
    xcodebuild -create-xcframework \
        -library "$TEMP_DIR/device/lib${FRAMEWORK_NAME}.a" \
        -headers "$TEMP_DIR/headers" \
        -library "$TEMP_DIR/simulator/lib${FRAMEWORK_NAME}.a" \
        -headers "$TEMP_DIR/headers" \
        -output "$XCFRAMEWORK_PATH"

    # Cleanup
    rm -rf "$TEMP_DIR"

    echo "iOS XCFramework created at: $XCFRAMEWORK_PATH"

    # Copy to SPM package directory for local testing
    local SPM_PACKAGE_DIR="$PACKAGE_DIR/ios/rive_native/Frameworks"
    echo "Copying XCFramework to $SPM_PACKAGE_DIR..."
    mkdir -p "$SPM_PACKAGE_DIR"
    rm -rf "$SPM_PACKAGE_DIR/${FRAMEWORK_NAME}_ios.xcframework"
    cp -R "$XCFRAMEWORK_PATH" "$SPM_PACKAGE_DIR/"

    # Create zip for distribution
    zip_xcframework "ios"

    echo ""
    echo "iOS XCFramework built successfully!"
    echo "  XCFramework: $XCFRAMEWORK_PATH"
    echo "  Zip: $IOS_OUTPUT_DIR/${FRAMEWORK_NAME}_ios.xcframework.zip"
}

build_macos_xcframework() {
    echo "Building macOS XCFramework..."

    local MACOS_DIR="$BUILD_DIR/macosx/bin/release"
    local TEMP_DIR="$MACOS_OUTPUT_DIR/temp_macos"

    # Verify build directory exists
    if [[ ! -d "$MACOS_DIR" ]]; then
        echo "Error: macOS build not found at $MACOS_DIR"
        echo "Run: ./build.sh release no-lto flutter-runtime"
        exit 1
    fi

    # Check for bitcode (LTO) - XCFramework doesn't support bitcode libraries
    echo "Checking for bitcode in libraries..."
    if ! check_for_bitcode "$MACOS_DIR/librive_native.a"; then
        exit 1
    fi

    # Create temp directory
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR/lib"

    # Merge static libraries
    echo "Merging macOS libraries..."
    merge_static_libs "$TEMP_DIR/lib/lib${FRAMEWORK_NAME}.a" "$MACOS_DIR" "${MACOS_LIBS[@]}"

    # Copy headers - preserve rive_native/ prefix for includes
    mkdir -p "$TEMP_DIR/headers/rive_native"
    cp -r "$SCRIPT_DIR/include/rive_native/"* "$TEMP_DIR/headers/rive_native/"

    # Create module.modulemap
    cat > "$TEMP_DIR/headers/module.modulemap" << 'EOF'
module RiveNative {
    header "rive_native/external.hpp"
    header "rive_native/external_objc.h"
    header "rive_native/rive_binding.hpp"
    export *
}
EOF

    # Create XCFramework
    local XCFRAMEWORK_PATH="$MACOS_OUTPUT_DIR/${FRAMEWORK_NAME}_macos.xcframework"
    rm -rf "$XCFRAMEWORK_PATH"

    echo "Creating XCFramework..."
    xcodebuild -create-xcframework \
        -library "$TEMP_DIR/lib/lib${FRAMEWORK_NAME}.a" \
        -headers "$TEMP_DIR/headers" \
        -output "$XCFRAMEWORK_PATH"

    # Cleanup
    rm -rf "$TEMP_DIR"

    echo "macOS XCFramework created at: $XCFRAMEWORK_PATH"

    # Copy to SPM package directory for local testing
    local SPM_PACKAGE_DIR="$PACKAGE_DIR/macos/rive_native/Frameworks"
    echo "Copying XCFramework to $SPM_PACKAGE_DIR..."
    mkdir -p "$SPM_PACKAGE_DIR"
    rm -rf "$SPM_PACKAGE_DIR/${FRAMEWORK_NAME}_macos.xcframework"
    cp -R "$XCFRAMEWORK_PATH" "$SPM_PACKAGE_DIR/"

    # Create zip for distribution
    zip_xcframework "macos"

    echo ""
    echo "macOS XCFramework built successfully!"
    echo "  XCFramework: $XCFRAMEWORK_PATH"
    echo "  Zip: $MACOS_OUTPUT_DIR/${FRAMEWORK_NAME}_macos.xcframework.zip"
}

# Main
if [[ $# -lt 1 ]]; then
    print_usage
    exit 1
fi

# Ensure output directories exist
mkdir -p "$IOS_OUTPUT_DIR"
mkdir -p "$MACOS_OUTPUT_DIR"

case "$1" in
    ios)
        build_ios_xcframework
        ;;
    macos)
        build_macos_xcframework
        ;;
    all)
        build_ios_xcframework
        build_macos_xcframework
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

echo ""
echo "Done!"
echo ""
echo "To update Package.swift with version and checksums, run:"
echo "  ./update_spm_package.sh $1"
