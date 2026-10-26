// ignore_for_file: invalid_export_of_internal_element

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Key;
import 'package:flutter/widgets.dart' as flutter show Key;
import 'package:rive_native/rive_native.dart';

import 'src/rive_native_ffi.dart'
    if (dart.library.js_interop) 'src/rive_native_web.dart';

export 'src/render_resolution.dart';
export 'src/rive.dart' hide RiveProfiler;
export 'src/rive_renderer.dart';
export 'package:rive_native/math.dart';
export 'src/rive_artboard_layout.dart';
export 'src/rive_ticker_aware_painter.dart';
export 'src/rive_widget.dart';
export 'src/rive_hit_test.dart';
export 'src/rive_semantics.dart';
export 'src/defaults.dart';
export 'rive_audio.dart' show AudioSource;
export 'rive_text.dart' show Font;

/// Base class for a Rive painter.
///
/// This is used to notify listeners when the painter changes.
///
/// Optional pointer event handling can be enabled with the
/// [PainterPointerEventMixin].
abstract base class RivePainter extends ChangeNotifier {
  RivePainter();

  /// Whether the animation ticker is currently active.
  ///
  /// This method can be overridden by subclasses to provide custom ticker state
  /// logic. By default, returns false as the base implementation doesn't have
  /// direct access to the ticker.
  ///
  /// Subclasses that need ticker state should override this method and maintain
  /// a reference to their associated render box or ticker.
  bool get isTickerActive => false;

  /// Creates a new [SingleAnimationPainter] instance.
  ///
  /// - [animationName] is the name of the animation to play.
  /// - [fit] determines how the artboard is scaled to fit its container.
  /// - [alignment] determines how the artboard is positioned within its container.
  static SingleAnimationPainter animation(
    String animationName, {
    Fit fit = RiveDefaults.fit,
    Alignment alignment = RiveDefaults.alignment,
  }) =>
      SingleAnimationPainter(
        animationName,
        fit: fit,
        alignment: alignment,
      );

  /// Creates a new [StateMachinePainter] instance.
  ///
  /// - [stateMachineName] is the name of the state machine to use. If null, the
  /// default state machine will be used.
  /// - [fit] determines how the artboard is scaled to fit its container.
  /// - [alignment] determines how the artboard is positioned within its
  /// container.
  /// - [withStateMachine] is an optional callback that will be called with the.
  /// - [hitTestBehavior] determines how the state machine handles pointer events.
  /// - [cursor] determines the cursor to display when the pointer is over the
  /// state machine.
  static StateMachinePainter stateMachine({
    String? stateMachineName,
    Fit fit = RiveDefaults.fit,
    Alignment alignment = RiveDefaults.alignment,
    void Function(StateMachine)? withStateMachine,
    RiveHitTestBehavior hitTestBehavior = RiveDefaults.hitTestBehaviour,
    MouseCursor cursor = RiveDefaults.mouseCursor,
  }) =>
      StateMachinePainter(
        stateMachineName: stateMachineName,
        withStateMachine: withStateMachine,
        fit: fit,
        alignment: alignment,
        hitTestBehavior: hitTestBehavior,
        cursor: cursor,
      );
}

/// A painting context passed to a Rive RenderTexture widget which will invoke
/// the paint method as necessary to paint into the texture with a Rive
/// renderer.
///
/// The `paint` method will be invoked to paint the texture.
///
/// Override the `background` property to set the desired background color.
///
/// Override the `clear` property to `false` to skip clearing the texture before
/// painting.
///
/// Optionally override `paintCanvas` to use Flutter's native renderer
/// to draw into the widget's RenderBox on top of Rive's texture.
///
/// The `textureChanged` method will be invoked when the texture is created.
abstract base class RenderTexturePainter extends RivePainter {
  bool get clear => true;
  Color get background;
  bool paint(RenderTexture texture, double devicePixelRatio, Size size,
      double elapsedSeconds);
  bool get paintsCanvas => false;
  bool get needsClip => false;
  void paintCanvas(Canvas canvas, Offset offset, Size size) {}
  void textureChanged() {}

  /// Called before the main RenderContext frame opens to run scripted canvas
  /// draws in their own frame. Override in subclasses that manage an artboard.
  void prepassCanvases() {}
}

abstract base class RenderTexture {
  int get textureId;
  dynamic get nativeTexture;
  Widget widget({
    RenderTexturePainter? painter,
    RenderResolution resolution = RenderResolution.defaultValue,
    flutter.Key? key,
  });
  void dispose();

  bool clear(Color color, [bool write = true]);
  bool flush(double devicePixelRatio);

  int get actualWidth;
  int get actualHeight;

  /// The per-axis scale from a logical [size] to this texture's actual pixel
  /// size, so painters fill the real texture even while it lags the widget size
  /// mid-resize. Falls back to [fallbackX]/[fallbackY] when there's no size yet.
  (double, double) actualScale(
    Size size, {
    required double fallbackX,
    required double fallbackY,
  }) {
    final texW = actualWidth.toDouble();
    final texH = actualHeight.toDouble();
    final sx = (texW > 0 && size.width > 0) ? texW / size.width : fallbackX;
    final sy = (texH > 0 && size.height > 0) ? texH / size.height : fallbackY;
    return (sx, sy);
  }

  bool needsResize(int width, int height);
  Future<void> makeRenderTexture(int width, int height);

  bool get isReady;
  bool get isDisposed;
  Renderer get renderer;

  Future<ui.Image> toImage();

  void Function()? _textureChangedCallback;

  @Deprecated(
    'Use addTextureChangedListener / removeTextureChangedListener instead. '
    'A single setter cannot support multiple painters sharing one texture.',
  )
  set onTextureChanged(void Function()? callback) {
    _textureChangedCallback = callback;
  }

  final _textureChangedListeners = <void Function()>[];

  /// Adds a listener called when the underlying texture is (re)created, so
  /// multiple painters sharing one texture can each redraw into it. Remove with
  /// [removeTextureChangedListener].
  void addTextureChangedListener(void Function() callback) {
    _textureChangedListeners.add(callback);
  }

  /// Removes a listener previously added with [addTextureChangedListener].
  void removeTextureChangedListener(void Function() callback) {
    _textureChangedListeners.remove(callback);
  }

  /// Removes every texture-changed listener. Call from [dispose].
  void removeAllTextureChangedListeners() {
    _textureChangedListeners.clear();
  }

  /// Notifies every registered listener (and the deprecated single callback)
  /// that the underlying texture changed.
  void textureChanged() {
    // Iterate a copy so a listener can safely add/remove during the callback.
    for (final listener in _textureChangedListeners.toList()) {
      listener();
    }
    _textureChangedCallback?.call();
  }
}

final class UnimplementedRenderTexture extends RenderTexture {
  @override
  bool clear(Color color, [bool write = true]) {
    return true;
  }

  @override
  void dispose() {
    throw UnimplementedError();
  }

  @override
  bool flush(double devicePixelRatio) {
    throw UnimplementedError();
  }

  @override
  bool get isDisposed => throw UnimplementedError();

  @override
  bool get isReady => throw UnimplementedError();

  @override
  get nativeTexture => throw UnimplementedError();

  @override
  Renderer get renderer => throw UnimplementedError();

  @override
  Future<ui.Image> toImage() {
    throw UnimplementedError();
  }

  @override
  Widget widget({
    RenderTexturePainter? painter,
    RenderResolution resolution = RenderResolution.defaultValue,
    flutter.Key? key,
  }) {
    throw UnimplementedError();
  }

  @override
  int get actualHeight => throw UnimplementedError();

  @override
  int get actualWidth => throw UnimplementedError();

  @override
  Future<void> makeRenderTexture(int width, int height) {
    throw UnimplementedError();
  }

  @override
  bool needsResize(int width, int height) {
    throw UnimplementedError();
  }

  @override
  int get textureId => throw UnimplementedError();
}

abstract class RiveNative {
  static late RiveNative instance;
  static Completer<bool>? _initializeCompleter;
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  static Future<bool> init() async {
    if (_initializeCompleter != null) {
      return _initializeCompleter!.future;
    }
    _initializeCompleter = Completer<bool>();
    final riveNative = await makeRiveNative();
    if (riveNative != null) {
      instance = riveNative;
      Font.initialize();
      _isInitialized = true;
    } else {
      _isInitialized = false;
    }
    _initializeCompleter!.complete(_isInitialized);
    return _initializeCompleter!.future;
  }

  RenderTexture makeRenderTexture();

  /// Releases cached rendering resources retained for reuse. Safe to call
  /// when no Rive content is on screen; resources are recreated on demand.
  /// May be a no-op on platforms that cache nothing.
  void releaseRenderResources() {}

  /// When true, logs render-texture lifecycle events — create, pool reuse,
  /// release and why — to the console, with live WebGL context counts.
  /// Debug aid; web only.
  static bool debugRenderTextureLogging = false;
}
