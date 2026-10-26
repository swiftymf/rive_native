import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rive_native/platform.dart';
import 'package:flutter/widgets.dart' hide Key;
import 'package:flutter/widgets.dart' as flutter show Key;
import 'package:rive_native/rive_native.dart';
import 'package:rive_native/src/ffi/dynamic_library_helper.dart';
import 'package:rive_native/src/ffi/rive_renderer_ffi.dart';
import 'package:rive_native/src/rive.dart' as rive;

final DynamicLibrary nativeLib = DynamicLibraryHelper.nativeLib;

Set<int> _allTextures = {};
final bool Function(Pointer<Void>, bool, int) _nativeClear = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>, Bool, Uint32)>>('clear')
    .asFunction();
final bool Function(Pointer<Void>, double) _nativeFlush = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>, Float)>>('flush')
    .asFunction();
final Pointer<Void> Function(Pointer<Void>) _nativeTexture = nativeLib
    .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
      'nativeTexture',
    )
    .asFunction();

// --- Headless rendering FFI lookups ---
final Pointer<Void> Function(bool) _createHeadlessContext = nativeLib
    .lookup<NativeFunction<Pointer<Void> Function(Bool)>>(
        'createHeadlessContext')
    .asFunction();
final Pointer<Void> Function(Pointer<Void>) _headlessContextFactory = nativeLib
    .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
        'headlessContextFactory')
    .asFunction();
final Pointer<Void> Function(Pointer<Void>, int, int) _createHeadlessRenderer =
    nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>, Uint32, Uint32)>>('createHeadlessRenderer')
        .asFunction();
final bool Function(Pointer<Void>, bool, int) _headlessClear = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>, Bool, Uint32)>>(
        'headlessClear')
    .asFunction();
final bool Function(Pointer<Void>, double) _headlessFlush = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>, Float)>>(
        'headlessFlush')
    .asFunction();
final Pointer<Void> Function(Pointer<Void>) _headlessMakeRenderer = nativeLib
    .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
        'headlessMakeRenderer')
    .asFunction();
final bool Function(Pointer<Void>, Pointer<Uint8>) _headlessReadPixels =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Uint8>)>>(
            'headlessReadPixels')
        .asFunction();
final void Function(Pointer<Void>) _destroyHeadlessRenderer = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'destroyHeadlessRenderer')
    .asFunction();
final void Function(Pointer<Void>) _destroyHeadlessContext = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'destroyHeadlessContext')
    .asFunction();

base class _NativeRenderTexture extends RenderTexture {
  @override
  int get textureId => _textureId;

  @override
  Pointer<Void> get nativeTexture => _nativeTexture(_rendererPtr);

  final MethodChannel methodChannel;
  int _textureId = -1;
  Pointer<Void> _rendererPtr = nullptr;
  bool _disposed = false;

  _NativeRenderTexture(this.methodChannel);

  @override
  bool get isReady => _textureId != -1;

  @override
  void dispose() {
    _disposed = true;
    if (_textureId != -1) {
      _allTextures.remove(_textureId);
      _disposeTexture(_textureId);
      _textureId = -1;
    }
  }

  int _width = 0;
  int _height = 0;
  int _actualWidth = 0;
  int _actualHeight = 0;

  @override
  int get actualWidth => _actualWidth;
  @override
  int get actualHeight => _actualHeight;

  @override
  bool needsResize(int width, int height) =>
      width != _width || height != _height;

  @override
  bool get isDisposed => _textureId == -1;

  final List<int> _deadTextures = [];

  void _disposeTextures() {
    _disposeTimer = null;
    var textures = _deadTextures.toList();
    _deadTextures.clear();
    for (final texture in textures) {
      methodChannel.invokeMethod('removeTexture', {'id': texture});
    }
  }

  Timer? _disposeTimer;
  void _disposeTexture(int id) {
    _deadTextures.add(id);
    if (_disposeTimer != null) {
      return;
    }

    _disposeTimer = Timer(const Duration(seconds: 1), _disposeTextures);
  }

  @override
  Future<void> makeRenderTexture(int width, int height) async {
    assert(width >= 0 && height >= 0,
        'Rive render texture width and height must be greater than or equal to 0. Width: $width, Height: $height');
    if (_disposed) {
      return;
    }
    // Immediately update cached values in-case we redraw during udpate.
    _width = width;
    _height = height;
    final result = await methodChannel.invokeMethod('createTexture', {
      'width': width == 0 ? 1 : width,
      'height': height == 0 ? 1 : height,
    });
    int? textureId = result['textureId'] as int?;
    // Disposed while the platform call was in flight: the texture it just
    // created would never be cleaned up through dispose(), so remove it now.
    if (_disposed) {
      if (textureId != null) {
        methodChannel.invokeMethod('removeTexture', {'id': textureId});
      }
      return;
    }
    _actualWidth = width;
    _actualHeight = height;
    String renderer = result['renderer'] as String;
    _rendererPtr = Pointer<Void>.fromAddress(
        int.parse(renderer.substring(renderer.indexOf('x') + 1), radix: 16));

    if (textureId != null) {
      _allTextures.add(textureId);
    }
    if (_textureId != -1) {
      _allTextures.remove(_textureId);
      _disposeTexture(_textureId);
    }

    if (textureId == null) {
      _textureId = -1;
    } else {
      _textureId = textureId;
    }
  }

  @override
  Widget widget({
    RenderTexturePainter? painter,
    RenderResolution resolution = RenderResolution.defaultValue,
    flutter.Key? key,
  }) =>
      _RiveNativeView(this, painter, resolution, key: key);

  void _markDestroyed() {
    _rendererPtr = nullptr;
    final textureIdToDestroy = _textureId;
    if (textureIdToDestroy != -1) {
      _textureId = -1;
      _allTextures.remove(textureIdToDestroy);
      _disposeTexture(textureIdToDestroy);
      _width = _height = 0;
      _actualWidth = _actualHeight = 0;
    }
  }

  @override
  bool clear(Color color, [bool write = true]) {
    // ignore: deprecated_member_use
    if (!_nativeClear(_rendererPtr, write, color.value)) {
      _markDestroyed();
      return false;
    }
    return true;
  }

  @override
  bool flush(double devicePixelRatio) {
    if (!_nativeFlush(_rendererPtr, devicePixelRatio)) {
      _markDestroyed();
      return false;
    }
    return true;
  }

  @override
  Renderer get renderer => FFIRiveRenderer(rive.Factory.rive, _rendererPtr);

  @override
  Future<ui.Image> toImage() {
    final scene = ui.SceneBuilder();
    scene.addTexture(
      _textureId,
      width: _width.toDouble(),
      height: _height.toDouble(),
      freeze: true,
    );

    final build = scene.build();
    return build.toImage(_width, _height);
  }
}

/// A headless render texture for test environments. Uses FFI-based headless
/// Metal rendering instead of Flutter's method channels/texture registry.
base class _HeadlessRenderTexture extends RenderTexture {
  final Pointer<Void> _headlessContext;
  Pointer<Void> _rendererPtr = nullptr;
  int _width = 0;
  int _height = 0;

  _HeadlessRenderTexture(this._headlessContext);

  @override
  int get textureId => -1; // Not used in headless mode.

  @override
  dynamic get nativeTexture => nullptr;

  @override
  bool get isReady => _rendererPtr != nullptr;

  @override
  bool get isDisposed => _rendererPtr == nullptr;

  @override
  int get actualWidth => _width;

  @override
  int get actualHeight => _height;

  @override
  bool needsResize(int width, int height) =>
      width != _width || height != _height;

  @override
  Future<void> makeRenderTexture(int width, int height) async {
    if (_rendererPtr != nullptr) {
      _destroyHeadlessRenderer(_rendererPtr);
    }
    _width = width;
    _height = height;
    _rendererPtr = _createHeadlessRenderer(
      _headlessContext,
      width == 0 ? 1 : width,
      height == 0 ? 1 : height,
    );
  }

  @override
  bool clear(Color color, [bool write = true]) {
    if (_rendererPtr == nullptr) return false;
    // ignore: deprecated_member_use
    return _headlessClear(_rendererPtr, write, color.value);
  }

  @override
  bool flush(double devicePixelRatio) {
    if (_rendererPtr == nullptr) return false;
    return _headlessFlush(_rendererPtr, devicePixelRatio);
  }

  @override
  Renderer get renderer {
    final ptr = _headlessMakeRenderer(_rendererPtr);
    return FFIRiveRenderer.fromPointer(ptr, rive.Factory.rive);
  }

  @override
  Future<ui.Image> toImage() async {
    if (_rendererPtr == nullptr || _width == 0 || _height == 0) {
      throw StateError('Headless texture not ready for toImage()');
    }
    final bufferSize = _width * _height * 4;
    final pixelBuffer = malloc.allocate<Uint8>(bufferSize);
    try {
      final success = _headlessReadPixels(_rendererPtr, pixelBuffer);
      if (!success) {
        throw StateError('Failed to read pixels from headless renderer');
      }
      // The C++ side already converts BGRA→RGBA.
      final pixels = Uint8List.fromList(pixelBuffer.asTypedList(bufferSize));
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        _width,
        _height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return completer.future;
    } finally {
      malloc.free(pixelBuffer);
    }
  }

  @override
  Widget widget({
    RenderTexturePainter? painter,
    RenderResolution resolution = RenderResolution.defaultValue,
    flutter.Key? key,
  }) =>
      // The real render-object widget works against the headless texture: the
      // TextureLayer composite is skipped because [textureId] is always -1, so
      // the full layout/allocation/policy pipeline runs in widget tests.
      _RiveNativeView(this, painter, resolution, key: key);

  @override
  void dispose() {
    if (_rendererPtr != nullptr) {
      _destroyHeadlessRenderer(_rendererPtr);
      _rendererPtr = nullptr;
    }
  }
}

class _RiveNativeFFI extends RiveNative {
  final methodChannel = const MethodChannel('rive_native');
  Pointer<Void> _headlessContext = nullptr;

  @override
  RenderTexture makeRenderTexture() {
    if (Platform.instance.isTesting && _headlessContext != nullptr) {
      return _HeadlessRenderTexture(_headlessContext);
    }
    return _NativeRenderTexture(methodChannel);
  }

  Future<void> initialize() async {
    if (Platform.instance.isTesting) {
      // Headless rendering is only available when the native lib was built
      // with the headless symbols. `./build.sh shared` includes them
      // (headless_rendering.mm is gated on `not flutter_runtime` in
      // premake5.lua); the flutter-runtime builds shipped to apps do not.
      if (!nativeLib.providesSymbol('createHeadlessContext')) {
        return;
      }
      // Create a headless render context for test mode so that Factory.rive
      // is available without the Flutter platform plugin.
      // Force atomic mode so rendering is deterministic across GPUs.
      _headlessContext = _createHeadlessContext(true);
      if (_headlessContext != nullptr) {
        final factoryPtr = _headlessContextFactory(_headlessContext);
        if (factoryPtr != nullptr) {
          (rive.Factory.rive as FFIRiveFactory).pointer = factoryPtr;
        }
      }
      return;
    }
    try {
      final result = await methodChannel.invokeMethod('getRenderContext', {});

      String rendererContext = result['rendererContext'] as String;
      if (rendererContext == 'android') {
        // on android we grab the global riveFactory.
        final Pointer<Void> Function() riveFactory = nativeLib
            .lookup<NativeFunction<Pointer<Void> Function()>>(
              'riveFactory',
            )
            .asFunction();
        (rive.Factory.rive as FFIRiveFactory).pointer = riveFactory();
      } else {
        (rive.Factory.rive as FFIRiveFactory).pointer =
            Pointer<Void>.fromAddress(int.parse(
                rendererContext.substring(rendererContext.indexOf('x') + 1),
                radix: 16));
      }
    } catch (e) {
      var message = '''
Error creating Rive Native render context
It could be because the native library is not loaded.

Try running the following command to fix this issue:
`dart run rive_native:setup --verbose --clean --platform <platform>`

Error: $e
''';
      debugPrint(message);
      rethrow;
    }
  }
}

Future<RiveNative?> makeRiveNative() async {
  WidgetsFlutterBinding.ensureInitialized();
  final riveNative = _RiveNativeFFI();
  await riveNative.initialize();
  return riveNative;
}

class _RiveNativeView extends LeafRenderObjectWidget {
  final RenderTexture renderTexture;
  final RenderTexturePainter? painter;
  final RenderResolution resolution;
  const _RiveNativeView(this.renderTexture, this.painter, this.resolution,
      {super.key});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RiveNativeViewRenderObject(renderTexture, painter)
      ..renderResolution = resolution
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..tickerModeEnabled = TickerMode.of(context);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RiveNativeViewRenderObject renderObject,
  ) {
    renderObject
      ..renderTexture = renderTexture
      ..painter = painter
      ..renderResolution = resolution
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..tickerModeEnabled = TickerMode.of(context);
  }

  @override
  void didUnmountRenderObject(
    covariant _RiveNativeViewRenderObject renderObject,
  ) {
    renderObject.painter = null;
  }
}

class _RiveNativeViewRenderObject extends RiveNativeRenderBox
    with WidgetsBindingObserver {
  _RiveNativeViewRenderObject(
    super._renderTexture,
    RenderTexturePainter? renderTexturePainter,
  ) {
    painter = renderTexturePainter;

    // Add an observer to monitor the widget lifecycle changes
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      restartTickerIfStopped();
      markNeedsLayout();
    }
  }

  @override
  void detach() {
    // Cancel in-flight resize work so it doesn't fire while detached (e.g.
    // scrolled out of a ListView).
    _resizeSettleTimer?.cancel();
    _resizeSettleTimer = null;
    super.detach();
  }

  @override
  void dispose() {
    _resizeSettleTimer?.cancel();
    _resizeSettleTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Latest target size requested by layout, in physical pixels.
  (int, int) _latestTargetTextureSize = (0, 0);

  Timer? _resizeSettleTimer;

  @override
  void performLayout() {
    super.performLayout();
    if (owner == null || !attached) {
      return;
    }

    final (targetWidth, targetHeight) = targetTextureSize();

    if (!renderTexture.needsResize(targetWidth, targetHeight)) {
      // Keep the composited id current — a shared texture can be recreated by
      // another widget.
      if (textureIdToUse != renderTexture.textureId) {
        textureIdToUse = renderTexture.textureId;
        markNeedsPaint();
      }
      return;
    }

    // Create the first texture immediately so there's something to show.
    if (renderTexture.textureId == -1) {
      unawaited(_createTexture(targetWidth, targetHeight));
      return;
    }

    // Reuse the current texture while the size changes (Flutter stretches it),
    // re-fitting its content to the new size each frame so it tracks the widget.
    restartTickerIfStopped();
    if (rivePainter != null) {
      // We own the content — redraw it. forceShouldAdvance keeps the ticker
      // running through the resize so a settled graphic keeps recompositing
      // (otherwise it'd freeze stretched until the next repaint).
      paintTexture(0, forceShouldAdvance: true);
    } else {
      // Shared/editor panel: we own the texture but not the content. Notify the
      // painters drawing into it to redraw — they won't repaint on their own if
      // their size didn't change (e.g. a vertical resize of a fixed-width grid).
      renderTexture.textureChanged();
    }

    _latestTargetTextureSize = (targetWidth, targetHeight);
    _scheduleCreateTexture();
  }

  // Recreate the texture at the latest size, throttled to one every
  // [RiveNativeRenderBox.textureResizeInterval]: the timer isn't reset on each
  // resize, so it fires periodically through a drag and re-arms while the size
  // keeps moving.
  void _scheduleCreateTexture() {
    if (_resizeSettleTimer?.isActive ?? false) {
      return;
    }
    _resizeSettleTimer = Timer(RiveNativeRenderBox.textureResizeInterval, () {
      if (!attached) {
        return;
      }
      restartTickerIfStopped();
      final (width, height) = _latestTargetTextureSize;
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        if (!attached) {
          return;
        }
        await _createTexture(width, height);
        // The size moved again before we finished — schedule another pass.
        if (attached && _latestTargetTextureSize != (width, height)) {
          _scheduleCreateTexture();
        }
      });
    });
  }

  Future<void> _createTexture(int targetWidth, int targetHeight) async {
    if (owner == null || !attached) {
      return;
    }
    // Only one creation in flight at a time — `makeRenderTexture` is async, so
    // without this every layout while the first texture is still being created
    // would spawn another, churning (and potentially leaking) native textures.
    if (_isCreatingTexture) {
      return;
    }
    if (!(renderTexture.needsResize(targetWidth, targetHeight) ||
        renderTexture.isDisposed)) {
      return;
    }
    _isCreatingTexture = true;
    try {
      await renderTexture.makeRenderTexture(targetWidth, targetHeight);
      if (!attached) {
        return;
      }
      // Draw into the new texture; the base listener handles the delayed swap.
      rivePainter?.textureChanged();
      renderTexture.textureChanged();
      markNeedsPaint();
    } catch (error, stackTrace) {
      debugPrint('$error $stackTrace');
    } finally {
      _isCreatingTexture = false;
    }
  }

  bool _isCreatingTexture = false;

  @override
  ui.Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);

    if (!renderTexture.isReady || textureIdToUse == -1) {
      return;
    }
    // Composite to the current bounds — during a resize this stretches the
    // previous texture so it scales smoothly until the new one is ready.
    context.addLayer(
      TextureLayer(
        rect: offset & size,
        textureId: textureIdToUse,
        filterQuality: FilterQuality.low,
      ),
    );

    final painter = rivePainter;
    if (painter != null && painter.paintsCanvas) {
      painter.paintCanvas(context.canvas, offset, size);
    }
  }
}
