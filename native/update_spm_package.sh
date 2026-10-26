#!/bin/bash
#
# Update Package.swift files with version and SPM checksums
#
# Usage:
#   ./update_spm_package.sh macos    # Update macOS Package.swift
#   ./update_spm_package.sh ios      # Update iOS Package.swift
#   ./update_spm_package.sh all      # Update both
#
# Prerequisites:
#   - XCFramework zips must exist (run build_xcframework.sh first)
#   - version.txt must exist in the package root
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/build"
VERSION_FILE="$PACKAGE_DIR/version.txt"

# Read version from version.txt
get_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE" | tr -d '[:space:]'
    else
        echo "Error: version.txt not found at $VERSION_FILE" >&2
        exit 1
    fi
}

# Calculate SPM checksum using swift package compute-checksum
calculate_spm_checksum() {
    local zip_path="$1"
    if [[ ! -f "$zip_path" ]]; then
        echo "Error: Zip file not found at $zip_path" >&2
        exit 1
    fi
    swift package compute-checksum "$zip_path" 2>/dev/null
}

# Update a single Package.swift file
update_package_swift() {
    local platform="$1"
    local version="$2"
    local checksum="$3"
    local package_swift

    if [[ "$platform" == "ios" ]]; then
        package_swift="$PACKAGE_DIR/ios/rive_native/Package.swift"
    else
        package_swift="$PACKAGE_DIR/macos/rive_native/Package.swift"
    fi

    if [[ ! -f "$package_swift" ]]; then
        echo "Error: Package.swift not found at $package_swift" >&2
        exit 1
    fi

    echo "Updating $package_swift..."
    echo "  Version: $version"
    echo "  Checksum: $checksum"

    # Update version and checksum
    sed -i '' "s/let riveNativeVersion = \".*\"/let riveNativeVersion = \"$version\"/" "$package_swift"
    sed -i '' "s/let riveNativeChecksum = \".*\"/let riveNativeChecksum = \"$checksum\"/" "$package_swift"

    echo "  Done!"
}

update_macos() {
    local zip_path="$BUILD_DIR/macosx/RiveNative_macos.xcframework.zip"
    local version=$(get_version)
    local checksum=$(calculate_spm_checksum "$zip_path")
    update_package_swift "macos" "$version" "$checksum"
}

update_ios() {
    local zip_path="$BUILD_DIR/iphoneos/RiveNative_ios.xcframework.zip"
    local version=$(get_version)
    local checksum=$(calculate_spm_checksum "$zip_path")
    update_package_swift "ios" "$version" "$checksum"
}

print_usage() {
    echo "Usage: $0 <platform>"
    echo "  platform: ios, macos, or all"
    echo ""
    echo "Updates Package.swift files with version from version.txt"
    echo "and calculates SPM checksums from XCFramework zips."
    echo ""
    echo "Prerequisites:"
    echo "  - Run build_xcframework.sh first to create the zip files"
}

# Main
if [[ $# -lt 1 ]]; then
    print_usage
    exit 1
fi

case "$1" in
    macos)
        update_macos
        ;;
    ios)
        update_ios
        ;;
    all)
        update_macos
        update_ios
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

echo ""
echo "Done!"
