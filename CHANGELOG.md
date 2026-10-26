## 0.1.11

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.
- Adds `RenderResolution` to control how a `Factory.rive` texture sizes its backing store: `display()` (default — layout × device pixel ratio × ancestor paint scale), `layout({scale})` (layout × device pixel ratio, ignores ancestor transforms), and `fixed(width, height)` (explicit physical pixels). Available on `RenderTexture.widget`, `RiveArtboardWidget`, and `RiveProceduralRenderingWidget`.
- **Web behavior change**: `RenderResolution.display()` now accounts for ancestor transforms on web, matching native — an upscaled widget renders sharp instead of stretched. Pass `RenderResolution.layout()` for the previous behavior.
- Adds `RiveNative.instance.releaseRenderResources()` to release cached render resources (web: pooled textures and the probe context), recreated on demand. No-op on other platforms.
- Adds `RiveNative.debugRenderTextureLogging` (web): logs render-texture create/reuse/release with live WebGL context counts.

### Fixes

- Windows: fixed a crash or hang when disposing a render texture with a frame in flight, such as closing the app under load or the desktop going to sleep. The fence wait thread could outlive teardown and either touch a destroyed texture registrar or block shutdown indefinitely (see core runtime issue [#86](https://github.com/rive-app/rive-runtime/issues/86)).
- Texture allocations under `display` and `layout` are capped at 4096 logical pixels per axis (aspect preserved), preventing runaway allocations under large ancestor scales.
- Web: canvas backing stores are clamped to the GPU's maximum render-target size.
- Web: render textures release their WebGL contexts on dispose (bounded reuse pool), browser-evicted contexts are purged instead of reused, and the MSAA probe context is released at startup — fixes context-limit exhaustion and permanently blank widgets.

## 0.1.10

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Rive Renderer (`Factory.rive`) rendering issues on Linux with later versions of Flutter (3.38+, see Flutter issue [182998](https://github.com/flutter/flutter/issues/182998))
- Various Rive scripting fixes and updates, notably:
  - Updated Luau to 0.728
  - Fixed the Lua `Data` global not being initialized, which left view model constructors such as `Data.MyViewModel.new()` unavailable to scripts

## 0.1.9

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixed a "RenderBox was not laid out" crash in `RiveNativeRenderBox.paint` (`Factory.rive`) that could occur when painting during certain transitions. See https://github.com/rive-app/rive-flutter/issues/642.
- Touch and stylus pointer up (and cancel) now also dispatch a pointer exit, so listeners receive a Pointer Exit when a finger or pen lifts. This keeps enter/exit symmetric on mobile and matches other Rive runtimes. Mouse and trackpad pointers are unaffected, their exit still comes from the pointer leaving the artboard/widget.
- Fixed a crash when using `desktop_multi_window` on Windows with MicroProfile GPU init

## 0.1.8

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixed Rive widgets blurring (`Factory.rive`) during parent rotation/skew animations.
- Improved `RiveWidget` (`Factory.rive`) flickering when resized. The render texture is reused and scaled during a resize, recreated at the new size on a throttle, and only swapped in once it has been drawn.

### Changes

- Deprecated `RenderTexture.onTextureChanged` in favour of `addTextureChangedListener` / `removeTextureChangedListener`, which allow multiple painters to share a single texture.
- Added `RiveNativeRenderBox.textureResizeInterval` to tune how often the texture is recreated while resizing.

## 0.1.7

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Breaking Changes

- Expose audio events through the Dart API. `Event` is a sealed class and `EventType` gains an `audio` value, so exhaustive `switch` statements over either now require a new `AudioRuntimeEvent` / `EventType.audio` arm.
- State machine event listeners now receive `AudioRuntimeEvent`s alongside `GeneralEvent` and `OpenUrlEvent`. Listeners that branch on event type with non-exhaustive `if`/`is` checks will see the new type pass through unhandled.

### Fixes

- Fixed a Windows crash in the `removeTexture` method channel handler when the texture id arrived as `int32_t` rather than `int64_t`. Most commonly seen when dragging the app window between displays with different DPI settings, or when rapidly creating/disposing render textures.

## 0.1.6

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixed [623](https://github.com/rive-app/rive-flutter/issues/623) - Explicitly nil Metal ivars in dealloc to prevent use-after-free on teardown

## 0.1.5

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

- Add optional `viewModelInstance` parameter to `File.artboardToBind`, allowing a `ViewModelInstance` to be bound to a `BindableArtboard`. When provided, the view model instance is set on the artboard property in the core runtime.

## 0.1.4

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Build & Platform Updates

- Rive Renderer support for Linux
- Linux is now fully supported. Known issue: arm64 builds are not yet included; for now, build manually: https://rive.app/docs/runtimes/flutter/rive-native#building-rive-native
- Fixes a build issue where scripting build files were missing. We previously did not include the `scripting` folder, which is now required by other build files.
- Fixed a build issue when running ``dart run rive_native:setup --build`.
- Resolves `dart run rive_native:setup` concurrency issue [rive-flutter#609](https://github.com/rive-app/rive-flutter/issues/609). Downloads now use a unique temporary directory to support concurrent CLI runners.

## 0.1.3

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Build & Platform Updates

- Adds Swift Package Manager support. Resolves issue [557](https://github.com/rive-app/rive-flutter/issues/557)

## 0.1.2

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.
- Updated the minimum Flutter version to `3.28.0`. The Android platform code requires the new `onSurfaceCleanup` and `onSurfaceAvailable` methods, see [SurfaceProducer](https://api.flutter.dev/javadoc/io/flutter/view/TextureRegistry.SurfaceProducer.Callback.html).
- Add `enumType` string getter to `ViewModelInstanceEnum` which returns the name of the enum (not the property name).
- Add `valueStream<T>` to data binding properties that are observable (implementations of `ViewModelInstanceObservableValue`), which returns a `Stream<T>`. For example:

```
ViewModelInstanceNumber? numberProperty = viewModelInstance!.number('age');
Stream<double> stream = numberProperty!.valueStream;
```

### Fixes

- Fixed iOS/macOS build issues when using custom schemes and flavors. See issue [594](https://github.com/rive-app/rive-flutter/issues/594).

## 0.1.1

- Adds runtime [Rive Scripting](https://rive.app/docs/scripting/getting-started) support.
- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixed [585](https://github.com/rive-app/rive-flutter/issues/585) - missing `artboard` `DataType` enum.

## 0.1.0

### Fixes

- Fixed Android build issues in certain environments. See issue [555](https://github.com/rive-app/rive-flutter/issues/555). Build commands are now executed from Gradle instead of CMakeLists, and the setup process automatically skips `rive_native:setup` if the required libraries are already downloaded.

### Build & Platform Updates

- Android: Added support for skipping automated setup by setting `rive.native.skipSetup=true` in your app's `gradle.properties`. When enabled, you must manually run `dart run rive_native:setup --verbose --clean --platform android` to download the required libraries.

## 0.0.17

- Marks methods to access text runs and state machine inputs as deprecated. While this functionality won't be removed in the near future, we encourage adoption of data binding to future-proof your Rive usage.

### Fixes

- Improved library loading and error message. See issue [566](https://github.com/rive-app/rive-flutter/issues/566)
- Fixed layout issues that occurred on first render when using `Fit.layout` by correcting the order of artboard resizing and advancing calls. Added a new `RiveArtboardLayoutMixin` that provides common layout options for painters, including fit mode, alignment, and scale factor controls.
- Resolves an issue where under some conditions the graphic may not restart the animation ticker. Adds a `isTickerActive` to `RivePainter`.
- Fixed a lifetime issue with `FileAsset`s when the owning Rive `File` is destroyed.
- Only send `textureFrameAvailable` on main (platform) thread (iOS and macOS). This likely resolves crashes observed during Flutter engine teardown when using `Factory.rive`.

## 0.0.16

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixes rendering issues on certain Android devices.
- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Build & Platform Updates

- Bump minimum supported dependency for Flutter to `3.27.0` and Dart to `3.6.0`.

## 0.0.15

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixed [556](https://github.com/rive-app/rive-flutter/issues/556). `getTransformTo` can return a negative width and height scale resulting in a texture creation with a negative width/height.
- Fixed [561](https://github.com/rive-app/rive-flutter/issues/561) Flutter web not initializing.

## 0.0.14

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Graphics memory leak on Android when using the Rive Renderer.

## 0.0.13

- Added multi-touch support
- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixed [544](https://github.com/rive-app/rive-flutter/issues/544), which resulted in settled graphics not being visible after backgrounding the app when using `Factory.rive`.
- Fixed [529](https://github.com/rive-app/rive-flutter/issues/529), an assertion/crash on Windows debug builds when accessing `front()` on an empty vector.
- Fixed an issue where graphics would not update after layout when using the Flutter renderer.

### Build & Platform Updates

- Included `pdb` symbol files for `rive_native` on Windows to assist in debugging native errors.

## 0.0.12

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.
- Reduced the number of texture allocations made when resizing widgets using `Factory.rive`, improving memory efficiency and performance.
- Enhanced painting and texture creation behavior when resizing widgets or windows with `Factory.rive`, resulting in smoother widget resizing.
- Better aligned the native and web implementations to ensure consistent behavior across all platforms.

### Fixes

- Resolved [issue #498](https://github.com/rive-app/rive-flutter/issues/498) where `Fit.scaleDown` was not working correctly with `Factory.rive`.
- Resolved [an issue](https://community.rive.app/c/support/rive-native-rendering-visible-aliasing-jagged-edges) where upscaling Rive widget transforms resulted in blurry textures when using `Factory.rive`.
- Fixed layout problems that occurred when certain `Fit` modes were used and the user switched to a different DPI screen.
- Adds `addAdvanceRequestListener` to `StateMachine` and `ViewModelInstance`. This is used internally by the `rive` package to force advance on view model property change, and input changes.
- Fixed instances where pointer exit was not working

## 0.0.11

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Fixed a crash in `preCommitCallback` for iOS and macOS.

### Build & Platform Updates

- Builds the native iOS and macOS libraries with Xcode 16.1 (bumped up from 15.4)

## 0.0.10+1

- Fixed hash verification

## 0.0.10

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.
- Expose `localBounds` on `Component`.

### Fixes

- Fixes an issue where graphics might settle (pause) too soon, by forcing an advance when the `elapsedSeconds` is zero.
- Fixes a potential crash in Android when a native pointer is no longer valid
- Fixed a crash when shutting down on Windows
- Fixed deleting the wrong texture from the wrong WebGL context

## 0.0.9

- Updates the Rive C++ runtime and renderer for the latest features, bug fixes, and performance improvements.

### Fixes

- Add missing `pointerExit` event logic.
- Fixed [507](https://github.com/rive-app/rive-flutter/issues/507) - Tests fail on Linux and Windows as native libs are not discoverable.
- Fixed incorrect key forwarding to child widgets.

## 0.0.8

- Expose `width` and `height` getters for `ImageAsset`. See issue [501](https://github.com/rive-app/rive-flutter/issues/501). This is only exposed to support older workflows. We now recommend using [Data Binding images](https://rive.app/docs/runtimes/data-binding#images). You can also alternatively expose the width and height of the component through data binding and listen to changes.

### Fixes

- Fixed a memory leak when listening to Rive Events that had Audio events. See issue [494](https://github.com/rive-app/rive-flutter/issues/494)
- Fixed a memory issue on WASM where large .riv files could invalidate our backing TypedArray views. This fix recreates these views if they are detached. See: https://github.com/emscripten-core/emscripten/issues/7294

## 0.0.7

- Updates the Rive C++ runtime and renderer for the latest bug fixes and performance improvements.

### Fixes

- Fixed running out of GL contexts by recycling HTML canvases
- Fixed an issue on Web (Rive Renderer) where certain graphics would settle (pause) too soon when exiting a settled state.
- Fixed an issue where the state machine would settle/pause too soon when resizing the widget (or native window) and when re entering from a backgrounded state (Android). See issue [496](https://github.com/rive-app/rive-flutter/issues/496)

### Build & Platform Updates

- Linux: Initial Linux support (Flutter renderer).
- Fixed testing libraries not available when using `rive_native` as a Pub package. `rive_native` now copies the native libraries to the local app `build` directory.

## 0.0.6

- Updates the Rive C++ runtime and renderer for the latest bug fixes and performance improvements.

### Fixes

- A dual mutex deadlock on iOS/macOS during window/texture resizing under certain conditions.
- An issue where the Rive Renderer requests a repaint on a disposed render object.

## 0.0.5

### Fixes

- Fixed a crash on iOS for the Flutter renderer on cleanup.

## 0.0.4

- Updates the Rive C++ runtime and renderer for the latest bug fixes and performance improvements.

### New Features

- **Data binding artboards**:
  You can now data bind artboards and update them programatically. Access a `ViewModelInstanceArtboard` by its path using `artboard(String path)` on a view model instance. To update, set the `value` by passing in a `BindableArtboard`. Create a `BindableArtboard` from a Rive file: `riveFile.artboardToBind(String name)` See the [runtime](https://rive.app/docs/runtimes/data-binding) docs for data binding artboards.
- **Detect Rive Renderer support**:
  You can now detect Rive Renderer support by doing `Factory.rive.isSupported` after `RiveNative.init()`.

### Fixes

- Fixed a crash when using the Flutter renderer.
- Allow Rive Native to still work even if the Rive Renderer context does not initialize.

## 0.0.3

- Updates the Rive C++ runtime and renderer for the latest bug fixes and performance improvements.

### New Features

- **Data binding lists**:
  You can now get a list property on a `ViewModelInstance` by its path using `list(String path)`. On this property you can perform common list operations, such as, `add`/`remove`/`insert`. See [Editor](https://rive.app/docs/editor/data-binding/lists) and [runtime](https://rive.app/docs/runtimes/data-binding) docs for data binding lists.

### Fixes

- Fixed a crash on Android when backgrounding the app using the Rive Renderer. See issue [481](https://github.com/rive-app/rive-flutter/issues/481).

### Build & Platform Updates

- Android: add `x86`/`x86_64` arch support.
- Android: support 16 KB page sizes, see issue [479](https://github.com/rive-app/rive-flutter/issues/479).
- Android: bump `compileSdk` from 34 to 35.

## 0.0.2

- Updates the Rive C++ runtime and renderer for the latest bug fixes and performance improvements.

### New Features

- **Data binding images:**  
  You can now get an image property on a `ViewModelInstance` by its path using `image(String path)`, and set its `value`.
  - Use `Factory.rive.decodeImage` or `Factory.flutter.decodeImage` to create a `RenderImage`.
  - Set the `value` to `null` to clear the image and free up resources.
- Exposes the `name` string getter on `Artboard`, `Animation`, and `StateMachine`.

### Fixes

- Fixed a build issue when creating an Android AAR module. `rive_native` now accounts for the `plugins_build_output` directory when running the build scripts.
- Fixed an issue where Pub would remove a required Makefile during package publishing. The Makefile is necessary for manually building `rive_native` libraries using `dart run rive_native:setup --build`.

## 0.0.1

- Updates the Rive C++ runtime and renderer for the latest bug fixes and performance improvements.

### Fixes

- Fixed a build issue when building directly from Xcode for iOS and macOS.
- Various rendering and runtime fixes.

## 0.0.1-dev.8

### New Features

- Data binding 🚀. See the [data binding documentation](https://rive.app/docs/runtimes/data-binding) and the updated example app for more info.

### Fixes

- Platform dependent CMakeList.txt instructions. Fixes Android and Windows rive_native setup for certain Windows environments. See issue [471](https://github.com/rive-app/rive-flutter/issues/471)
- Support for [Workspaces](https://dart.dev/tools/pub/workspaces) in `rive_native:setup`, see issue [467](https://github.com/rive-app/rive-flutter/issues/467). Thanks [tpucci](https://github.com/tpucci) for the contribution.
- Textures now use pre-multiplied alpha, which may fix dark edges around alpha textures [ad7c295](https://github.com/rive-app/rive-android/commit/ad7c29530cbeb7f7f1575e236f584dfc7ccd7de9)
- Fixed an OpenGL buffer race condition [b001b21](https://github.com/rive-app/rive-android/commit/b001b2144aa765db1926360f34c16ece913c3756)

## 0.0.1-dev.7

### New Features

- Initial support for text follow path (early access)

### Fixes

- Latest Rive Runtime and Renderer fixes and improvements
  - Fixes rendering glitches on certain device hardware
- **Android and Windows building**: Fixed executing the download scripts from the wrong path in `CMakeLists.txt`. See issue [460](https://github.com/rive-app/rive-flutter/issues/460), Dart does not allow executing `pub` commands from the pub cache directory.
- **iOS and macOS build flavor support**: Fixed an issue where rive_native could not build when using Flutter flavors, see issue [460](https://github.com/rive-app/rive-flutter/issues/460).
- **Reduce Pub package size and fix building**: Reduce dependencies included when publishing to Pub, and fix manual library building

## 0.0.1-dev.6

### New Features

- **Android Support**: Added support for Android (arm, arm64) with Rive Renderer and Flutter Renderer (Skia/Impeller).
- **iOS Emulator Support**: Added support for running on iOS emulators.
- **Layout Support**: Introduced [Layout](https://rive.app/docs/editor/layouts/layouts-overview) support.
- **Scrolling Support**: Added [Scrolling](https://rive.app/docs/editor/layouts/scrolling) support.
- **N-Slicing Support**: Added [N-Slicing](https://rive.app/docs/editor/layouts/n-slicing) support.
- **Feathering**: Added support for Feathering.
- **Nested Inputs**: Added [nested inputs](https://rive.app/docs/runtimes/state-machines#nested-inputs) accessible via the optional `path` parameter in `StateMachine.number`, `StateMachine.boolean`, and `StateMachine.trigger`.
- **Nested Text Runs**: Added support for [nested text runs](https://rive.app/docs/runtimes/text#read%2Fupdate-nested-text-runs-at-runtime), accessible via the optional `path` parameter in `artboard.getText(textRunName, path: path)`.
- **Text Run Setters**: Added setters for [text runs](https://rive.app/docs/runtimes/text) (including nested text runs) using `artboard.setText(textRunName, updatedValue, path: path)`.
- **Rive Events**: Added support for [Rive Events](https://rive.app/docs/runtimes/rive-events).
- **Out-of-Band Assets**: Added support for [out-of-band assets](https://rive.app/docs/runtimes/loading-assets).
- **Procedural Rendering**: Introduced `RiveProceduralRenderingWidget` and `ProceduralPainter`.

### Fixes

- **Windows Build Scripts**: Fixed build scripts for Windows.
- **Latest Rive C++ runtime**: Updates to the latest core runtime with various improvements and fixes.

### Breaking Changes

- **StateMachinePainter**: `StateMachinePainter` and `RivePainter.stateMachine` no longer require a `stateMachineName` parameter. It is now optional. If `null`, the default state machine will be used.
- **Rive Widgets**: `RiveArtboardWidget` and `RiveFileWidget` now require a `RivePainter`.

---

## 0.0.1-dev.5

- Initial prerelease 🎉
