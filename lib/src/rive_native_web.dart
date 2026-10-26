// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:meta/meta.dart' show internal, visibleForTesting;
import 'package:web/web.dart' as web;

import 'package:flutter/widgets.dart' hide Key;
import 'package:flutter/widgets.dart' as flutter show Key;
import 'package:rive_native/rive_native.dart';
import 'package:rive_native/src/wasm_version.dart';
import 'package:rive_native/src/web/layout_engine_web.dart';
import 'package:rive_native/src/web/rive_audio_web.dart';
import 'package:rive_native/src/web/rive_focus_web.dart';
import 'package:rive_native/src/web/rive_semantic_web.dart';
import 'package:rive_native/src/web/rive_luau_web.dart';
import 'package:rive_native/src/web/rive_pathops_web.dart';
import 'package:rive_native/src/web/rive_renderer_web.dart';
import 'package:rive_native/src/web/rive_text_web.dart';
import 'package:rive_native/src/web/scripting_workspace_web.dart';
import 'package:web/web.dart' as html;

extension RiveNativeJsExtension on js.JSFunction {
  @js.JS('call')
  external js.JSAny? callAsFunctionEx([
    js.JSAny? thisArg,
    js.JSAny? arg1,
    js.JSAny? arg2,
    js.JSAny? arg3,
    js.JSAny? arg4,
    js.JSAny? arg5,
    js.JSAny? arg6,
    js.JSAny? arg7,
    js.JSAny? arg8,
    js.JSAny? arg9,
    js.JSAny? arg10,
    js.JSAny? arg11,
    js.JSAny? arg12,
    js.JSAny? arg13,
    js.JSAny? arg14,
    js.JSAny? arg15,
    js.JSAny? arg16,
    js.JSAny? arg17,
    js.JSAny? arg18,
    js.JSAny? arg19,
  ]);
}

base class _WebRenderTexture extends RenderTexture {
  @override
  int get textureId => -1;

  // late int _webRenderer;
  static int _canvasCounter = 0;
  js.JSObject? jsRenderContext;
  js.JSAny? jsRenderContextPtr;
  final String rendererId;
  final html.HTMLCanvasElement canvasElement;
  web.ResizeObserver? _resizeObserver;

  /// The raw WebGL2 context from the glue's renderer object, cached because
  /// [isReady] runs every frame. Nulled on release.
  js.JSObject? _gl;

  static final js.JSString _isContextLostKey = 'isContextLost'.toJS;

  @override
  bool get isReady => canvasElement.isConnected && !_contextLost;

  /// Whether the WebGL context backing this texture is gone — released, or
  /// evicted by the browser (context pressure, GPU reset). GL calls against
  /// a lost context are silently ignored, so painting it renders nothing.
  bool get _contextLost {
    final gl = _gl;
    return gl == null || gl.callMethod<js.JSBoolean>(_isContextLostKey).toDart;
  }

  /// Disposed textures kept for reuse. A pooled texture keeps its canvas and
  /// live WebGL2 context, and browsers cap live contexts (~16 per process) —
  /// so the pool is bounded and dispose genuinely releases beyond the cap.
  /// The cap covers realistic churn bursts (route pops, editor pane
  /// closures) without pinning a whole page's high-water mark forever.
  static const int _maxPoolSize = 4;
  static final List<_WebRenderTexture> _pool = [];

  static _WebRenderTexture make() {
    while (_pool.isNotEmpty) {
      final pooled = _pool.removeAt(0);
      if (!pooled._contextLost) {
        _debugLogTexture('${pooled.rendererId} reused from pool');
        return pooled;
      }
      // The browser evicted this context while the texture sat idle in the
      // pool; reusing it would render nothing forever. Purge it and fall
      // through to a fresh texture.
      pooled._release();
      _debugLogTexture('${pooled.rendererId} purged from pool (context lost)');
    }
    final id = '_rr_${_canvasCounter++}';
    final canvasElement = html.HTMLCanvasElement()
      ..id = id
      ..style.height = '100%'
      ..style.width = '100%';
    html.document.body!.append(canvasElement);

    final renderer = RiveWasm.makeRenderer.callAsFunction(null, canvasElement);
    assert(renderer != null && renderer.isA<js.JSObject>());

    final texture = _WebRenderTexture(
      renderer as js.JSObject,
      canvasElement,
      id,
    );
    // Create the observer
    final web.ResizeObserver observer = web.ResizeObserver(
      (
        js.JSArray<web.ResizeObserverEntry> entries,
        web.ResizeObserver observer,
      ) {
        if (canvasElement.isConnected) {
          texture.textureChanged();
        }
      }.toJS,
    );

    // Connect the observer.
    observer.observe(canvasElement);
    texture._resizeObserver = observer;

    _debugLogTexture('$id created');
    return texture;
  }

  _WebRenderTexture(this.jsRenderContext, this.canvasElement, this.rendererId) {
    jsRenderContextPtr = jsRenderContext?.getProperty('_ptr'.toJS);
    final gl = jsRenderContext?.getProperty('_gl'.toJS);
    _gl = gl != null && gl.isA<js.JSObject>() ? gl as js.JSObject : null;
    ui_web.platformViewRegistry.registerViewFactory(rendererId, (int viewId) {
      return canvasElement;
    });
  }

  // Last backing policy pushed to the JS renderer (fixedWidth, fixedHeight,
  // scaleX, scaleY, maxLogical), so repeated syncs only cross into JS when
  // something changed.
  (int, int, double, double, double)? _backingPolicy;

  /// Writes the backing policy that the wasm glue's `clearRenderer` sizes the
  /// canvas backing store from each frame (see
  /// `native/platform/wasm/init.js`). Returns whether the policy changed.
  bool setBackingPolicy({
    required int fixedWidth,
    required int fixedHeight,
    required double scaleX,
    required double scaleY,
    required double maxLogical,
  }) {
    final ctx = jsRenderContext;
    if (ctx == null) {
      // No renderer to apply to — leave the change unconsumed (and unkicked)
      // so a later sync, e.g. after a context is recreated, pushes it.
      return false;
    }
    final policy = (fixedWidth, fixedHeight, scaleX, scaleY, maxLogical);
    if (policy == _backingPolicy) {
      return false;
    }
    _backingPolicy = policy;
    ctx.setProperty('_fixedWidth'.toJS, fixedWidth.toJS);
    ctx.setProperty('_fixedHeight'.toJS, fixedHeight.toJS);
    ctx.setProperty('_backingScaleX'.toJS, scaleX.toJS);
    ctx.setProperty('_backingScaleY'.toJS, scaleY.toJS);
    ctx.setProperty('_maxBackingLogical'.toJS, maxLogical.toJS);
    return true;
  }

  /// Restores the default backing policy (layout × DPR, uncapped) so a pooled
  /// renderer cannot leak one consumer's policy to the next.
  void resetBackingPolicy() => setBackingPolicy(
        fixedWidth: 0,
        fixedHeight: 0,
        scaleX: 1,
        scaleY: 1,
        maxLogical: 0,
      );

  @override
  void dispose() {
    final alreadyDisposed = isDisposed || _pool.contains(this);
    assert(!alreadyDisposed, 'RenderTexture disposed twice');
    if (alreadyDisposed) {
      return;
    }
    canvasElement.width = canvasElement.height = 0;
    resetBackingPolicy();
    // A lost context never recovers on its own — pooling it would hand a
    // dead texture to the next consumer.
    final contextLost = _contextLost;
    if (_pool.length < _maxPoolSize && !contextLost) {
      _pool.add(this);
      _debugLogTexture('$rendererId disposed → pooled');
      return;
    }
    _release();
    _debugLogTexture('$rendererId disposed → released '
        '(${contextLost ? 'context lost' : 'pool full'})');
  }

  /// Genuinely destroys this texture: the native renderer, the browser's
  /// WebGL context, the resize observer, and the canvas element. The
  /// platform-view registration for [rendererId] keeps a closure over the
  /// canvas — registrations cannot be unregistered — but the id is never
  /// reused for another canvas.
  void _release() {
    _resizeObserver?.disconnect();
    _resizeObserver = null;
    final ctx = jsRenderContext;
    if (ctx != null) {
      RiveWasm.releaseRenderer.callAsFunction(null, ctx);
    }
    jsRenderContext = null;
    jsRenderContextPtr = null;
    _gl = null;
    canvasElement.remove();
  }

  /// Destroys all pooled textures. With [RiveWasm.releaseOffscreenGL] this
  /// lets an idle page drop to zero live WebGL contexts.
  static void releasePool() {
    for (final texture in _pool) {
      texture._release();
    }
    _pool.clear();
  }

  @override
  Widget widget({
    RenderTexturePainter? painter,
    RenderResolution resolution = RenderResolution.defaultValue,
    flutter.Key? key,
  }) =>
      Stack(
        children: [
          Positioned.fill(child: HtmlElementView(viewType: rendererId)),
          Positioned.fill(
              child: _RiveNativeWebView(this, painter, resolution, key: key)),
        ],
      );

  @override
  bool clear(Color color, [bool write = true]) {
    if (isDisposed) {
      return false;
    }
    RiveWasm.clearRenderer
        // ignore: deprecated_member_use
        .callAsFunction(null, jsRenderContext, color.value.toJS);
    return true;
  }

  @override
  bool flush(double devicePixelRatio) {
    if (isDisposed) {
      return false;
    }
    RiveWasm.flushRenderer.callAsFunction(null, jsRenderContextPtr);
    return true;
  }

  @override
  dynamic get nativeTexture => null;

  @override
  Renderer get renderer => WebRiveRenderer(jsRenderContextPtr, Factory.rive);

  @override
  Future<ui.Image> toImage() {
    final completer = Completer<ui.Image>();
    void blobResult(html.Blob blob) {
      blob.arrayBuffer().toDart.then((js.JSArrayBuffer buffer) {
        ui.decodeImageFromList(buffer.toDart.asUint8List(), (image) {
          completer.complete(image);
        });
      });
    }

    canvasElement.toBlob(blobResult.toJS, 'image/png');
    return completer.future;
  }

  // Pooled textures are not "disposed" — the same object is handed back out
  // by make(). Only a genuine release is terminal.
  @override
  bool get isDisposed => jsRenderContext == null;

  @override
  int get actualWidth => canvasElement.width;
  @override
  int get actualHeight => canvasElement.height;

  @override
  Future<void> makeRenderTexture(int width, int height) {
    throw UnimplementedError();
  }

  @override
  bool needsResize(int width, int height) => false;
}

/// Forces the loss of the WebGL context backing [texture] via the
/// `WEBGL_lose_context` extension — simulates the browser evicting the
/// context under context pressure.
@visibleForTesting
void debugLoseWebGLContext(RenderTexture? texture) {
  if (texture is! _WebRenderTexture) return;
  final ext = texture._gl?.callMethod<js.JSAny?>(
    'getExtension'.toJS,
    'WEBGL_lose_context'.toJS,
  );
  if (ext != null && ext.isA<js.JSObject>()) {
    (ext as js.JSObject).callMethod<js.JSAny?>('loseContext'.toJS);
  }
}

/// The bound on the web render-texture reuse pool, for lifecycle tests.
@visibleForTesting
int get debugWebRenderTexturePoolCap => _WebRenderTexture._maxPoolSize;

/// Logs a render-texture lifecycle event with live-context bookkeeping when
/// [RiveNative.debugRenderTextureLogging] is on.
void _debugLogTexture(String message) {
  if (!RiveNative.debugRenderTextureLogging) {
    return;
  }
  var live = -1;
  final fn = RiveWasm.module?.getProperty('liveGLContextCount'.toJS);
  if (fn != null && fn.isA<js.JSFunction>()) {
    live =
        ((fn as js.JSFunction).callAsFunction(null) as js.JSNumber).toDartInt;
  }
  debugPrint('[Rive] $message — live contexts: $live '
      '(pooled: ${_WebRenderTexture._pool.length})');
}

/// Extracts the WebGL context handle from a web [RenderTexture].
/// Returns 0 if the texture is null or not a web render texture.
int webGLHandleFromRenderTexture(RenderTexture? texture) {
  if (texture is! _WebRenderTexture) return 0;
  final renderer = texture.jsRenderContext;
  if (renderer == null) return 0;
  final handle = renderer.getProperty('_handle'.toJS);
  if (handle == null || !handle.isA<js.JSNumber>()) return 0;
  return (handle as js.JSNumber).toDartInt;
}

/// Extracts the ore::Context* pointer from a web [RenderTexture].
/// Returns 0 if the texture is null or not a web render texture.
int webOreCtxPtrFromRenderTexture(RenderTexture? texture) {
  if (texture is! _WebRenderTexture) return 0;
  final renderer = texture.jsRenderContext;
  if (renderer == null) return 0;
  final ptr = renderer.getProperty('_oreCtxPtr'.toJS);
  if (ptr == null || !ptr.isA<js.JSNumber>()) return 0;
  return (ptr as js.JSNumber).toDartInt;
}

/// Extracts the gpu::RenderContext* pointer from a web [RenderTexture].
/// Returns 0 if the texture is null or not a web render texture.
int webRenderCtxPtrFromRenderTexture(RenderTexture? texture) {
  if (texture is! _WebRenderTexture) return 0;
  final renderer = texture.jsRenderContext;
  if (renderer == null) return 0;
  final ptr = renderer.getProperty('_renderCtxPtr'.toJS);
  if (ptr == null || !ptr.isA<js.JSNumber>()) return 0;
  return (ptr as js.JSNumber).toDartInt;
}

class WasmBuffer {
  js.JSAny _pointer;
  late Uint8List _data;
  final int size;

  Uint8List get data {
    // As WebAssembly memory grows it might invalidate the JavaScript
    // TypedArray views.
    // In the event these views are detached, we need to recreate them.
    // This can happen when loading large .riv files or when the WASM memory
    // is expanded.
    // Only recreate the data if it is empty and the pointer is not 0 (disposed).
    // See: https://github.com/emscripten-core/emscripten/issues/7294
    if (_data.isEmpty && _pointer != 0.toJS) {
      _data = RiveWasm.heap((_pointer as js.JSNumber).toDartInt, size);
      return _data;
    }
    return _data;
  }

  js.JSAny get pointer => _pointer;

  WasmBuffer(this.size)
      : _pointer = RiveWasm.allocateBuffer.callAsFunction(null, size.toJS)
            as js.JSAny {
    _data = RiveWasm.heap((_pointer as js.JSNumber).toDartInt, size);
  }

  factory WasmBuffer.fromBytes(Uint8List bytes) {
    var buffer = WasmBuffer(bytes.length);
    buffer.data.setRange(0, bytes.length, bytes);
    return buffer;
  }

  void dispose() {
    RiveWasm.deleteBuffer.callAsFunction(null, _pointer);
    _pointer = 0.toJS;
    _data = Uint8List(0);
  }
}

class RiveWasm {
  /// The linked emscripten module. Exposed so tests can reach raw `_name`
  /// exports (e.g. debug-build object counters) the way FFI tests reach
  /// `DynamicLibraryHelper.nativeLib`.
  @internal
  static js.JSObject? module;

  static late js.JSFunction makeRenderer;
  static late js.JSFunction releaseRenderer;
  static late js.JSFunction releaseOffscreenGL;
  static late js.JSFunction deleteFlutterRenderer;
  static late js.JSFunction flushRenderer;
  static late js.JSFunction clearRenderer;
  static late js.JSFunction saveRenderer;
  static late js.JSFunction restoreRenderer;
  static late js.JSFunction transformRenderer;
  static late js.JSFunction modulateOpacityRenderer;
  static late js.JSFunction makeEmptyRenderPath;
  static late js.JSFunction deleteRenderPath;
  static late js.JSFunction renderPathHitTest;
  static late js.JSFunction addPath;
  static late js.JSFunction addPathBackwards;
  static late js.JSFunction trimPathEffectPath;
  static late js.JSFunction makeTrimPathEffect;
  static late js.JSFunction deleteTrimPathEffect;
  static late js.JSFunction trimPathEffectInvalidate;
  static late js.JSFunction trimPathEffectGetEnd;
  static late js.JSFunction trimPathEffectSetEnd;
  static late js.JSFunction trimPathEffectGetMode;
  static late js.JSFunction trimPathEffectSetMode;
  static late js.JSFunction trimPathEffectGetOffset;
  static late js.JSFunction trimPathEffectSetOffset;
  static late js.JSFunction trimPathEffectGetStart;
  static late js.JSFunction trimPathEffectSetStart;
  static late js.JSFunction makePathMeasure;
  static late js.JSFunction deletePathMeasure;
  static late js.JSFunction pathMeasureAtPercentage;
  static late js.JSFunction pathMeasureAtDistance;
  static late js.JSFunction pathMeasureLength;
  static late js.JSFunction deleteRenderImage;
  static late js.JSFunction renderImageWidth;
  static late js.JSFunction renderImageHeight;
  static late js.JSFunction makeVertexRenderBuffer;
  static late js.JSFunction makeIndexRenderBuffer;
  static late js.JSFunction deleteRenderBuffer;
  static late js.JSFunction mapRenderBuffer;
  static late js.JSFunction unmapRenderBuffer;
  static late js.JSFunction setArtboardLayoutChangedCallback;
  static late js.JSFunction setArtboardTestBoundsCallback;
  static late js.JSFunction setArtboardIsAncestorCallback;
  static late js.JSFunction setArtboardRootTransformCallback;
  static late js.JSFunction setArtboardLayoutDirtyCallback;
  static late js.JSFunction setArtboardTransformDirtyCallback;
  static late js.JSFunction setStateMachineInputChangedCallback;
  static late js.JSFunction setArtboardEventCallback;
  static late js.JSFunction addRawPath;
  static late js.JSFunction addRawPathWithTransform;
  static late js.JSFunction addRawPathWithTransformClockwise;

  static late js.JSFunction deleteDashPathEffect;
  static late js.JSFunction makeDashPathEffect;
  static late js.JSFunction dashPathEffectGetPathLength;
  static late js.JSFunction dashPathEffectGetOffset;
  static late js.JSFunction dashPathEffectSetOffset;
  static late js.JSFunction dashPathEffectGetOffsetIsPercentage;
  static late js.JSFunction dashPathEffectSetOffsetIsPercentage;
  static late js.JSFunction dashPathClearDashes;
  static late js.JSFunction dashPathAddDash;
  static late js.JSFunction dashPathInvalidate;
  static late js.JSFunction dashPathEffectPath;

  static late js.JSFunction renderPathColinearCheck;
  static late js.JSFunction renderPathPreciseBounds;
  static late js.JSFunction renderPathPreciseLength;
  static late js.JSFunction renderPathBounds;
  static late js.JSFunction renderPathIsClosed;
  static late js.JSFunction renderPathHasBounds;
  static late js.JSFunction renderPathIsClockwise;

  static late js.JSFunction renderPathCopyBuffers;

  static const scratchBufferSize = 1024;

  // Float32 specific view of scratchBuffer to mitigate making a view on
  // scratchBuffer which doesn't work with SharedArrayBuffer.
  static Float32List get scratchBufferFloat {
    return (_heapViewF32.callAsFunction(
      null,
      scratchBufferPtr,
      (scratchBufferSize ~/ 4).toJS,
    ) as js.JSFloat32Array)
        .toDart;
  }

  static Uint8List get scratchBuffer {
    return (_heapViewU8.callAsFunction(
      null,
      scratchBufferPtr,
      scratchBufferSize.toJS,
    ) as js.JSUint8Array)
        .toDart;
  }

  static ByteData get scratchBufferByteData {
    return (_heapDataView.callAsFunction(
      null,
      scratchBufferPtr,
      scratchBufferSize.toJS,
    ) as js.JSDataView)
        .toDart;
  }

  static ByteData heapDataView(int pointer, [int? size]) {
    if (size == null) {
      return (_heapDataView.callAsFunction(null, pointer.toJS) as js.JSDataView)
          .toDart;
    }
    return (_heapDataView.callAsFunction(null, pointer.toJS, size.toJS)
            as js.JSDataView)
        .toDart;
  }

  static Float32List heapViewF32(int pointer, int size) {
    return (_heapViewF32.callAsFunction(null, pointer.toJS, size.toJS)
            as js.JSFloat32Array)
        .toDart;
  }

  static Uint16List heapViewU16(int pointer, int size) {
    return (_heapViewU16.callAsFunction(null, pointer.toJS, size.toJS)
            as js.JSUint16Array)
        .toDart;
  }

  static Uint32List heapViewU32(int pointer, int size) {
    return (_heapViewU32.callAsFunction(null, pointer.toJS, size.toJS)
            as js.JSUint32Array)
        .toDart;
  }

  static late js.JSNumber scratchBufferPtr;
  static late js.JSFunction appendCommands;
  static late js.JSFunction makeRenderPath;
  static late js.JSFunction renderPathSetFillRule;
  static late js.JSFunction appendRenderPath;
  static late js.JSFunction rewindRenderPath;
  static late js.JSFunction makeRenderPaint;
  static late js.JSFunction deleteRenderPaint;
  static late js.JSFunction updatePaint;
  static late js.JSFunction drawPath;
  static late js.JSFunction drawImage;
  static late js.JSFunction drawImageMesh;
  static late js.JSFunction clipPath;
  static late js.JSFunction _heapViewU8;
  static late js.JSFunction _heapViewF32;
  static late js.JSFunction _heapViewU16;
  static late js.JSFunction _heapViewU32;
  static late js.JSFunction _heapDataView;
  static late js.JSFunction stringViewU8;
  static late js.JSFunction decodeImage;
  static late js.JSFunction renderImageSetSize;

  static late js.JSFunction makeFlutterFactory;
  static late js.JSFunction deleteFlutterFactory;
  static late js.JSFunction initFactoryCallbacks;
  static late js.JSFunction makeFlutterRenderer;
  static late js.JSFunction allocateBuffer;
  static late js.JSFunction deleteBuffer;
  static late js.JSFunction loadRiveFile;
  static late js.JSFunction riveFileAssetName;
  static late js.JSFunction riveFileAssetFileExtension;
  static late js.JSFunction riveFileAssetCdnBaseUrl;
  static late js.JSFunction riveFileAssetCdnUuid;
  static late js.JSFunction riveFileAssetId;
  static late js.JSFunction riveFileAssetCoreType;
  static late js.JSFunction riveFileAssetSetRenderImage;
  static late js.JSFunction imageAssetGetWidth;
  static late js.JSFunction imageAssetGetHeight;
  static late js.JSFunction riveFileAssetSetFont;
  static late js.JSFunction riveFileAssetSetAudioSource;
  static late js.JSFunction deleteRiveFile;
  static js.JSFunction? riveFileSetScriptingVM;
  static late js.JSFunction deleteFileAsset;
  static js.JSFunction? requestSerializedViewModelInstance;
  static late js.JSFunction clearRuntimeViewModelInstances;
  static late js.JSFunction riveFileArtboardDefault;
  static late js.JSFunction riveFileArtboardNamed;
  static late js.JSFunction riveFileArtboardByIndex;
  static late js.JSFunction riveFileArtboardToBindNamed;
  static late js.JSFunction riveFileViewModelCount;
  static late js.JSFunction riveFileViewModelRuntimeByIndex;
  static late js.JSFunction riveFileViewModelRuntimeByName;
  static late js.JSFunction riveFileDefaultArtboardViewModelRuntime;
  static late js.JSFunction viewModelRuntimePropertyCount;
  static late js.JSFunction viewModelRuntimeInstanceCount;
  static late js.JSFunction viewModelRuntimeName;
  static late js.JSFunction viewModelRuntimeProperties;
  static late js.JSFunction fileEnums;
  static late js.JSFunction createVMIRuntimeFromIndex;
  static late js.JSFunction createVMIRuntimeFromName;
  static late js.JSFunction createDefaultVMIRuntime;
  static late js.JSFunction createVMIRuntime;
  static late js.JSFunction vmiRuntimeName;
  static late js.JSFunction vmiRuntimeProperties;
  static late js.JSFunction vmiRuntimeGetViewModelProperty;
  static late js.JSFunction vmiRuntimeGetNumberProperty;
  static late js.JSFunction getVMINumberRuntimeValue;
  static late js.JSFunction setVMINumberRuntimeValue;
  static late js.JSFunction vmiRuntimeGetStringProperty;
  static late js.JSFunction getVMIStringRuntimeValue;
  static late js.JSFunction setVMIStringRuntimeValue;
  static late js.JSFunction vmiRuntimeGetBooleanProperty;
  static late js.JSFunction getVMIBooleanRuntimeValue;
  static late js.JSFunction setVMIBooleanRuntimeValue;
  static late js.JSFunction vmiRuntimeGetColorProperty;
  static late js.JSFunction getVMIColorRuntimeValue;
  static late js.JSFunction setVMIColorRuntimeValue;
  static late js.JSFunction vmiRuntimeGetEnumProperty;
  static late js.JSFunction getVMIEnumRuntimeValue;
  static late js.JSFunction setVMIEnumRuntimeValue;
  static late js.JSFunction getVMIEnumRuntimeEnumType;
  static late js.JSFunction vmiRuntimeGetTriggerProperty;
  static late js.JSFunction triggerVMITriggerRuntime;
  static late js.JSFunction vmiRuntimeGetAssetImageProperty;
  static late js.JSFunction setVMIAssetImageRuntimeValue;
  static late js.JSFunction vmiRuntimeGetAssetFontProperty;
  static late js.JSFunction setVMIAssetFontRuntimeValue;
  static late js.JSFunction vmiRuntimeGetListProperty;
  static late js.JSFunction getVMIListRuntimeSize;
  static late js.JSFunction vmiListRuntimeAddInstance;
  static late js.JSFunction vmiListRuntimeAddInstanceAt;
  static late js.JSFunction vmiListRuntimeRemoveInstance;
  static late js.JSFunction vmiListRuntimeRemoveInstanceAt;
  static late js.JSFunction vmiListRuntimeInstanceAt;
  static late js.JSFunction vmiListRuntimeSwap;
  static late js.JSFunction vmiRuntimeGetArtboardProperty;
  static late js.JSFunction setVMIArtboardRuntimeValue;
  static late js.JSFunction vmiValueRuntimeHasChanged;
  static late js.JSFunction vmiValueRuntimeClearChanges;
  static late js.JSFunction artboardSetVMIRuntime;
  static late js.JSFunction stateMachineSetVMIRuntime;
  static late js.JSFunction deleteVMIValueRuntime;
  static late js.JSFunction deleteVMIRuntime;
  static late js.JSFunction deleteViewModelRuntime;
  static late js.JSFunction artboardDraw;
  static late js.JSFunction artboardDrawCanvases;
  static late js.JSFunction artboardGetDrawCanvasLuauState;
  static late js.JSFunction artboardDrawInternal;
  static late js.JSFunction artboardReset;
  static late js.JSFunction artboardName;
  static late js.JSFunction artboardGetInnerPointer;
  static late js.JSFunction deleteArtboardInstance;
  static late js.JSFunction deleteBindableArtboard;
  static late js.JSFunction artboardAnimationCount;
  static late js.JSFunction artboardStateMachineCount;
  static late js.JSFunction artboardAnimationAt;
  static late js.JSFunction artboardComponentNamed;
  static late js.JSFunction componentGetLocalBounds;
  static late js.JSFunction componentGetWorldTransform;
  static late js.JSFunction componentSetWorldTransform;
  static late js.JSFunction artboardGetRenderTransform;
  static late js.JSFunction artboardSetRenderTransform;
  static late js.JSFunction componentGetScaleX;
  static late js.JSFunction componentSetScaleX;
  static late js.JSFunction componentGetX;
  static late js.JSFunction componentSetX;
  static late js.JSFunction componentGetScaleY;
  static late js.JSFunction componentSetScaleY;
  static late js.JSFunction componentGetY;
  static late js.JSFunction componentSetY;
  static late js.JSFunction componentGetRotation;
  static late js.JSFunction componentSetRotation;
  static late js.JSFunction componentSetLocalFromWorld;
  static late js.JSFunction artboardAnimationNamed;
  static late js.JSFunction artboardSetFrameOrigin;
  static late js.JSFunction artboardGetFrameOrigin;
  static late js.JSFunction animationInstanceName;
  static late js.JSFunction animationInstanceAdvance;
  static late js.JSFunction animationInstanceApply;
  static late js.JSFunction animationInstanceAdvanceAndApply;
  static late js.JSFunction animationInstanceGetTime;
  static late js.JSFunction animationInstanceGetDuration;
  static late js.JSFunction animationInstanceGetLocalSeconds;
  static late js.JSFunction animationInstanceSetTime;
  static late js.JSFunction animationInstanceDelete;
  static late js.JSFunction artboardAddToRenderPath;
  static late js.JSFunction artboardBounds;
  static late js.JSFunction artboardWorldBounds;
  static late js.JSFunction artboardLayoutBounds;
  static late js.JSFunction riveArtboardAdvance;
  static late js.JSFunction riveArtboardGetOpacity;
  static late js.JSFunction riveArtboardSetOpacity;
  static late js.JSFunction riveArtboardSetHostOpacity;
  static late js.JSFunction riveArtboardGetWidth;
  static late js.JSFunction riveArtboardSetWidth;
  static late js.JSFunction riveArtboardGetHeight;
  static late js.JSFunction riveArtboardSetHeight;
  static late js.JSFunction riveArtboardGetOriginX;
  static late js.JSFunction riveArtboardSetOriginX;
  static late js.JSFunction riveArtboardGetOriginY;
  static late js.JSFunction riveArtboardSetOriginY;
  static late js.JSFunction riveArtboardGetOriginalWidth;
  static late js.JSFunction riveArtboardGetOriginalHeight;
  static late js.JSFunction riveArtboardStateMachineDefault;
  static late js.JSFunction riveArtboardStateMachineNamed;
  static late js.JSFunction riveArtboardStateMachineAt;
  static late js.JSFunction riveArtboardHasComponentDirt;
  static late js.JSFunction riveArtboardUpdatePass;
  static late js.JSFunction deleteStateMachineInstance;
  static late js.JSFunction stateMachineInstanceName;
  static late js.JSFunction stateMachineInstanceAdvance;
  static late js.JSFunction stateMachineInstanceAdvanceAndApply;
  static late js.JSFunction stateMachineInstanceStateChangedCount;
  static late js.JSFunction stateMachineInstanceStateChangedNameByIndex;
  static late js.JSFunction deleteInput;
  static late js.JSFunction deleteComponent;
  static late js.JSFunction stateMachineInput;
  static late js.JSFunction stateMachineInputName;
  static late js.JSFunction stateMachineInputType;
  static late js.JSFunction stateMachineInstanceNumber;
  static late js.JSFunction stateMachineInstanceDone;
  static late js.JSFunction stateMachineInstanceHitTest;
  static late js.JSFunction stateMachineInstancePointerDown;
  static late js.JSFunction stateMachineInstancePointerUp;
  static late js.JSFunction stateMachineInstancePointerMove;
  static late js.JSFunction stateMachineInstancePointerExit;
  static late js.JSFunction stateMachineInstanceDragStart;
  static late js.JSFunction stateMachineInstanceDragEnd;
  static late js.JSFunction stateMachineInstanceSubmitGamepadsFromBuffer;
  static late js.JSFunction makeGamepadInvocation;
  static late js.JSFunction deleteGamepadInvocation;
  static late js.JSFunction stateMachineInstanceDispatchGamepadInvocation;
  static late js.JSFunction stateMachineGetReportedEventCount;
  static late js.JSFunction stateMachineReportedEventAt;
  static late js.JSFunction deleteEvent;
  static late js.JSFunction deleteCustomProperty;
  static late js.JSFunction getEventName;
  static late js.JSFunction getOpenUrlEventUrl;
  static late js.JSFunction getOpenUrlEventTarget;
  static late js.JSFunction getAudioEventAssetId;
  static late js.JSFunction getAudioEventAssetName;
  static late js.JSFunction getAudioEventVolume;
  static late js.JSFunction getEventCustomPropertyCount;
  static late js.JSFunction getEventCustomProperty;
  static late js.JSFunction getCustomPropertyNumber;
  static late js.JSFunction getCustomPropertyBoolean;
  static late js.JSFunction getCustomPropertyString;
  static late js.JSFunction getNumberValue;
  static late js.JSFunction setNumberValue;
  static late js.JSFunction stateMachineInstanceBoolean;
  static late js.JSFunction getBooleanValue;
  static late js.JSFunction setBooleanValue;
  static late js.JSFunction stateMachineInstanceTrigger;
  static late js.JSFunction fireTrigger;
  static late js.JSFunction stateMachineInstanceBatchAdvance;
  static late js.JSFunction stateMachineInstanceBatchAdvanceAndRender;
  static late js.JSFunction artboardSetText;
  static late js.JSFunction artboardGetText;
  static late js.JSFunction artboardGetAllTextRuns;
  static late js.JSFunction freeTextRunsArray;
  static late js.JSFunction getTextRunFromArray;
  static late js.JSFunction deleteTextValueRun;
  static late js.JSFunction textValueRunName;
  static late js.JSFunction textValueRunText;
  static late js.JSFunction textValueRunPath;
  static late js.JSFunction textValueRunSetText;
  static late js.JSFunction artboardTakeLayoutNode;
  static late js.JSFunction artboardAddedToHost;
  static late js.JSFunction artboardSyncStyleChanges;
  static late js.JSFunction artboardWidthOverride;
  static late js.JSFunction artboardHeightOverride;
  static late js.JSFunction artboardParentIsRow;
  static late js.JSFunction artboardWidthIntrinsicallySizeOverride;
  static late js.JSFunction artboardHeightIntrinsicallySizeOverride;
  static late js.JSFunction updateLayoutBounds;
  static late js.JSFunction cascadeLayoutStyle;
  static late js.JSFunction cascadeLayoutStyleBatch;
  static late js.JSFunction? cascadeCollapseBatch;
  static late js.JSFunction? cascadeCollapse;

  static late js.JSFunction makeFlutterRenderImage;
  static late js.JSFunction flutterRenderImageId;
  static late js.JSFunction riveDataContext;
  static late js.JSFunction riveDataContextFromInstances;
  static late js.JSFunction dataContextViewModelInstanceAt;
  static late js.JSFunction dataContextFromViewModelInstancePointers;
  static late js.JSFunction deleteDataContext;
  static late js.JSFunction deleteViewModelInstance;
  static late js.JSFunction deleteViewModelInstanceValue;
  static late js.JSFunction riveDataContextViewModelInstance;
  static late js.JSFunction viewModelInstancePropertyValue;
  static late js.JSFunction pruneViewModelInstanceToProperties;
  static late js.JSFunction viewModelInstanceListItemViewModel;
  static late js.JSFunction viewModelInstanceListSize;
  static late js.JSFunction viewModelInstanceReferenceViewModel;
  static late js.JSFunction setViewModelInstanceNumberValue;
  static late js.JSFunction setViewModelInstanceColorValue;
  static late js.JSFunction setViewModelInstanceStringValue;
  static late js.JSFunction setViewModelInstanceBooleanValue;
  static late js.JSFunction setViewModelInstanceTriggerValue;
  static late js.JSFunction setViewModelInstanceAssetValue;
  static late js.JSFunction viewModelInstanceAssetImageResolveRuntimeIndex;
  static late js.JSFunction viewModelInstanceAssetFontResolveRuntimeIndex;
  static late js.JSFunction setViewModelInstanceArtboardValue;
  static late js.JSFunction setViewModelInstanceAdvanced;
  static late js.JSFunction setViewModelInstanceEnumValue;
  static late js.JSFunction setViewModelInstanceSymbolListIndexValue;
  static late js.JSFunction setViewModelInstanceListValue;
  static late js.JSFunction copyViewModelInstance;
  static late js.JSFunction riveDataBindDirt;
  static late js.JSFunction riveDataBindSetDirt;
  static late js.JSFunction riveDataBindFlags;
  static late js.JSFunction riveDataBindUpdate;
  static late js.JSFunction riveDataBindUpdateSourceBinding;
  static late js.JSFunction artboardClearDataContext;
  static late js.JSFunction artboardUnbind;
  static late js.JSFunction artboardUpdateDataBinds;
  static late js.JSFunction artboardDataContextFromInstance;
  static late js.JSFunction artboardInternalDataContext;
  static late js.JSFunction artboardDataContext;
  static late js.JSFunction stateMachineDataContextFromInstance;
  static late js.JSFunction stateMachineDataContext;
  static late js.JSFunction setStateMachineDataBindChangedCallback;
  static late js.JSFunction setViewModelInstanceNumberCallback;
  static late js.JSFunction setViewModelInstanceBooleanCallback;
  static late js.JSFunction setViewModelInstanceColorCallback;
  static late js.JSFunction setViewModelInstanceStringCallback;
  static late js.JSFunction setViewModelInstanceTriggerCallback;
  static late js.JSFunction setViewModelInstanceEnumCallback;
  static late js.JSFunction setViewModelInstanceSymbolListIndexCallback;
  static late js.JSFunction setViewModelInstanceAssetCallback;
  static late js.JSFunction setViewModelInstanceArtboardCallback;
  static late js.JSFunction setViewModelInstanceListCallback;
  static late js.JSFunction setViewModelInstanceViewModelValue;
  static late js.JSFunction setViewModelInstanceViewModelCallback;
  static late js.JSFunction initBindingCallbacks;

  // Focus-related artboard/state machine functions
  // These require WITH_RIVE_TOOLS (editor builds only)
  static js.JSFunction? artboardRootFocusDataCount;
  static js.JSFunction? artboardRootFocusNodeAt;
  static js.JSFunction? artboardSetExternalParentFocusNode;
  static late js.JSFunction artboardBuildFocusTreeWithParent;
  static late js.JSFunction stateMachineGetFocusManager;
  static late js.JSFunction stateMachineSetExternalFocusManager;

  static late js.JSFunction makeRawText;
  static late js.JSFunction deleteRawText;
  static late js.JSFunction rawTextAppend;
  static late js.JSFunction rawTextClear;
  static late js.JSFunction rawTextIsEmpty;
  static late js.JSFunction rawTextGetSizing;
  static late js.JSFunction rawTextSetSizing;
  static late js.JSFunction rawTextGetOverflow;
  static late js.JSFunction rawTextSetOverflow;
  static late js.JSFunction rawTextGetAlign;
  static late js.JSFunction rawTextSetAlign;
  static late js.JSFunction rawTextGetMaxWidth;
  static late js.JSFunction rawTextSetMaxWidth;
  static late js.JSFunction rawTextGetMaxHeight;
  static late js.JSFunction rawTextSetMaxHeight;
  static late js.JSFunction rawTextGetParagraphSpacing;
  static late js.JSFunction rawTextSetParagraphSpacing;
  static late js.JSFunction rawTextBounds;
  static late js.JSFunction rawTextRender;

  static late js.JSFunction makeRawTextInput;
  static late js.JSFunction deleteRawTextInput;
  static late js.JSFunction rawTextInputGetFontSize;
  static late js.JSFunction rawTextInputSetFontSize;
  static late js.JSFunction rawTextInputSetFont;
  static late js.JSFunction rawTextInputGetMaxWidth;
  static late js.JSFunction rawTextInputSetMaxWidth;
  static late js.JSFunction rawTextInputGetMaxHeight;
  static late js.JSFunction rawTextInputSetMaxHeight;
  static late js.JSFunction rawTextInputGetParagraphSpacing;
  static late js.JSFunction rawTextInputSetParagraphSpacing;
  static late js.JSFunction rawTextInputGetSizing;
  static late js.JSFunction rawTextInputSetSizing;
  static late js.JSFunction rawTextInputGetOverflow;
  static late js.JSFunction rawTextInputSetOverflow;
  static late js.JSFunction rawTextInputGetSelectionCornerRadius;
  static late js.JSFunction rawTextInputSetSelectionCornerRadius;
  static late js.JSFunction rawTextInputGetSeparateSelectionText;
  static late js.JSFunction rawTextInputSetSeparateSelectionText;
  static late js.JSFunction rawTextInputGetText;
  static late js.JSFunction rawTextInputSetText;
  static late js.JSFunction rawTextInputSetTextPreserveCursor;
  static late js.JSFunction rawTextInputLength;
  static late js.JSFunction rawTextInputBounds;
  static late js.JSFunction rawTextInputUpdate;
  static late js.JSFunction rawTextTextPath;
  static late js.JSFunction rawTextSelectedTextPath;
  static late js.JSFunction rawTextCursorPath;
  static late js.JSFunction rawTextSelectionPath;
  static late js.JSFunction rawTextClipPath;
  static late js.JSFunction rawTextInputCursorPosition;
  static late js.JSFunction rawTextInsertText;
  static late js.JSFunction rawTextInsertCodePoint;
  static late js.JSFunction rawTextErase;
  static late js.JSFunction rawTextBackspace;
  static late js.JSFunction rawTextCursorLeft;
  static late js.JSFunction rawTextCursorRight;
  static late js.JSFunction rawTextCursorUp;
  static late js.JSFunction rawTextCursorDown;
  static late js.JSFunction rawTextMoveCursorTo;
  static late js.JSFunction rawTextUndo;
  static late js.JSFunction rawTextRedo;
  static late js.JSFunction rawTextSelectWord;
  static late js.JSFunction rawTextHasSelection;
  static late js.JSFunction rawTextClearSelection;
  static late js.JSFunction rawTextInputMeasure;
  static late js.JSFunction freeString;
  static late js.JSFunction riveAdvanceFrameId;

  // Profiler bindings
  // Profiler functions require WITH_RIVE_TOOLS (editor builds only)
  static js.JSFunction? profilerStart;
  static js.JSFunction? profilerStop;
  static js.JSFunction? profilerIsActive;
  static js.JSFunction? profilerDump;
  static js.JSFunction? profilerGetBufferPtr;
  static js.JSFunction? profilerGetBufferSize;
  static js.JSFunction? profilerFreeBuffer;
  static js.JSFunction? profilerEndFrame;

  static ByteData heapView() => heapDataView(0);

  static Uint8List heap(int pointer, int size) =>
      (_heapViewU8.callAsFunction(null, pointer.toJS, size.toJS)
              as js.JSUint8Array)
          .toDart;

  static String toDartString(int pointer, {bool deleteNative = false}) {
    var codeUnits =
        (stringViewU8.callAsFunction(null, pointer.toJS) as js.JSUint8Array)
            .toDart;
    final result = utf8.decode(codeUnits);
    if (deleteNative) {
      freeString.callAsFunction(null, pointer.toJS);
    }
    return result;
  }

  static void link(js.JSObject module) {
    RiveWasm.module = module;
    makeRenderer = module['makeRenderer'] as js.JSFunction;
    releaseRenderer = module['releaseRenderer'] as js.JSFunction;
    releaseOffscreenGL = module['releaseOffscreenGL'] as js.JSFunction;
    flushRenderer = module['flushRenderer'] as js.JSFunction;
    clearRenderer = module['clearRenderer'] as js.JSFunction;
    saveRenderer = module['saveRenderer'] as js.JSFunction;
    restoreRenderer = module['restoreRenderer'] as js.JSFunction;
    transformRenderer = module['transformRenderer'] as js.JSFunction;
    modulateOpacityRenderer =
        module['modulateOpacityRenderer'] as js.JSFunction;

    makeEmptyRenderPath = module['_makeEmptyRenderPath'] as js.JSFunction;
    deleteRenderPath = module['_deleteRenderPath'] as js.JSFunction;
    renderPathHitTest = module['_renderPathHitTest'] as js.JSFunction;
    addPath = module['_addPath'] as js.JSFunction;
    addRawPath = module['_addRawPath'] as js.JSFunction;
    addRawPathWithTransform =
        module['_addRawPathWithTransform'] as js.JSFunction;
    addRawPathWithTransformClockwise =
        module['_addRawPathWithTransformClockwise'] as js.JSFunction;
    addPathBackwards = module['_addPathBackwards'] as js.JSFunction;
    appendCommands = module['_appendCommands'] as js.JSFunction;
    makeRenderPath = module['_makeRenderPath'] as js.JSFunction;
    renderPathSetFillRule = module['_renderPathSetFillRule'] as js.JSFunction;
    appendRenderPath = module['_appendRenderPath'] as js.JSFunction;
    rewindRenderPath = module['_rewindRenderPath'] as js.JSFunction;
    makeRenderPaint = module['_makeRenderPaint'] as js.JSFunction;
    deleteRenderPaint = module['_deleteRenderPaint'] as js.JSFunction;
    updatePaint = module['_updatePaint'] as js.JSFunction;
    drawPath = module['_drawPath'] as js.JSFunction;
    drawImage = module['_drawImage'] as js.JSFunction;
    drawImageMesh = module['_drawImageMesh'] as js.JSFunction;
    clipPath = module['_clipPath'] as js.JSFunction;
    trimPathEffectPath = module['_trimPathEffectPath'] as js.JSFunction;
    makeTrimPathEffect = module['_makeTrimPathEffect'] as js.JSFunction;
    deleteTrimPathEffect = module['_deleteTrimPathEffect'] as js.JSFunction;
    trimPathEffectInvalidate =
        module['_trimPathEffectInvalidate'] as js.JSFunction;
    trimPathEffectGetEnd = module['_trimPathEffectGetEnd'] as js.JSFunction;
    trimPathEffectSetEnd = module['_trimPathEffectSetEnd'] as js.JSFunction;
    trimPathEffectGetMode = module['_trimPathEffectGetMode'] as js.JSFunction;
    trimPathEffectSetMode = module['_trimPathEffectSetMode'] as js.JSFunction;
    trimPathEffectGetOffset =
        module['_trimPathEffectGetOffset'] as js.JSFunction;
    trimPathEffectSetOffset =
        module['_trimPathEffectSetOffset'] as js.JSFunction;
    trimPathEffectGetStart = module['_trimPathEffectGetStart'] as js.JSFunction;
    trimPathEffectSetStart = module['_trimPathEffectSetStart'] as js.JSFunction;

    makePathMeasure = module['_makePathMeasure'] as js.JSFunction;
    deletePathMeasure = module['_deletePathMeasure'] as js.JSFunction;
    pathMeasureAtPercentage =
        module['_pathMeasureAtPercentage'] as js.JSFunction;
    pathMeasureAtDistance = module['_pathMeasureAtDistance'] as js.JSFunction;
    pathMeasureLength = module['_pathMeasureLength'] as js.JSFunction;

    decodeImage = module['decodeImage'] as js.JSFunction;
    renderImageSetSize = module['_renderImageSetSize'] as js.JSFunction;
    deleteRenderImage = module['_deleteRenderImage'] as js.JSFunction;
    renderImageWidth = module['_renderImageWidth'] as js.JSFunction;
    renderImageHeight = module['_renderImageHeight'] as js.JSFunction;

    makeVertexRenderBuffer = module['_makeVertexRenderBuffer'] as js.JSFunction;
    makeIndexRenderBuffer = module['_makeIndexRenderBuffer'] as js.JSFunction;
    deleteRenderBuffer = module['_deleteRenderBuffer'] as js.JSFunction;
    mapRenderBuffer = module['_mapRenderBuffer'] as js.JSFunction;
    unmapRenderBuffer = module['_unmapRenderBuffer'] as js.JSFunction;

    // Allocate the scratch buffer.
    allocateBuffer = module["_allocateBuffer"] as js.JSFunction;
    deleteBuffer = module["_deleteBuffer"] as js.JSFunction;
    scratchBufferPtr = allocateBuffer.callAsFunction(
        null, scratchBufferSize.toJS) as js.JSNumber;
    _heapViewU8 = module["heapViewU8"] as js.JSFunction;
    _heapViewF32 = module["heapViewF32"] as js.JSFunction;
    _heapViewU16 = module["heapViewU16"] as js.JSFunction;
    _heapViewU32 = module["heapViewU32"] as js.JSFunction;
    stringViewU8 = module["stringViewU8"] as js.JSFunction;
    _heapDataView = module["heapDataView"] as js.JSFunction;

    makeFlutterFactory = module['_makeFlutterFactory'] as js.JSFunction;
    deleteFlutterFactory = module['_deleteFlutterFactory'] as js.JSFunction;
    initFactoryCallbacks = module['initFactoryCallbacks'] as js.JSFunction;
    makeFlutterRenderer = module['_makeFlutterRenderer'] as js.JSFunction;
    deleteFlutterRenderer = module['_deleteFlutterRenderer'] as js.JSFunction;

    loadRiveFile = module['loadRiveFile'] as js.JSFunction;
    deleteRiveFile = module['_deleteRiveFile'] as js.JSFunction;
    riveFileSetScriptingVM =
        module['_riveFileSetScriptingVM'] as js.JSFunction?;
    clearRuntimeViewModelInstances =
        module['_clearRuntimeViewModelInstances'] as js.JSFunction;
    requestSerializedViewModelInstance =
        module['_requestSerializedViewModelInstance'] as js.JSFunction?;
    deleteFileAsset = module['_deleteFileAsset'] as js.JSFunction;
    riveFileAssetName = module['_riveFileAssetName'] as js.JSFunction;
    riveFileAssetFileExtension =
        module['_riveFileAssetFileExtension'] as js.JSFunction;
    riveFileAssetCdnBaseUrl =
        module['_riveFileAssetCdnBaseUrl'] as js.JSFunction;
    riveFileAssetCdnUuid = module['_riveFileAssetCdnUuid'] as js.JSFunction;
    riveFileAssetId = module['_riveFileAssetId'] as js.JSFunction;
    riveFileAssetCoreType = module['_riveFileAssetCoreType'] as js.JSFunction;
    riveFileAssetSetFont = module['_riveFileAssetSetFont'] as js.JSFunction;
    riveFileAssetSetAudioSource =
        module['_riveFileAssetSetAudioSource'] as js.JSFunction;
    riveFileAssetSetRenderImage =
        module['_riveFileAssetSetRenderImage'] as js.JSFunction;
    imageAssetGetWidth = module['_imageAssetGetWidth'] as js.JSFunction;
    imageAssetGetHeight = module['_imageAssetGetHeight'] as js.JSFunction;
    riveFileArtboardDefault =
        module['_riveFileArtboardDefault'] as js.JSFunction;
    riveFileArtboardNamed = module['_riveFileArtboardNamed'] as js.JSFunction;
    riveFileArtboardByIndex =
        module['_riveFileArtboardByIndex'] as js.JSFunction;
    riveFileArtboardToBindNamed =
        module['_riveFileArtboardToBindNamed'] as js.JSFunction;
    riveFileViewModelCount = module['_riveFileViewModelCount'] as js.JSFunction;
    riveFileViewModelRuntimeByIndex =
        module['_riveFileViewModelRuntimeByIndex'] as js.JSFunction;
    riveFileViewModelRuntimeByName =
        module['_riveFileViewModelRuntimeByName'] as js.JSFunction;
    riveFileDefaultArtboardViewModelRuntime =
        module['_riveFileDefaultArtboardViewModelRuntime'] as js.JSFunction;
    viewModelRuntimePropertyCount =
        module['_viewModelRuntimePropertyCount'] as js.JSFunction;
    viewModelRuntimeInstanceCount =
        module['_viewModelRuntimeInstanceCount'] as js.JSFunction;
    viewModelRuntimeName = module['_viewModelRuntimeName'] as js.JSFunction;
    viewModelRuntimeProperties =
        module['viewModelRuntimeProperties'] as js.JSFunction;
    fileEnums = module['fileEnums'] as js.JSFunction;
    createVMIRuntimeFromIndex =
        module['_createVMIRuntimeFromIndex'] as js.JSFunction;
    createVMIRuntimeFromName =
        module['_createVMIRuntimeFromName'] as js.JSFunction;
    createDefaultVMIRuntime =
        module['_createDefaultVMIRuntime'] as js.JSFunction;
    createVMIRuntime = module['_createVMIRuntime'] as js.JSFunction;
    vmiRuntimeName = module['_vmiRuntimeName'] as js.JSFunction;
    vmiRuntimeProperties = module['vmiRuntimeProperties'] as js.JSFunction;
    vmiRuntimeGetViewModelProperty =
        module['_vmiRuntimeGetViewModelProperty'] as js.JSFunction;
    vmiRuntimeGetNumberProperty =
        module['_vmiRuntimeGetNumberProperty'] as js.JSFunction;
    getVMINumberRuntimeValue =
        module['_getVMINumberRuntimeValue'] as js.JSFunction;
    setVMINumberRuntimeValue =
        module['_setVMINumberRuntimeValue'] as js.JSFunction;
    vmiRuntimeGetStringProperty =
        module['_vmiRuntimeGetStringProperty'] as js.JSFunction;
    getVMIStringRuntimeValue =
        module['_getVMIStringRuntimeValue'] as js.JSFunction;
    setVMIStringRuntimeValue =
        module['_setVMIStringRuntimeValue'] as js.JSFunction;
    vmiRuntimeGetBooleanProperty =
        module['_vmiRuntimeGetBooleanProperty'] as js.JSFunction;
    getVMIBooleanRuntimeValue =
        module['_getVMIBooleanRuntimeValue'] as js.JSFunction;
    setVMIBooleanRuntimeValue =
        module['_setVMIBooleanRuntimeValue'] as js.JSFunction;
    vmiRuntimeGetColorProperty =
        module['_vmiRuntimeGetColorProperty'] as js.JSFunction;
    getVMIColorRuntimeValue =
        module['_getVMIColorRuntimeValue'] as js.JSFunction;
    setVMIColorRuntimeValue =
        module['_setVMIColorRuntimeValue'] as js.JSFunction;
    vmiRuntimeGetEnumProperty =
        module['_vmiRuntimeGetEnumProperty'] as js.JSFunction;
    getVMIEnumRuntimeValue = module['_getVMIEnumRuntimeValue'] as js.JSFunction;
    setVMIEnumRuntimeValue = module['_setVMIEnumRuntimeValue'] as js.JSFunction;
    getVMIEnumRuntimeEnumType =
        module['_getVMIEnumRuntimeEnumType'] as js.JSFunction;
    vmiRuntimeGetTriggerProperty =
        module['_vmiRuntimeGetTriggerProperty'] as js.JSFunction;
    triggerVMITriggerRuntime =
        module['_triggerVMITriggerRuntime'] as js.JSFunction;
    vmiRuntimeGetAssetImageProperty =
        module['_vmiRuntimeGetAssetImageProperty'] as js.JSFunction;
    vmiRuntimeGetAssetFontProperty =
        module['_vmiRuntimeGetAssetFontProperty'] as js.JSFunction;
    vmiRuntimeGetListProperty =
        module['_vmiRuntimeGetListProperty'] as js.JSFunction;
    getVMIListRuntimeSize = module['_getVMIListRuntimeSize'] as js.JSFunction;
    vmiListRuntimeAddInstance =
        module['_vmiListRuntimeAddInstance'] as js.JSFunction;
    vmiListRuntimeAddInstanceAt =
        module['_vmiListRuntimeAddInstanceAt'] as js.JSFunction;
    vmiListRuntimeRemoveInstance =
        module['_vmiListRuntimeRemoveInstance'] as js.JSFunction;
    vmiListRuntimeRemoveInstanceAt =
        module['_vmiListRuntimeRemoveInstanceAt'] as js.JSFunction;
    vmiListRuntimeInstanceAt =
        module['_vmiListRuntimeInstanceAt'] as js.JSFunction;
    vmiListRuntimeSwap = module['_vmiListRuntimeSwap'] as js.JSFunction;
    setVMIAssetImageRuntimeValue =
        module['_setVMIAssetImageRuntimeValue'] as js.JSFunction;
    setVMIAssetFontRuntimeValue =
        module['_setVMIAssetFontRuntimeValue'] as js.JSFunction;
    vmiRuntimeGetArtboardProperty =
        module['_vmiRuntimeGetArtboardProperty'] as js.JSFunction;
    setVMIArtboardRuntimeValue =
        module['_setVMIArtboardRuntimeValue'] as js.JSFunction;
    vmiValueRuntimeHasChanged =
        module['_vmiValueRuntimeHasChanged'] as js.JSFunction;
    vmiValueRuntimeClearChanges =
        module['_vmiValueRuntimeClearChanges'] as js.JSFunction;
    artboardSetVMIRuntime = module['_artboardSetVMIRuntime'] as js.JSFunction;
    stateMachineSetVMIRuntime =
        module['_stateMachineSetVMIRuntime'] as js.JSFunction;
    deleteVMIValueRuntime = module['_deleteVMIValueRuntime'] as js.JSFunction;
    deleteVMIRuntime = module['_deleteVMIRuntime'] as js.JSFunction;
    deleteViewModelRuntime = module['_deleteViewModelRuntime'] as js.JSFunction;
    artboardDraw = module['_artboardDraw'] as js.JSFunction;
    artboardDrawCanvases = module['_artboardDrawCanvases'] as js.JSFunction;
    artboardGetDrawCanvasLuauState =
        module['_artboardGetDrawCanvasLuauState'] as js.JSFunction;
    artboardDrawInternal = module['_artboardDrawInternal'] as js.JSFunction;
    artboardReset = module['_artboardReset'] as js.JSFunction;
    artboardName = module['_artboardName'] as js.JSFunction;
    artboardGetInnerPointer =
        module['_artboardGetInnerPointer'] as js.JSFunction;
    deleteArtboardInstance = module['_deleteArtboardInstance'] as js.JSFunction;
    deleteBindableArtboard = module['_deleteBindableArtboard'] as js.JSFunction;
    artboardAnimationCount = module['_artboardAnimationCount'] as js.JSFunction;
    artboardStateMachineCount =
        module['_artboardStateMachineCount'] as js.JSFunction;
    artboardAnimationAt = module['_artboardAnimationAt'] as js.JSFunction;
    artboardComponentNamed = module['_artboardComponentNamed'] as js.JSFunction;
    componentGetLocalBounds =
        module['_componentGetLocalBounds'] as js.JSFunction;
    componentGetWorldTransform =
        module['_componentGetWorldTransform'] as js.JSFunction;
    componentSetWorldTransform =
        module['_componentSetWorldTransform'] as js.JSFunction;
    artboardGetRenderTransform =
        module['_artboardGetRenderTransform'] as js.JSFunction;
    artboardSetRenderTransform =
        module['_artboardSetRenderTransform'] as js.JSFunction;
    componentGetScaleX = module['_componentGetScaleX'] as js.JSFunction;
    componentSetScaleX = module['_componentSetScaleX'] as js.JSFunction;
    componentGetX = module['_componentGetX'] as js.JSFunction;
    componentSetX = module['_componentSetX'] as js.JSFunction;
    componentGetScaleY = module['_componentGetScaleY'] as js.JSFunction;
    componentSetScaleY = module['_componentSetScaleY'] as js.JSFunction;
    componentGetY = module['_componentGetY'] as js.JSFunction;
    componentSetY = module['_componentSetY'] as js.JSFunction;
    componentGetRotation = module['_componentGetRotation'] as js.JSFunction;
    componentSetRotation = module['_componentSetRotation'] as js.JSFunction;
    componentSetLocalFromWorld =
        module['_componentSetLocalFromWorld'] as js.JSFunction;
    artboardAnimationNamed = module['_artboardAnimationNamed'] as js.JSFunction;
    artboardSetFrameOrigin = module['_artboardSetFrameOrigin'] as js.JSFunction;
    artboardGetFrameOrigin = module['_artboardGetFrameOrigin'] as js.JSFunction;
    animationInstanceName = module['_animationInstanceName'] as js.JSFunction;
    animationInstanceAdvance =
        module['_animationInstanceAdvance'] as js.JSFunction;
    animationInstanceApply = module['_animationInstanceApply'] as js.JSFunction;
    animationInstanceAdvanceAndApply =
        module['_animationInstanceAdvanceAndApply'] as js.JSFunction;
    animationInstanceGetTime =
        module['_animationInstanceGetTime'] as js.JSFunction;
    animationInstanceGetDuration =
        module['_animationInstanceGetDuration'] as js.JSFunction;
    animationInstanceGetLocalSeconds =
        module['_animationInstanceGetLocalSeconds'] as js.JSFunction;
    animationInstanceSetTime =
        module['_animationInstanceSetTime'] as js.JSFunction;
    animationInstanceDelete =
        module['_animationInstanceDelete'] as js.JSFunction;
    artboardAddToRenderPath =
        module['_artboardAddToRenderPath'] as js.JSFunction;
    artboardBounds = module['_artboardBounds'] as js.JSFunction;
    artboardWorldBounds = module['_artboardWorldBounds'] as js.JSFunction;
    artboardLayoutBounds = module['_artboardLayoutBounds'] as js.JSFunction;
    riveArtboardAdvance = module['_riveArtboardAdvance'] as js.JSFunction;
    riveArtboardGetOpacity = module['_riveArtboardGetOpacity'] as js.JSFunction;
    riveArtboardSetOpacity = module['_riveArtboardSetOpacity'] as js.JSFunction;
    riveArtboardSetHostOpacity =
        module['_riveArtboardSetHostOpacity'] as js.JSFunction;
    riveArtboardGetWidth = module['_riveArtboardGetWidth'] as js.JSFunction;
    riveArtboardSetWidth = module['_riveArtboardSetWidth'] as js.JSFunction;
    riveArtboardGetHeight = module['_riveArtboardGetHeight'] as js.JSFunction;
    riveArtboardSetHeight = module['_riveArtboardSetHeight'] as js.JSFunction;
    riveArtboardGetOriginX = module['_riveArtboardGetOriginX'] as js.JSFunction;
    riveArtboardSetOriginX = module['_riveArtboardSetOriginX'] as js.JSFunction;
    riveArtboardGetOriginY = module['_riveArtboardGetOriginY'] as js.JSFunction;
    riveArtboardSetOriginY = module['_riveArtboardSetOriginY'] as js.JSFunction;
    riveArtboardGetOriginalWidth =
        module['_riveArtboardGetOriginalWidth'] as js.JSFunction;
    riveArtboardGetOriginalHeight =
        module['_riveArtboardGetOriginalHeight'] as js.JSFunction;
    riveArtboardStateMachineDefault =
        module['_riveArtboardStateMachineDefault'] as js.JSFunction;
    riveArtboardStateMachineNamed =
        module['_riveArtboardStateMachineNamed'] as js.JSFunction;
    riveArtboardStateMachineAt =
        module['_riveArtboardStateMachineAt'] as js.JSFunction;
    riveArtboardHasComponentDirt =
        module['_riveArtboardHasComponentDirt'] as js.JSFunction;
    riveArtboardUpdatePass = module['_riveArtboardUpdatePass'] as js.JSFunction;
    setArtboardLayoutChangedCallback =
        module['setArtboardLayoutChangedCallback'] as js.JSFunction;
    setArtboardTestBoundsCallback =
        module['setArtboardTestBoundsCallback'] as js.JSFunction;
    setArtboardIsAncestorCallback =
        module['setArtboardIsAncestorCallback'] as js.JSFunction;
    setArtboardRootTransformCallback =
        module['setArtboardRootTransformCallback'] as js.JSFunction;
    setArtboardLayoutDirtyCallback =
        module['setArtboardLayoutDirtyCallback'] as js.JSFunction;
    setArtboardTransformDirtyCallback =
        module['setArtboardTransformDirtyCallback'] as js.JSFunction;
    deleteInput = module['_deleteInput'] as js.JSFunction;
    deleteComponent = module['_deleteComponent'] as js.JSFunction;
    deleteStateMachineInstance =
        module['_deleteStateMachineInstance'] as js.JSFunction;
    stateMachineInstanceName =
        module['_stateMachineInstanceName'] as js.JSFunction;
    stateMachineInstanceAdvance =
        module['_stateMachineInstanceAdvance'] as js.JSFunction;
    stateMachineInstanceAdvanceAndApply =
        module['_stateMachineInstanceAdvanceAndApply'] as js.JSFunction;
    stateMachineInstanceStateChangedCount =
        module['_stateMachineInstanceStateChangedCount'] as js.JSFunction;
    stateMachineInstanceStateChangedNameByIndex =
        module['_stateMachineInstanceStateChangedNameByIndex'] as js.JSFunction;
    setStateMachineInputChangedCallback =
        module['setStateMachineInputChangedCallback'] as js.JSFunction;
    setArtboardEventCallback =
        module['setArtboardEventCallback'] as js.JSFunction;
    stateMachineInput = module['_stateMachineInput'] as js.JSFunction;
    stateMachineInputName = module['_stateMachineInputName'] as js.JSFunction;
    stateMachineInputType = module['_stateMachineInputType'] as js.JSFunction;
    stateMachineInstanceNumber =
        module['_stateMachineInstanceNumber'] as js.JSFunction;
    stateMachineInstanceDone =
        module['_stateMachineInstanceDone'] as js.JSFunction;
    stateMachineInstanceHitTest =
        module['_stateMachineInstanceHitTest'] as js.JSFunction;
    stateMachineInstancePointerDown =
        module['_stateMachineInstancePointerDown'] as js.JSFunction;
    stateMachineInstancePointerUp =
        module['_stateMachineInstancePointerUp'] as js.JSFunction;
    stateMachineInstancePointerMove =
        module['_stateMachineInstancePointerMove'] as js.JSFunction;
    stateMachineInstancePointerExit =
        module['_stateMachineInstancePointerExit'] as js.JSFunction;
    stateMachineInstanceDragStart =
        module['_stateMachineInstanceDragStart'] as js.JSFunction;
    stateMachineInstanceDragEnd =
        module['_stateMachineInstanceDragEnd'] as js.JSFunction;
    stateMachineInstanceSubmitGamepadsFromBuffer =
        module['_stateMachineInstanceSubmitGamepadsFromBuffer']
            as js.JSFunction;
    makeGamepadInvocation = module['_makeGamepadInvocation'] as js.JSFunction;
    deleteGamepadInvocation =
        module['_deleteGamepadInvocation'] as js.JSFunction;
    stateMachineInstanceDispatchGamepadInvocation =
        module['_stateMachineInstanceDispatchGamepadInvocation']
            as js.JSFunction;

    stateMachineGetReportedEventCount =
        module['_stateMachineGetReportedEventCount'] as js.JSFunction;
    stateMachineReportedEventAt =
        module['stateMachineReportedEventAt'] as js.JSFunction;
    deleteEvent = module['_deleteEvent'] as js.JSFunction;
    deleteCustomProperty = module['_deleteCustomProperty'] as js.JSFunction;
    getEventName = module['_getEventName'] as js.JSFunction;
    getOpenUrlEventUrl = module['_getOpenUrlEventUrl'] as js.JSFunction;
    getOpenUrlEventTarget = module['_getOpenUrlEventTarget'] as js.JSFunction;
    getAudioEventAssetId = module['_getAudioEventAssetId'] as js.JSFunction;
    getAudioEventAssetName = module['_getAudioEventAssetName'] as js.JSFunction;
    getAudioEventVolume = module['_getAudioEventVolume'] as js.JSFunction;
    getEventCustomPropertyCount =
        module['_getEventCustomPropertyCount'] as js.JSFunction;
    getEventCustomProperty = module['getEventCustomProperty'] as js.JSFunction;
    getCustomPropertyNumber =
        module['_getCustomPropertyNumber'] as js.JSFunction;
    getCustomPropertyBoolean =
        module['_getCustomPropertyBoolean'] as js.JSFunction;
    getCustomPropertyString =
        module['_getCustomPropertyString'] as js.JSFunction;
    getNumberValue = module['_getNumberValue'] as js.JSFunction;
    setNumberValue = module['_setNumberValue'] as js.JSFunction;
    stateMachineInstanceBoolean =
        module['_stateMachineInstanceBoolean'] as js.JSFunction;
    getBooleanValue = module['_getBooleanValue'] as js.JSFunction;
    setBooleanValue = module['_setBooleanValue'] as js.JSFunction;
    stateMachineInstanceTrigger =
        module['_stateMachineInstanceTrigger'] as js.JSFunction;
    fireTrigger = module['_fireTrigger'] as js.JSFunction;
    stateMachineInstanceBatchAdvance =
        module['_stateMachineInstanceBatchAdvance'] as js.JSFunction;
    stateMachineInstanceBatchAdvanceAndRender =
        module['_stateMachineInstanceBatchAdvanceAndRender'] as js.JSFunction;
    artboardSetText = module['_artboardSetText'] as js.JSFunction;
    artboardGetText = module['_artboardGetText'] as js.JSFunction;
    artboardGetAllTextRuns = module['artboardGetAllTextRuns'] as js.JSFunction;
    freeTextRunsArray = module['_freeTextRunsArray'] as js.JSFunction;
    getTextRunFromArray = module['_getTextRunFromArray'] as js.JSFunction;
    deleteTextValueRun = module['_deleteTextValueRun'] as js.JSFunction;
    textValueRunName = module['_textValueRunName'] as js.JSFunction;
    textValueRunText = module['_textValueRunText'] as js.JSFunction;
    textValueRunPath = module['_textValueRunPath'] as js.JSFunction;
    textValueRunSetText = module['_textValueRunSetText'] as js.JSFunction;
    artboardTakeLayoutNode = module['_artboardTakeLayoutNode'] as js.JSFunction;
    artboardAddedToHost = module['_artboardAddedToHost'] as js.JSFunction;
    artboardSyncStyleChanges =
        module['_artboardSyncStyleChanges'] as js.JSFunction;
    artboardWidthOverride = module['_artboardWidthOverride'] as js.JSFunction;
    artboardHeightOverride = module['_artboardHeightOverride'] as js.JSFunction;
    artboardParentIsRow = module['_artboardParentIsRow'] as js.JSFunction;
    artboardWidthIntrinsicallySizeOverride =
        module['_artboardWidthIntrinsicallySizeOverride'] as js.JSFunction;
    artboardHeightIntrinsicallySizeOverride =
        module['_artboardHeightIntrinsicallySizeOverride'] as js.JSFunction;
    updateLayoutBounds = module['_updateLayoutBounds'] as js.JSFunction;
    cascadeLayoutStyle = module['_cascadeLayoutStyle'] as js.JSFunction;
    cascadeLayoutStyleBatch =
        module['_cascadeLayoutStyleBatch'] as js.JSFunction;
    cascadeCollapseBatch = module['_cascadeCollapseBatch'] as js.JSFunction?;
    cascadeCollapse = module['_cascadeCollapse'] as js.JSFunction?;

    makeFlutterRenderImage = module['_makeFlutterRenderImage'] as js.JSFunction;
    flutterRenderImageId = module['_flutterRenderImageId'] as js.JSFunction;
    riveDataContext = module['_riveDataContext'] as js.JSFunction;
    riveDataContextFromInstances =
        module['_riveDataContextFromInstances'] as js.JSFunction;
    dataContextViewModelInstanceAt =
        module['_dataContextViewModelInstanceAt'] as js.JSFunction;
    dataContextFromViewModelInstancePointers =
        module['_dataContextFromViewModelInstancePointers'] as js.JSFunction;
    deleteDataContext = module['_deleteDataContext'] as js.JSFunction;
    deleteViewModelInstance =
        module['_deleteViewModelInstance'] as js.JSFunction;
    deleteViewModelInstanceValue =
        module['_deleteViewModelInstanceValue'] as js.JSFunction;
    riveDataContextViewModelInstance =
        module['_riveDataContextViewModelInstance'] as js.JSFunction;
    viewModelInstancePropertyValue =
        module['_viewModelInstancePropertyValue'] as js.JSFunction;
    pruneViewModelInstanceToProperties =
        module['_pruneViewModelInstanceToProperties'] as js.JSFunction;
    viewModelInstanceListItemViewModel =
        module['_viewModelInstanceListItemViewModel'] as js.JSFunction;
    viewModelInstanceListSize =
        module['_viewModelInstanceListSize'] as js.JSFunction;
    viewModelInstanceReferenceViewModel =
        module['_viewModelInstanceReferenceViewModel'] as js.JSFunction;
    setViewModelInstanceNumberValue =
        module['_setViewModelInstanceNumberValue'] as js.JSFunction;
    setViewModelInstanceColorValue =
        module['_setViewModelInstanceColorValue'] as js.JSFunction;
    setViewModelInstanceStringValue =
        module['_setViewModelInstanceStringValue'] as js.JSFunction;
    setViewModelInstanceBooleanValue =
        module['_setViewModelInstanceBooleanValue'] as js.JSFunction;
    setViewModelInstanceTriggerValue =
        module['_setViewModelInstanceTriggerValue'] as js.JSFunction;
    setViewModelInstanceAssetValue =
        module['_setViewModelInstanceAssetValue'] as js.JSFunction;
    viewModelInstanceAssetImageResolveRuntimeIndex =
        module['_viewModelInstanceAssetImageResolveRuntimeIndex']
            as js.JSFunction;
    viewModelInstanceAssetFontResolveRuntimeIndex =
        module['_viewModelInstanceAssetFontResolveRuntimeIndex']
            as js.JSFunction;
    setViewModelInstanceArtboardValue =
        module['_setViewModelInstanceArtboardValue'] as js.JSFunction;
    setViewModelInstanceAdvanced =
        module['_setViewModelInstanceAdvanced'] as js.JSFunction;
    setViewModelInstanceEnumValue =
        module['_setViewModelInstanceEnumValue'] as js.JSFunction;
    setViewModelInstanceSymbolListIndexValue =
        module['_setViewModelInstanceSymbolListIndexValue'] as js.JSFunction;
    setViewModelInstanceListValue =
        module['_setViewModelInstanceListValue'] as js.JSFunction;
    copyViewModelInstance = module['_copyViewModelInstance'] as js.JSFunction;
    riveDataBindDirt = module['_riveDataBindDirt'] as js.JSFunction;
    riveDataBindSetDirt = module['_riveDataBindSetDirt'] as js.JSFunction;
    riveDataBindFlags = module['_riveDataBindFlags'] as js.JSFunction;
    riveDataBindUpdate = module['_riveDataBindUpdate'] as js.JSFunction;
    riveDataBindUpdateSourceBinding =
        module['_riveDataBindUpdateSourceBinding'] as js.JSFunction;
    artboardClearDataContext =
        module['_artboardClearDataContext'] as js.JSFunction;
    artboardUnbind = module['_artboardUnbind'] as js.JSFunction;
    artboardUpdateDataBinds =
        module['_artboardUpdateDataBinds'] as js.JSFunction;
    artboardDataContextFromInstance =
        module['_artboardDataContextFromInstance'] as js.JSFunction;
    artboardInternalDataContext =
        module['_artboardInternalDataContext'] as js.JSFunction;
    artboardDataContext = module['_artboardDataContext'] as js.JSFunction;
    stateMachineDataContextFromInstance =
        module['_stateMachineDataContextFromInstance'] as js.JSFunction;
    stateMachineDataContext =
        module['_stateMachineDataContext'] as js.JSFunction;
    setStateMachineDataBindChangedCallback =
        module['setStateMachineDataBindChangedCallback'] as js.JSFunction;
    setViewModelInstanceNumberCallback =
        module['_setViewModelInstanceNumberCallback'] as js.JSFunction;
    setViewModelInstanceBooleanCallback =
        module['_setViewModelInstanceBooleanCallback'] as js.JSFunction;
    setViewModelInstanceColorCallback =
        module['_setViewModelInstanceColorCallback'] as js.JSFunction;
    setViewModelInstanceStringCallback =
        module['_setViewModelInstanceStringCallback'] as js.JSFunction;
    setViewModelInstanceTriggerCallback =
        module['_setViewModelInstanceTriggerCallback'] as js.JSFunction;
    setViewModelInstanceEnumCallback =
        module['_setViewModelInstanceEnumCallback'] as js.JSFunction;
    setViewModelInstanceSymbolListIndexCallback =
        module['_setViewModelInstanceSymbolListIndexCallback'] as js.JSFunction;
    setViewModelInstanceAssetCallback =
        module['_setViewModelInstanceAssetCallback'] as js.JSFunction;
    setViewModelInstanceArtboardCallback =
        module['_setViewModelInstanceArtboardCallback'] as js.JSFunction;
    setViewModelInstanceListCallback =
        module['_setViewModelInstanceListCallback'] as js.JSFunction;
    setViewModelInstanceViewModelValue =
        module['_setViewModelInstanceViewModelValue'] as js.JSFunction;
    setViewModelInstanceViewModelCallback =
        module['_setViewModelInstanceViewModelCallback'] as js.JSFunction;
    initBindingCallbacks = module['initBindingCallbacks'] as js.JSFunction;

    // Focus-related artboard/state machine functions
    artboardRootFocusDataCount =
        module['_artboardRootFocusDataCount'] as js.JSFunction?;
    artboardRootFocusNodeAt =
        module['_artboardRootFocusNodeAt'] as js.JSFunction?;
    artboardSetExternalParentFocusNode =
        module['_artboardSetExternalParentFocusNode'] as js.JSFunction?;
    artboardBuildFocusTreeWithParent =
        module['_artboardBuildFocusTreeWithParent'] as js.JSFunction;
    stateMachineGetFocusManager =
        module['_stateMachineGetFocusManager'] as js.JSFunction;
    stateMachineSetExternalFocusManager =
        module['_stateMachineSetExternalFocusManager'] as js.JSFunction;

    deleteDashPathEffect = module['_deleteDashPathEffect'] as js.JSFunction;
    makeDashPathEffect = module['_makeDashPathEffect'] as js.JSFunction;
    dashPathEffectGetOffset =
        module['_dashPathEffectGetOffset'] as js.JSFunction;
    dashPathEffectGetPathLength =
        module['_dashPathEffectGetPathLength'] as js.JSFunction;
    dashPathEffectSetOffset =
        module['_dashPathEffectSetOffset'] as js.JSFunction;
    dashPathEffectGetOffsetIsPercentage =
        module['_dashPathEffectGetOffsetIsPercentage'] as js.JSFunction;
    dashPathEffectSetOffsetIsPercentage =
        module['_dashPathEffectSetOffsetIsPercentage'] as js.JSFunction;
    dashPathClearDashes = module['_dashPathClearDashes'] as js.JSFunction;
    dashPathAddDash = module['_dashPathAddDash'] as js.JSFunction;
    dashPathInvalidate = module['_dashPathInvalidate'] as js.JSFunction;
    dashPathEffectPath = module['_dashPathEffectPath'] as js.JSFunction;
    renderPathColinearCheck =
        module['_renderPathColinearCheck'] as js.JSFunction;
    renderPathPreciseBounds =
        module['_renderPathPreciseBounds'] as js.JSFunction;
    renderPathPreciseLength =
        module['_renderPathPreciseLength'] as js.JSFunction;
    renderPathBounds = module['_renderPathBounds'] as js.JSFunction;
    renderPathIsClosed = module['_renderPathIsClosed'] as js.JSFunction;
    renderPathHasBounds = module['_renderPathHasBounds'] as js.JSFunction;
    renderPathCopyBuffers = module['_renderPathCopyBuffers'] as js.JSFunction;
    renderPathIsClockwise = module['_renderPathIsClockwise'] as js.JSFunction;

    makeRawText = module['_makeRawText'] as js.JSFunction;
    deleteRawText = module['_deleteRawText'] as js.JSFunction;
    rawTextAppend = module['_rawTextAppend'] as js.JSFunction;
    rawTextClear = module['_rawTextClear'] as js.JSFunction;
    rawTextIsEmpty = module['_rawTextIsEmpty'] as js.JSFunction;
    rawTextGetSizing = module['_rawTextGetSizing'] as js.JSFunction;
    rawTextSetSizing = module['_rawTextSetSizing'] as js.JSFunction;
    rawTextGetOverflow = module['_rawTextGetOverflow'] as js.JSFunction;
    rawTextSetOverflow = module['_rawTextSetOverflow'] as js.JSFunction;
    rawTextGetAlign = module['_rawTextGetAlign'] as js.JSFunction;
    rawTextSetAlign = module['_rawTextSetAlign'] as js.JSFunction;
    rawTextGetMaxWidth = module['_rawTextGetMaxWidth'] as js.JSFunction;
    rawTextSetMaxWidth = module['_rawTextSetMaxWidth'] as js.JSFunction;
    rawTextGetMaxHeight = module['_rawTextGetMaxHeight'] as js.JSFunction;
    rawTextSetMaxHeight = module['_rawTextSetMaxHeight'] as js.JSFunction;
    rawTextGetParagraphSpacing =
        module['_rawTextGetParagraphSpacing'] as js.JSFunction;
    rawTextSetParagraphSpacing =
        module['_rawTextSetParagraphSpacing'] as js.JSFunction;
    rawTextBounds = module['_rawTextBounds'] as js.JSFunction;
    rawTextRender = module['_rawTextRender'] as js.JSFunction;

    makeRawTextInput = module['_makeRawTextInput'] as js.JSFunction;
    deleteRawTextInput = module['_deleteRawTextInput'] as js.JSFunction;
    rawTextInputGetFontSize =
        module['_rawTextInputGetFontSize'] as js.JSFunction;
    rawTextInputSetFontSize =
        module['_rawTextInputSetFontSize'] as js.JSFunction;
    rawTextInputSetFont = module['_rawTextInputSetFont'] as js.JSFunction;
    rawTextInputGetMaxHeight =
        module['_rawTextInputGetMaxHeight'] as js.JSFunction;
    rawTextInputSetMaxHeight =
        module['_rawTextInputSetMaxHeight'] as js.JSFunction;
    rawTextInputGetMaxWidth =
        module['_rawTextInputGetMaxWidth'] as js.JSFunction;
    rawTextInputSetMaxWidth =
        module['_rawTextInputSetMaxWidth'] as js.JSFunction;
    rawTextInputGetParagraphSpacing =
        module['_rawTextInputGetParagraphSpacing'] as js.JSFunction;
    rawTextInputSetParagraphSpacing =
        module['_rawTextInputSetParagraphSpacing'] as js.JSFunction;
    rawTextInputGetSizing = module['_rawTextInputGetSizing'] as js.JSFunction;
    rawTextInputSetSizing = module['_rawTextInputSetSizing'] as js.JSFunction;
    rawTextInputGetOverflow =
        module['_rawTextInputGetOverflow'] as js.JSFunction;
    rawTextInputSetOverflow =
        module['_rawTextInputSetOverflow'] as js.JSFunction;
    rawTextInputGetSelectionCornerRadius =
        module['_rawTextInputGetSelectionCornerRadius'] as js.JSFunction;
    rawTextInputSetSelectionCornerRadius =
        module['_rawTextInputSetSelectionCornerRadius'] as js.JSFunction;
    rawTextInputGetSeparateSelectionText =
        module['_rawTextInputGetSeparateSelectionText'] as js.JSFunction;
    rawTextInputSetSeparateSelectionText =
        module['_rawTextInputSetSeparateSelectionText'] as js.JSFunction;
    rawTextInputGetText = module['_rawTextInputGetText'] as js.JSFunction;
    rawTextInputSetText = module['_rawTextInputSetText'] as js.JSFunction;
    rawTextInputSetTextPreserveCursor =
        module['_rawTextInputSetTextPreserveCursor'] as js.JSFunction;
    freeString = module['_freeString'] as js.JSFunction;
    rawTextInputLength = module['_rawTextInputLength'] as js.JSFunction;
    rawTextInputBounds = module['_rawTextInputBounds'] as js.JSFunction;
    rawTextInputUpdate = module['_rawTextInputUpdate'] as js.JSFunction;
    rawTextInsertText = module['_rawTextInsertText'] as js.JSFunction;
    rawTextInsertCodePoint = module['_rawTextInsertCodePoint'] as js.JSFunction;
    rawTextErase = module['_rawTextErase'] as js.JSFunction;
    rawTextBackspace = module['_rawTextBackspace'] as js.JSFunction;
    rawTextCursorLeft = module['_rawTextCursorLeft'] as js.JSFunction;
    rawTextCursorRight = module['_rawTextCursorRight'] as js.JSFunction;
    rawTextCursorUp = module['_rawTextCursorUp'] as js.JSFunction;
    rawTextCursorDown = module['_rawTextCursorDown'] as js.JSFunction;
    rawTextMoveCursorTo = module['_rawTextMoveCursorTo'] as js.JSFunction;
    rawTextUndo = module['_rawTextUndo'] as js.JSFunction;
    rawTextRedo = module['_rawTextRedo'] as js.JSFunction;
    rawTextInputMeasure = module['_rawTextInputMeasure'] as js.JSFunction;
    rawTextSelectWord = module['_rawTextSelectWord'] as js.JSFunction;
    rawTextHasSelection = module['_rawTextHasSelection'] as js.JSFunction;
    rawTextClearSelection = module['_rawTextClearSelection'] as js.JSFunction;
    rawTextTextPath = module['_rawTextTextPath'] as js.JSFunction;
    rawTextSelectedTextPath =
        module['_rawTextSelectedTextPath'] as js.JSFunction;
    rawTextCursorPath = module['_rawTextCursorPath'] as js.JSFunction;
    rawTextSelectionPath = module['_rawTextSelectionPath'] as js.JSFunction;
    rawTextClipPath = module['_rawTextClipPath'] as js.JSFunction;
    rawTextInputCursorPosition =
        module['_rawTextInputCursorPosition'] as js.JSFunction;
    riveAdvanceFrameId = module['_riveAdvanceFrameId'] as js.JSFunction;

    // Profiler bindings
    profilerStart = module['profilerStart'] as js.JSFunction?;
    profilerStop = module['profilerStop'] as js.JSFunction?;
    profilerIsActive = module['profilerIsActive'] as js.JSFunction?;
    profilerDump = module['profilerDump'] as js.JSFunction?;
    profilerGetBufferPtr = module['profilerGetBufferPtr'] as js.JSFunction?;
    profilerGetBufferSize = module['profilerGetBufferSize'] as js.JSFunction?;
    profilerFreeBuffer = module['profilerFreeBuffer'] as js.JSFunction?;
    profilerEndFrame = module['profilerEndFrame'] as js.JSFunction?;

    WebRiveFactory.instance.pointer =
        (module['_rendererContext'] as js.JSFunction).callAsFunction(null)
            as js.JSAny;

    _stringScratchBuffer = WasmBuffer(scratchBufferSize);
  }

  static late WasmBuffer _stringScratchBuffer;
  static T toNativeString<T>(
    String value,
    T Function(js.JSAny valuePointer) callback,
  ) {
    final units = utf8.encode(value);
    final length = units.length + 1;
    WasmBuffer buffer = length < scratchBufferSize
        ? _stringScratchBuffer
        : WasmBuffer(units.length + 1);
    buffer.data.setRange(0, units.length, units);
    buffer.data[units.length] = 0;
    T result = callback(buffer.pointer);
    if (buffer != _stringScratchBuffer) {
      buffer.dispose();
    }
    return result;
  }
}

/// Extension method for converting a [String] to a WASM heap backed string.
extension StringUtf8Wasm on String {
  /// Creates a zero-terminated [Utf8] code-unit array from this String.
  WasmBuffer toWasmUtf8() {
    final units = utf8.encode(this);
    var buffer = WasmBuffer(units.length + 1);
    buffer.data.setRange(0, units.length, units);
    buffer.data[units.length] = 0;
    return buffer;
  }
}

class _WebRiveNative extends RiveNative {
  @override
  RenderTexture makeRenderTexture() => _WebRenderTexture.make();

  /// Destroys the pooled render textures and the shared offscreen probe,
  /// each of which holds a live WebGL context (browsers cap those at ~16
  /// per process) — an idle page drops to zero live contexts.
  @override
  void releaseRenderResources() {
    _WebRenderTexture.releasePool();
    RiveWasm.releaseOffscreenGL.callAsFunction(null);
    _debugLogTexture('released pooled textures and offscreen probe');
  }
}

bool get isRuntimeEnvironment =>
    const String.fromEnvironment('RIVE_ENVIRONMENT', defaultValue: 'runtime') ==
    'runtime';

bool get isLocalEnvironment =>
    const bool.fromEnvironment('LOCAL_RIVE_NATIVE', defaultValue: false);

const wasmHost = bool.hasEnvironment("RIVE_NATIVE_WASM_HOST")
    ? String.fromEnvironment("RIVE_NATIVE_WASM_HOST")
    : null;

String _wasmHost() {
  if (wasmHost != null) {
    return wasmHost!;
  }
  if (isLocalEnvironment) {
    return 'http://localhost:8282/release/';
  } else if (isRuntimeEnvironment) {
    return 'https://cdn.jsdelivr.net/npm/@rive-app/'
        'flutter-native-wasm@$wasmVersion/';
  }
  return '';
}

Future<RiveNative?> _loadWasm(String source, String name) async {
  var script = html.HTMLScriptElement()
    ..src = _wasmHost() + source
    ..type = 'application/javascript'
    ..defer = true;

  html.document.body!.append(script);
  await script.onLoad.first;
  var initWasm = js.globalContext[name] as js.JSFunction;
  var promise = initWasm.callAsFunction() as js.JSObject;
  var thenFunction = promise['then'] as js.JSFunction;

  var completer = Completer<RiveNative?>();
  thenFunction.callAsFunction(
    promise,
    (js.JSAny? moduleAny) {
      // dart:js_interop delivers promise resolution values as JSAny?; cast
      // to JSObject after the fact so the .toJS wrapper doesn't throw.
      final module = moduleAny as js.JSObject;
      RiveWasm.link(module);
      LayoutEngineWasm.link(module);
      if (!isRuntimeEnvironment) {
        // Add scripting workspace for the Editor
        ScriptingWorkspaceWasm.link(module);
        LuauStateWasm.link(module);
        PathOpsWasm.link(module);
      }
      TextEngine.link(module);
      AudioEngineWasm.link(module);
      FocusManagerWasm.link(module);
      SemanticsWasm.link(module);
      completer.complete(_WebRiveNative());
    }.toJS,
    ((js.JSAny? error) => completer.complete(null)).toJS,
  );
  return completer.future;
}

Future<RiveNative?> makeRiveNative() async {
  RiveNative? result;

  if ((result = await _loadWasm('wasm/rive_native.js', 'RiveNative')) != null) {
    return result;
  }
  if ((result = await _loadWasm(
        'wasm_compatibility/rive_native.js',
        'RiveNative',
      )) !=
      null) {
    return result;
  }
  return null;
}

class _RiveNativeWebView extends LeafRenderObjectWidget {
  final _WebRenderTexture renderTexture;
  final RenderTexturePainter? painter;
  final RenderResolution resolution;
  const _RiveNativeWebView(this.renderTexture, this.painter, this.resolution,
      {super.key});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RiveNativeWebViewRenderObject(renderTexture, painter)
      ..renderResolution = resolution
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..tickerModeEnabled = TickerMode.of(context);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RiveNativeWebViewRenderObject renderObject,
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
    covariant _RiveNativeWebViewRenderObject renderObject,
  ) {
    renderObject.painter = null;
  }
}

class _RiveNativeWebViewRenderObject extends RiveNativeRenderBox {
  _RiveNativeWebViewRenderObject(
    super._renderTexture,
    RenderTexturePainter? renderTexturePainter,
  ) {
    painter = renderTexturePainter;
  }

  // Syncing eagerly consumes the "changed" state, so performLayout doesn't
  // kick a redundant repaint for changes whose rebuild already woke the ticker.
  @override
  set renderResolution(RenderResolution value) {
    super.renderResolution = value;
    _syncBackingPolicy();
  }

  @override
  set renderTexture(RenderTexture value) {
    super.renderTexture = value;
    _syncBackingPolicy();
  }

  /// Pushes the resolution policy to the texture, which owns the JS wire
  /// protocol `clearRenderer` sizes the canvas from. Returns whether anything
  /// changed. Display carries the measured ancestor paint scale per axis —
  /// the same allocation policy as native.
  bool _syncBackingPolicy() {
    final texture = renderTexture;
    if (texture is! _WebRenderTexture) {
      return false;
    }
    final (fixedWidth, fixedHeight, scaleX, scaleY) =
        switch (renderResolution) {
      FixedRenderResolution(:final width, :final height) => (
          width,
          height,
          1.0,
          1.0
        ),
      LayoutRenderResolution(:final scale) => (0, 0, scale, scale),
      DisplayRenderResolution() => (
          0,
          0,
          desiredTransformWidthScale,
          desiredTransformHeightScale
        ),
    };
    return texture.setBackingPolicy(
      fixedWidth: fixedWidth,
      fixedHeight: fixedHeight,
      scaleX: scaleX,
      scaleY: scaleY,
      maxLogical: RiveNativeRenderBox.maxTextureLogicalSize,
    );
  }

  @override
  void performLayout() {
    // Read before super.performLayout(), which restarts the ticker and would
    // mask whether the graphic was actually settled.
    final wasTickerActive = isTickerActive;
    super.performLayout();
    // Display-policy remeasures land here via post-frame markNeedsLayout. A
    // ticker that was already running repaints at the new backing on its own;
    // settled content and painterless surfaces need the kick — a pure
    // transform change never fires the ResizeObserver.
    if (_syncBackingPolicy() && !wasTickerActive) {
      renderTexture.textureChanged();
    }
  }

  @override
  double get devicePixelRatio => html.window.devicePixelRatio;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Measures the ancestor paint scale (display policy only) exactly like
    // native; the scales reach the canvas backing via performLayout's sync.
    super.paint(context, offset);
    final painter = rivePainter;
    if (painter != null && painter.paintsCanvas) {
      painter.paintCanvas(context.canvas, offset, size);
    }
  }
}
