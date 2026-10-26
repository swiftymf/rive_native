.PHONY: default
default:
	@echo "No target specified. Please use 'make <target>' to run a specific task."
	@echo "Run 'make help' for available targets."

# =============================================================================
# Build Options
# =============================================================================
# Pass CLEAN=1 to clean before building: make macos CLEAN=1

# Convert CLEAN=1 to "clean" argument for build.sh
ifdef CLEAN
BUILD_CLEAN := clean
else
BUILD_CLEAN :=
endif

# =============================================================================
# Flutter Runtime Builds (for pub.dev releases)
# =============================================================================

# macOS Flutter runtime build + XCFramework
.PHONY: macos
macos:
	@echo "Building macOS Flutter runtime..."
	cd native && ./build.sh release no-lto flutter-runtime $(BUILD_CLEAN)
	@echo "Building macOS XCFramework..."
	cd native && ./build_xcframework.sh macos
	@echo "macOS build complete!"

# iOS Flutter runtime build (device + simulator) + XCFramework
.PHONY: ios
ios:
	@echo "Building iOS device Flutter runtime..."
	cd native && ./build.sh release ios no-lto flutter-runtime $(BUILD_CLEAN)
	@echo "Building iOS simulator Flutter runtime..."
	cd native && ./build.sh release ios emulator no-lto flutter-runtime $(BUILD_CLEAN)
	@echo "Building iOS XCFramework..."
	cd native && ./build_xcframework.sh ios
	@echo "iOS build complete!"

# Build both iOS and macOS
.PHONY: apple
apple: macos ios
	@echo "All Apple platform builds complete!"

# =============================================================================
# XCFramework Only (when static libs are already built)
# =============================================================================

.PHONY: xcframework-macos
xcframework-macos:
	@echo "Building macOS XCFramework..."
	cd native && ./build_xcframework.sh macos

.PHONY: xcframework-ios
xcframework-ios:
	@echo "Building iOS XCFramework..."
	cd native && ./build_xcframework.sh ios

.PHONY: xcframework-all
xcframework-all:
	@echo "Building all XCFrameworks..."
	cd native && ./build_xcframework.sh all

# =============================================================================
# Debug Builds (for local development)
# =============================================================================

.PHONY: macos-debug
macos-debug:
	@echo "Building macOS debug Flutter runtime..."
	cd native && ./build.sh no-lto flutter-runtime $(BUILD_CLEAN)
	@echo "macOS debug build complete!"

.PHONY: ios-debug
ios-debug:
	@echo "Building iOS device debug Flutter runtime..."
	cd native && ./build.sh ios no-lto flutter-runtime $(BUILD_CLEAN)
	@echo "Building iOS simulator debug Flutter runtime..."
	cd native && ./build.sh ios emulator no-lto flutter-runtime $(BUILD_CLEAN)
	@echo "iOS debug build complete!"

# =============================================================================
# Editor Builds (for Rive Editor, includes scripting)
# =============================================================================

.PHONY: macos-editor
macos-editor:
	@echo "Building macOS for Rive Editor..."
	cd native && ./build.sh release $(BUILD_CLEAN)
	@echo "macOS editor build complete!"

# =============================================================================
# Android Builds
# =============================================================================

.PHONY: android
android:
	@echo "Building Android Flutter runtime..."
	cd native && ./build.sh release android flutter-runtime $(BUILD_CLEAN)
	@echo "Android build complete!"

# =============================================================================
# Tests
# =============================================================================

# Run the unit test suite in Chrome against the local debug wasm.
# Builds the debug wasm first; pass ARGS to forward flutter test arguments
# or skip the build: make test-web ARGS="no-build test/hit_test.dart"
.PHONY: test-web
test-web:
	./scripts/test_web.sh $(ARGS)

# =============================================================================
# Clean Targets
# =============================================================================

.PHONY: clean
clean:
	@echo "Cleaning Rive download markers..."
	@rm -f ios/rive_marker_ios_setup_complete
	@rm -f ios/rive_marker_ios_development
	@rm -f macos/rive_marker_macos_setup_complete
	@rm -f macos/rive_marker_macos_development
	@rm -f windows/rive_marker_windows_development
	@rm -f windows/rive_marker_windows_setup_complete
	@rm -f android/rive_marker_android_development
	@rm -f linux/rive_marker_linux_development
	@echo "Clean complete"

.PHONY: clean-native
clean-native:
	@echo "Cleaning native build output..."
	rm -rf native/out
	rm -rf native/build
	@echo "Native clean complete"

.PHONY: clean-all
clean-all: clean clean-native
	@echo "Full clean complete"

# =============================================================================
# Utility Targets
# =============================================================================

.PHONY: update_cpp_runtime
update_cpp_runtime:
	@rsync -av --exclude-from='runtime_exclude.txt' --delete --delete-excluded ../runtime/ runtime
	@echo "\nRive runtime updated\n"
	@echo "Testing if the shaders/Makefile exists..."
	@if [ -e runtime/renderer/src/shaders/Makefile ]; then \
		echo "Makefile exists, renaming it to Makefile.rive\n"; \
		mv runtime/renderer/src/shaders/Makefile runtime/renderer/src/shaders/Makefile.rive; \
	else \
		>&2 echo "\033[1;31mERROR: Makefile does not exist, nothing to rename. Pub builds may fail.\033[0m"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory verify_cpp_runtime

# The synced runtime is published to pub.dev, so it must never contain anything
# that isn't already public. Everything under ../runtime that git tracks is
# pushed to github.com/rive-app/rive-runtime; anything untracked (build output,
# editor config, secrets) is not, and must be excluded in runtime_exclude.txt.
.PHONY: verify_cpp_runtime
verify_cpp_runtime:
	@echo "Verifying synced runtime contains only public files..."
	@tracked=$$(mktemp); synced=$$(mktemp); \
	( cd ../runtime && git ls-files ) | LC_ALL=C sort >$$tracked; \
	( cd runtime && find . ! -type d ) | sed -e 's|^\./||' \
		-e 's|^renderer/src/shaders/Makefile\.rive$$|renderer/src/shaders/Makefile|' \
		| LC_ALL=C sort >$$synced; \
	extra=$$(comm -23 $$synced $$tracked); \
	rm -f $$tracked $$synced; \
	if [ -n "$$extra" ]; then \
		>&2 echo "\033[1;31mERROR: synced runtime contains files that are not in the public rive-runtime repo:\033[0m"; \
		>&2 echo "$$extra"; \
		>&2 echo "\033[1;31mAdd them to runtime_exclude.txt before publishing.\033[0m"; \
		exit 1; \
	fi; \
	echo "OK: every synced file is public"

.PHONY: publish_pub
publish_pub:
	@echo "publishing..."
	@make clean
	@make update_cpp_runtime
	@echo "todo download all hash files, put in the correct directory"
	@echo "todo update hash checks to use package versions"
	@echo "todo actually run flutter pub publish"
	@echo "publish complete"

# =============================================================================
# Help
# =============================================================================

.PHONY: help
help:
	@echo "Rive Native Build System"
	@echo "========================"
	@echo ""
	@echo "Flutter Runtime Builds (for pub.dev releases):"
	@echo "  macos           - Build macOS release + XCFramework"
	@echo "  ios             - Build iOS (device + simulator) release + XCFramework"
	@echo "  apple           - Build both macOS and iOS"
	@echo "  android         - Build Android release"
	@echo ""
	@echo "XCFramework Only (when static libs already built):"
	@echo "  xcframework-macos  - Build macOS XCFramework only"
	@echo "  xcframework-ios    - Build iOS XCFramework only"
	@echo "  xcframework-all    - Build all XCFrameworks"
	@echo ""
	@echo "Debug Builds (for local development):"
	@echo "  macos-debug     - Build macOS debug"
	@echo "  ios-debug       - Build iOS debug (device + simulator)"
	@echo ""
	@echo "Editor Builds (for Rive Editor):"
	@echo "  macos-editor    - Build macOS for Rive Editor (includes scripting)"
	@echo ""
	@echo "Clean Targets:"
	@echo "  clean           - Remove download markers"
	@echo "  clean-native    - Remove native build output"
	@echo "  clean-all       - Full clean (markers + native output)"
	@echo ""
	@echo "Utility:"
	@echo "  update_cpp_runtime   - Sync C++ runtime from ../runtime"
	@echo "  verify_cpp_runtime   - Check the synced runtime contains only public files"
	@echo "  publish_pub          - Prepare for pub.dev publish"
	@echo "  help                 - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  CLEAN=1           - Clean before building (e.g., make macos CLEAN=1)"
	@echo ""
	@echo "Example workflow for Flutter release:"
	@echo "  make apple CLEAN=1    # Clean build macOS + iOS with XCFrameworks"
