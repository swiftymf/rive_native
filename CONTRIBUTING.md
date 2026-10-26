# Contributing to rive_native

This guide covers how to build and run the rive_native Flutter plugin locally for development.

## Prerequisites

- Xcode 15+ with command line tools
- Flutter SDK
- Dart SDK
- premake5 (for building native libraries)

## Project Structure

```
rive_native/
├── native/                     # C++ native libraries
│   ├── build/                  # Build output (generated)
│   │   ├── macosx/            # macOS builds
│   │   └── iphoneos/          # iOS builds
│   ├── include/               # Public headers
│   ├── src/                   # Source files
│   ├── build.sh               # Native library build script
│   └── build_xcframework.sh   # XCFramework build script
├── macos/
│   ├── rive_native.podspec    # CocoaPods spec
│   └── rive_native/           # SPM package
│       ├── Package.swift
│       ├── Frameworks/        # XCFramework (generated, gitignored)
│       └── Sources/
├── ios/
│   ├── rive_native.podspec    # CocoaPods spec
│   └── rive_native/           # SPM package
│       ├── Package.swift
│       ├── Frameworks/        # XCFramework (generated, gitignored)
│       └── Sources/
├── lib/                       # Dart code
└── example/                   # Example Flutter app
```

## Building for Local Development

### Using the Makefile (Recommended)

The easiest way to build is using the Makefile targets:

```bash
# Build macOS (static libs + XCFramework)
make macos

# Build iOS (device + simulator + XCFramework)
make ios

# Build both
make apple

# Clean build (removes out/ before building)
make macos CLEAN=1
make apple CLEAN=1
```

Run `make help` to see all available targets.

### Manual Build Steps

#### Step 1: Build Native Libraries

Build the native static libraries with the `no-lto` flag (required for XCFramework compatibility):

**macOS:**
```bash
cd native
./build.sh release no-lto flutter-runtime
```

**iOS (device + simulator):**
```bash
cd native
./build.sh release ios no-lto flutter-runtime
./build.sh release ios emulator no-lto flutter-runtime
```

The `no-lto` flag is important - XCFrameworks require native object code, not LLVM bitcode produced by LTO.

#### Step 2: Build XCFrameworks

After building the static libraries, create the XCFrameworks:

**macOS:**
```bash
cd native
./build_xcframework.sh macos
```

**iOS:**
```bash
cd native
./build_xcframework.sh ios
```

**Both:**
```bash
cd native
./build_xcframework.sh all
```

This will:
- Merge all static libraries into a single library
- Create the XCFramework with headers
- Copy the XCFramework to the local `Frameworks/` directory
- Generate a zipped XCFramework
- Calculate the SPM checksum
- Update Package.swift with the checksum

#### Step 3: Configure Package.swift for Local Testing

Edit the Package.swift files to use the local path instead of the remote URL.

In `macos/rive_native/Package.swift` and `ios/rive_native/Package.swift`, uncomment the local path and comment out the URL version:

```swift
// FOR LOCAL TESTING: Use local path (uncomment this)
.binaryTarget(
    name: "RiveNative",
    path: "Frameworks/RiveNative_macos.xcframework"  // or RiveNative_ios.xcframework
),

// FOR RELEASE: Use url/checksum (comment this out for local testing)
// .binaryTarget(
//     name: "RiveNative",
//     url: "https://...",
//     checksum: riveNativeChecksum
// ),
```

#### Step 4: Enable SPM in Flutter

```bash
flutter config --enable-swift-package-manager
```

#### Step 5: Run the Example App

```bash
cd example
flutter clean
flutter pub get
flutter run -d macos  # or -d ios
```

## CocoaPods vs SPM

The plugin supports both CocoaPods and Swift Package Manager:

- **CocoaPods**: Uses the podspec files which reference native libraries directly and run setup scripts
- **SPM**: Uses Package.swift files which reference pre-built XCFrameworks

For local development with CocoaPods (the traditional approach):
```bash
cd example
flutter run -d macos  # Without SPM enabled
```

## Switching Between Local and Release Builds

### Local Development (SPM)
1. Build XCFrameworks locally (`make macos` or `make ios`)
2. Uncomment the `.binaryTarget(path: ...)` line in Package.swift
3. Comment out the `.binaryTarget(url: ..., checksum: ...)` line

### Release Build (SPM)
1. Build XCFrameworks
2. Upload zipped XCFrameworks to CDN at versioned URLs
3. Comment out `.binaryTarget(path: ...)` in Package.swift
4. Uncomment `.binaryTarget(url: ..., checksum: ...)` - the `build_xcframework.sh` script automatically updates checksums

## Troubleshooting

### "symbol not found" errors at runtime
FFI symbols need to be force-linked because they're only accessed via `dlsym` at runtime. The plugin registration code in `rive_native_plugin.mm` calls functions that reference key symbols, forcing the linker to include them. If you add new FFI entry points, ensure they're referenced from the plugin registration.

### XCFramework build fails with "Unknown header: 0xb17c0de"
Libraries were built with LTO. Rebuild with `no-lto` flag:
```bash
./build.sh release no-lto flutter-runtime
```

### SPM can't find XCFramework
1. Make sure you've run `build_xcframework.sh` which copies the framework to `Frameworks/`
2. Verify the framework exists:
   ```bash
   ls -la macos/rive_native/Frameworks/
   ls -la ios/rive_native/Frameworks/
   ```
3. Make sure the local path is uncommented in Package.swift

### Headers not found during SPM build
Rebuild the XCFramework - headers are copied into it during the build process.

## Release Process

1. Build native libraries with `no-lto` flag
2. Run `build_xcframework.sh all`
3. Upload XCFramework zips to CDN at versioned URLs
4. Update Package.swift files to use url/checksum (comment out path, uncomment url)
5. Commit the updated Package.swift files
