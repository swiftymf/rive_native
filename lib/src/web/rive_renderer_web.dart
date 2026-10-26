import 'dart:js_interop' as js;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:rive_native/rive_native.dart';
import 'package:rive_native/rive_text.dart';
import 'package:rive_native/src/buffered_render_paint.dart';
import 'package:rive_native/src/buffered_render_path.dart';
import 'package:rive_native/src/rive_native_web.dart';
import 'package:rive_native/src/utilities/utilities.dart';
import 'package:rive_native/src/web/rive_text_web.dart';
import 'package:rive_native/src/web/rive_web.dart';

class WebRenderBuffer extends RenderBuffer {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteRenderBuffer.callAsFunction(null, pointer),
  );

  js.JSAny get pointer => _pointer;
  js.JSAny _pointer;

  @override
  final int elementCount;

  WebRenderBuffer(this.elementCount, this._pointer) {
    _finalizer.attach(this, _pointer, detach: this);
  }

  @override
  void dispose() {
    _finalizer.detach(this);
    RiveWasm.deleteRenderBuffer.callAsFunction(null, _pointer);
    _pointer = 0.toJS;
  }

  Float32List toFloat32List(int length) {
    return RiveWasm.heapViewF32(
      (RiveWasm.mapRenderBuffer.callAsFunction(null, pointer) as js.JSNumber)
          .toDartInt,
      length,
    );
  }

  Uint16List toUint16List(int length) {
    return RiveWasm.heapViewU16(
      (RiveWasm.mapRenderBuffer.callAsFunction(null, pointer) as js.JSNumber)
          .toDartInt,
      length,
    );
  }
}

class WebIndexRenderBuffer extends WebRenderBuffer
    implements IndexRenderBuffer {
  WebIndexRenderBuffer(WebFactory riveFactory, int elementCount)
      : super(
          elementCount,
          RiveWasm.makeIndexRenderBuffer.callAsFunction(
            null,
            riveFactory.pointer,
            elementCount.toJS,
          ) as js.JSAny,
        );

  @override
  void setIndices(Uint16List indices) {
    assert(indices.length == elementCount);
    final indexBuffer = toUint16List(indices.length);
    indexBuffer.setRange(0, indexBuffer.length, indices);
    RiveWasm.unmapRenderBuffer.callAsFunction(null, pointer);
  }
}

class WebVertexRenderBuffer extends WebRenderBuffer
    implements VertexRenderBuffer {
  WebVertexRenderBuffer(WebFactory riveFactory, int elementCount)
      : super(
          elementCount,
          RiveWasm.makeVertexRenderBuffer.callAsFunction(
            null,
            riveFactory.pointer,
            elementCount.toJS,
          ) as js.JSAny,
        );

  @override
  void setVertices(Float32List vertices) {
    assert(vertices.length == elementCount * 2);
    var vertexBuffer = toFloat32List(vertices.length);
    vertexBuffer.setRange(0, vertexBuffer.length, vertices);
    RiveWasm.unmapRenderBuffer.callAsFunction(null, pointer);
  }
}

class WebRenderImage extends RenderImage {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteRenderImage.callAsFunction(null, pointer),
  );
  js.JSAny _pointer;
  js.JSAny get pointer => _pointer;

  WebRenderImage(this._pointer) {
    _finalizer.attach(this, _pointer, detach: this);
  }

  @override
  int get width =>
      (RiveWasm.renderImageWidth.callAsFunction(null, _pointer) as js.JSNumber)
          .toDartInt;

  @override
  int get height =>
      (RiveWasm.renderImageHeight.callAsFunction(null, _pointer) as js.JSNumber)
          .toDartInt;

  @override
  void dispose() {
    _finalizer.detach(this);
    RiveWasm.deleteRenderImage.callAsFunction(null, _pointer);
    _pointer = 0.toJS;
  }
}

class WebRenderText extends RenderText {
  static final Finalizer<js.JSAny?> _finalizer = Finalizer(
    (nativePtr) => RiveWasm.deleteRawText.callAsFunction(null, nativePtr),
  );

  js.JSAny? _rawText;
  js.JSAny? get pointer => _rawText;

  WebRenderText(WebFactory riveFactory)
      : _rawText = RiveWasm.makeRawText
            .callAsFunction(null, riveFactory.pointer) as js.JSAny {
    _finalizer.attach(this, _rawText, detach: this);
  }

  @override
  void dispose() {
    if (_rawText == null) {
      return;
    }
    RiveWasm.deleteRawText.callAsFunction(null, _rawText);
    _rawText = null;
    _finalizer.detach(this);
  }

  @override
  void append(
    String text, {
    required covariant FontWasm font,
    covariant WebRenderPaint? paint,
    double size = 16,
    double lineHeight = -1,
    double letterSpacing = 0,
  }) {
    final nativeString = text.toWasmUtf8();
    RiveWasm.rawTextAppend.callAsFunctionEx(
      null,
      _rawText,
      nativeString.pointer,
      paint?.pointer ?? 0.toJS,
      font.fontPtr.toJS,
      size.toJS,
      lineHeight.toJS,
      letterSpacing.toJS,
    );
    nativeString.dispose();
  }

  @override
  void clear() => RiveWasm.rawTextClear.callAsFunction(null, _rawText);

  @override
  TextSizing get sizing => TextSizing.values.elementAtOrFirst(
        (RiveWasm.rawTextGetSizing.callAsFunction(null, _rawText)
                as js.JSNumber)
            .toDartInt,
      );

  @override
  set sizing(TextSizing value) => RiveWasm.rawTextSetSizing.callAsFunction(
        null,
        _rawText,
        value.index.toJS,
      );

  @override
  TextOverflow get overflow => TextOverflow.values.elementAtOrFirst(
        (RiveWasm.rawTextGetOverflow.callAsFunction(null, _rawText)
                as js.JSNumber)
            .toDartInt,
      );

  @override
  set overflow(TextOverflow value) => RiveWasm.rawTextSetOverflow
      .callAsFunction(null, _rawText, value.index.toJS);

  @override
  TextAlign get align => TextAlign.values.elementAtOrFirst(
        (RiveWasm.rawTextGetAlign.callAsFunction(null, _rawText) as js.JSNumber)
            .toDartInt,
      );

  @override
  set align(TextAlign value) =>
      RiveWasm.rawTextSetAlign.callAsFunction(null, _rawText, value.index.toJS);

  @override
  double get maxWidth =>
      (RiveWasm.rawTextGetMaxWidth.callAsFunction(null, _rawText)
              as js.JSNumber)
          .toDartDouble;

  @override
  set maxWidth(double value) =>
      RiveWasm.rawTextSetMaxWidth.callAsFunction(null, _rawText, value.toJS);

  @override
  double get maxHeight =>
      (RiveWasm.rawTextGetMaxHeight.callAsFunction(null, _rawText)
              as js.JSNumber)
          .toDartDouble;

  @override
  set maxHeight(double value) =>
      RiveWasm.rawTextSetMaxHeight.callAsFunction(null, _rawText, value.toJS);

  @override
  double get paragraphSpacing =>
      (RiveWasm.rawTextGetParagraphSpacing.callAsFunction(null, _rawText)
              as js.JSNumber)
          .toDartDouble;

  @override
  set paragraphSpacing(double value) => RiveWasm.rawTextSetParagraphSpacing
      .callAsFunction(null, _rawText, value.toJS);

  @override
  AABB get bounds {
    RiveWasm.rawTextBounds.callAsFunction(
      null,
      _rawText,
      RiveWasm.scratchBufferPtr,
    );

    final floats = RiveWasm.scratchBufferFloat;

    return AABB.fromValues(floats[0], floats[1], floats[2], floats[3]);
  }

  @override
  bool get isEmpty =>
      _wasmBool(RiveWasm.rawTextIsEmpty.callAsFunction(null, _rawText));
}

class WebRiveFactory extends WebFactory {
  WebRiveFactory._() : super(0.toJS);

  @override
  Future<void> completedDecodingFile(bool success) async {}

  static final WebRiveFactory _instance = WebRiveFactory._();

  static WebRiveFactory get instance => _instance;

  @override
  bool isValidRenderer(Renderer renderer) => renderer is WebRiveRenderer;
}

class WebRenderPath extends BufferedRenderPath {
  final WebFactory riveFactory;
  js.JSAny? _renderPath;
  static final Finalizer<js.JSAny?> _finalizer = Finalizer(
    (nativePtr) => RiveWasm.deleteRenderPath.callAsFunction(null, nativePtr),
  );

  js.JSAny? get pointer {
    update();
    return _renderPath;
  }

  WebRenderPath(this.riveFactory, bool initEmpty) {
    if (initEmpty) {
      _renderPath = RiveWasm.makeEmptyRenderPath.callAsFunction(
        null,
        riveFactory.pointer,
      );
      _finalizer.attach(this, _renderPath, detach: this);
    }
  }

  WebRenderPath.fromPointer(this.riveFactory, this._renderPath) {
    _finalizer.attach(this, _renderPath, detach: this);
  }

  PathFillType _fillType = PathFillType.nonZero;
  @override
  PathFillType get fillType => _fillType;

  @override
  set fillType(PathFillType type) {
    if (type == _fillType) {
      return;
    }
    _fillType = type;
    RiveWasm.renderPathSetFillRule.callAsFunction(
      null,
      _renderPath,
      _fillType.index.toJS,
    );
  }

  @override
  void addPath(covariant WebRenderPath path, Mat2D transform) =>
      RiveWasm.addPath.callAsFunctionEx(
        null,
        pointer,
        path.pointer,
        transform[0].toJS,
        transform[1].toJS,
        transform[2].toJS,
        transform[3].toJS,
        transform[4].toJS,
        transform[5].toJS,
      );

  @override
  void addPathBackwards(covariant WebRenderPath path, Mat2D transform) =>
      RiveWasm.addPathBackwards.callAsFunctionEx(
        null,
        riveFactory.pointer,
        pointer,
        path.pointer,
        transform[0].toJS,
        transform[1].toJS,
        transform[2].toJS,
        transform[3].toJS,
        transform[4].toJS,
        transform[5].toJS,
      );

  @override
  void dispose() {
    if (_renderPath == null) {
      return;
    }
    _finalizer.detach(this);
    RiveWasm.deleteRenderPath.callAsFunction(null, _renderPath);
    _renderPath = null;
  }

  @override
  ByteData get scratchBufferByteData => RiveWasm.scratchBufferByteData;

  @override
  void appendCommands(int commandCount) => RiveWasm.appendCommands
      .callAsFunction(null, RiveWasm.scratchBufferPtr, commandCount.toJS);

  @override
  void updateRenderPath() {
    if (_renderPath == null) {
      _renderPath = RiveWasm.makeRenderPath.callAsFunction(
        null,
        riveFactory.pointer,
      );
      RiveWasm.renderPathSetFillRule.callAsFunction(
        null,
        _renderPath,
        _fillType.index.toJS,
      );
      _finalizer.attach(this, _renderPath, detach: this);
    } else {
      RiveWasm.appendRenderPath.callAsFunction(null, _renderPath);
    }
  }

  @override
  void reset() {
    resetBuffer();
    RiveWasm.rewindRenderPath.callAsFunction(null, _renderPath);
  }

  @override
  bool hitTest(Vec2D point, {Mat2D? transform, double hitRadius = 3}) {
    var actualTransform = transform ?? Mat2D.identity;
    update();
    return _wasmBool(
      RiveWasm.renderPathHitTest.callAsFunctionEx(
        null,
        riveFactory.pointer,
        pointer,
        point.x.toJS,
        point.y.toJS,
        hitRadius.toJS,
        actualTransform[0].toJS,
        actualTransform[1].toJS,
        actualTransform[2].toJS,
        actualTransform[3].toJS,
        actualTransform[4].toJS,
        actualTransform[5].toJS,
      ) as js.JSNumber,
    );
  }

  @override
  Segment2D? get isColinear {
    if (_wasmBool(
      RiveWasm.renderPathColinearCheck.callAsFunction(
        null,
        riveFactory.pointer,
        pointer,
        RiveWasm.scratchBufferPtr,
      ) as js.JSNumber,
    )) {
      final floats = RiveWasm.scratchBufferFloat;
      return Segment2D(
        Vec2D.fromValues(floats[0], floats[1]),
        Vec2D.fromValues(floats[2], floats[3]),
      );
    }
    return null;
  }

  @override
  bool get isClosed => _wasmBool(
        RiveWasm.renderPathIsClosed.callAsFunction(
          null,
          riveFactory.pointer,
          pointer,
        ),
      );

  @override
  bool get hasBounds => _wasmBool(
        RiveWasm.renderPathHasBounds.callAsFunction(
          null,
          riveFactory.pointer,
          pointer,
        ),
      );

  @override
  AABB computePreciseBounds(Mat2D transform) {
    RiveWasm.renderPathPreciseBounds.callAsFunctionEx(
      null,
      riveFactory.pointer,
      pointer,
      transform[0].toJS,
      transform[1].toJS,
      transform[2].toJS,
      transform[3].toJS,
      transform[4].toJS,
      transform[5].toJS,
      RiveWasm.scratchBufferPtr,
    );
    final floats = RiveWasm.scratchBufferFloat;
    return AABB.fromLTRB(floats[0], floats[1], floats[2], floats[3]);
  }

  @override
  double computePreciseLength(Mat2D transform) {
    return (RiveWasm.renderPathPreciseLength.callAsFunctionEx(
      null,
      riveFactory.pointer,
      pointer,
      transform[0].toJS,
      transform[1].toJS,
      transform[2].toJS,
      transform[3].toJS,
      transform[4].toJS,
      transform[5].toJS,
    ) as js.JSNumber)
        .toDartDouble;
  }

  @override
  AABB computeBounds(Mat2D transform) {
    RiveWasm.renderPathBounds.callAsFunctionEx(
      null,
      riveFactory.pointer,
      pointer,
      transform[0].toJS,
      transform[1].toJS,
      transform[2].toJS,
      transform[3].toJS,
      transform[4].toJS,
      transform[5].toJS,
      RiveWasm.scratchBufferPtr,
    );
    final floats = RiveWasm.scratchBufferFloat;
    return AABB.fromLTRB(floats[0], floats[1], floats[2], floats[3]);
  }

  static int _verbBufferSize = 0;
  static late int _verbBuffer;
  static late int _pointBuffer;

  static void _resizeVerbBuffer(int size) {
    if (_verbBufferSize != 0) {
      RiveWasm.deleteBuffer.callAsFunction(null, _verbBuffer.toJS);
      RiveWasm.deleteBuffer.callAsFunction(null, _pointBuffer.toJS);
    }
    _verbBufferSize = size;
    _verbBuffer = (RiveWasm.allocateBuffer
            .callAsFunction(null, _verbBufferSize.toJS) as js.JSNumber)
        .toDartInt;
    _pointBuffer = (RiveWasm.allocateBuffer.callAsFunction(
      null,
      (_verbBufferSize * 4 * 3 * 2).toJS,
    ) as js.JSNumber)
        .toDartInt;
  }

  Iterable<PathCommand> _commands() sync* {
    if (_verbBufferSize == 0) {
      _resizeVerbBuffer(10);
    }
    int count = (RiveWasm.renderPathCopyBuffers.callAsFunctionEx(
      null,
      riveFactory.pointer,
      pointer,
      _verbBuffer.toJS,
      _verbBufferSize.toJS,
      _pointBuffer.toJS,
      (_verbBufferSize * 3).toJS,
    ) as js.JSNumber)
        .toDartInt;
    // Negative means the buffers were too small, grow them.
    if (count < 0) {
      _resizeVerbBuffer(-count);
      count = (RiveWasm.renderPathCopyBuffers.callAsFunctionEx(
        null,
        riveFactory.pointer,
        pointer,
        _verbBuffer.toJS,
        _verbBufferSize.toJS,
        _pointBuffer.toJS,
        (_verbBufferSize * 3).toJS,
      ) as js.JSNumber)
          .toDartInt;
      assert(count >= 0);
    }

    final verbBuffer = RiveWasm.heap(_verbBuffer, _verbBufferSize);

    final floats = RiveWasm.heapViewF32(_pointBuffer, _verbBufferSize * 3 * 2);

    int pointIndex = 0;
    for (int i = 0; i < count; i++) {
      int verb = verbBuffer[i];
      switch (verb) {
        case 0:
          Vec2D to = Vec2D.fromValues(
            floats[pointIndex],
            floats[pointIndex + 1],
          );
          pointIndex += 2;
          yield PathCommand.move(to);
          break;
        case 1:
          Vec2D from = Vec2D.fromValues(
            floats[pointIndex - 2],
            floats[pointIndex - 1],
          );
          Vec2D to = Vec2D.fromValues(
            floats[pointIndex],
            floats[pointIndex + 1],
          );
          pointIndex += 2;
          yield PathCommand.line(from, to);
          break;
        case 2:
          Vec2D from = Vec2D.fromValues(
            floats[pointIndex - 2],
            floats[pointIndex - 1],
          );
          Vec2D control = Vec2D.fromValues(
            floats[pointIndex],
            floats[pointIndex + 1],
          );
          Vec2D to = Vec2D.fromValues(
            floats[pointIndex + 2],
            floats[pointIndex + 3],
          );
          pointIndex += 4;
          yield PathCommand.quad(from, control, to);
          break;
        case 4:
          Vec2D from = Vec2D.fromValues(
            floats[pointIndex - 2],
            floats[pointIndex - 1],
          );
          Vec2D controlOut = Vec2D.fromValues(
            floats[pointIndex],
            floats[pointIndex + 1],
          );
          Vec2D controlIn = Vec2D.fromValues(
            floats[pointIndex + 2],
            floats[pointIndex + 3],
          );
          Vec2D to = Vec2D.fromValues(
            floats[pointIndex + 4],
            floats[pointIndex + 5],
          );
          pointIndex += 6;
          yield PathCommand.cubic(from, controlOut, controlIn, to);
          break;
        case 5:
          yield PathCommand.close();
        default:
          throw UnimplementedError('Unkonwn path command $verb');
      }
    }
  }

  @override
  Iterable<PathCommand> get commands => _commands();

  @override
  bool isClockwise(Mat2D transform) => _wasmBool(
        RiveWasm.renderPathIsClockwise.callAsFunction(
          null,
          riveFactory.pointer,
          pointer,
          transform.determinant.toJS,
        ),
      );

  @override
  void addRawPath(
    covariant RawPathWasm rawPath, {
    Mat2D? transform,
    bool forceClockwise = false,
  }) {
    if (transform == null) {
      RiveWasm.addRawPath.callAsFunction(null, pointer, rawPath.pointer);
      return;
    }
    if (!forceClockwise) {
      RiveWasm.addRawPathWithTransform.callAsFunctionEx(
        null,
        pointer,
        rawPath.pointer,
        transform[0].toJS,
        transform[1].toJS,
        transform[2].toJS,
        transform[3].toJS,
        transform[4].toJS,
        transform[5].toJS,
      );
    } else {
      RiveWasm.addRawPathWithTransformClockwise.callAsFunctionEx(
        null,
        pointer,
        rawPath.pointer,
        transform[0].toJS,
        transform[1].toJS,
        transform[2].toJS,
        transform[3].toJS,
        transform[4].toJS,
        transform[5].toJS,
      );
    }
  }
}

class WebRenderPaint extends BufferedRenderPaint {
  final WebFactory riveFactory;
  js.JSAny? _renderPaint;
  static final Finalizer<js.JSAny?> _finalizer = Finalizer(
    (nativePtr) => RiveWasm.deleteRenderPaint.callAsFunction(null, nativePtr),
  );

  js.JSAny? get pointer {
    update();
    return _renderPaint;
  }

  WebRenderPaint(this.riveFactory)
      : _renderPaint = RiveWasm.makeRenderPaint.callAsFunction(
          null,
          riveFactory.pointer,
        ) {
    _finalizer.attach(this, _renderPaint, detach: this);
  }

  @override
  void dispose() {
    if (_renderPaint == null) {
      return;
    }
    RiveWasm.deleteRenderPaint.callAsFunction(null, _renderPaint);
    _renderPaint = null;
    _finalizer.detach(this);
  }

  @override
  ByteData get scratchBufferByteData => RiveWasm.scratchBufferByteData;

  @override
  void updatePaint(int dirty, int wroteStops) =>
      RiveWasm.updatePaint.callAsFunctionEx(
        null,
        riveFactory.pointer,
        _renderPaint,
        dirty.toJS,
        RiveWasm.scratchBufferPtr,
        wroteStops.toJS,
      );
}

class WebRiveRenderer extends Renderer {
  @override
  final Factory riveFactory;

  js.JSAny? jsRendererPtr;
  WebRiveRenderer(this.jsRendererPtr, this.riveFactory);

  @override
  void clipPath(covariant WebRenderPath path) =>
      RiveWasm.clipPath.callAsFunction(null, jsRendererPtr, path.pointer);

  @override
  void drawImage(
    covariant WebRenderImage image,
    ui.BlendMode blendMode,
    double opacity,
  ) =>
      RiveWasm.drawImage.callAsFunction(
        null,
        jsRendererPtr,
        image._pointer,
        blendMode.index.toJS,
        opacity.toJS,
      );

  @override
  void drawImageMesh(
    covariant WebRenderImage image,
    covariant WebVertexRenderBuffer vertices,
    covariant WebVertexRenderBuffer uvs,
    covariant WebIndexRenderBuffer indices,
    ui.BlendMode blendMode,
    double opacity,
  ) {
    assert(vertices.elementCount == uvs.elementCount);
    RiveWasm.drawImageMesh.callAsFunctionEx(
      null,
      jsRendererPtr,
      image._pointer,
      vertices.pointer,
      uvs.pointer,
      indices.pointer,
      vertices.elementCount.toJS,
      indices.elementCount.toJS,
      blendMode.index.toJS,
      opacity.toJS,
    );
  }

  @override
  void drawPath(covariant WebRenderPath path, covariant WebRenderPaint paint) =>
      RiveWasm.drawPath.callAsFunction(
        null,
        jsRendererPtr,
        path.pointer,
        paint.pointer,
      );

  @override
  void drawText(
    covariant WebRenderText text, [
    covariant WebRenderPaint? paint,
  ]) =>
      RiveWasm.rawTextRender.callAsFunction(
        null,
        text.pointer,
        jsRendererPtr,
        paint?.pointer ?? 0.toJS,
      );

  @override
  void restore() =>
      RiveWasm.restoreRenderer.callAsFunction(null, jsRendererPtr);

  @override
  void save() => RiveWasm.saveRenderer.callAsFunction(null, jsRendererPtr);

  @override
  void transform(Mat2D matrix) => RiveWasm.transformRenderer.callAsFunctionEx(
        null,
        jsRendererPtr,
        matrix[0].toJS,
        matrix[1].toJS,
        matrix[2].toJS,
        matrix[3].toJS,
        matrix[4].toJS,
        matrix[5].toJS,
      );

  @override
  void modulateOpacity(double opacity) =>
      RiveWasm.modulateOpacityRenderer.callAsFunction(
        null,
        jsRendererPtr,
        opacity.toJS,
      );
}

bool _wasmBool(js.JSAny? value) => (value as js.JSNumber).toDartInt == 1;
js.JSNumber _boolWasm(bool value) => (value ? 1 : 0).toJS;

class WebDashPath extends DashPathEffect {
  static final _finalizer = Finalizer<js.JSAny>(
    (pointer) => RiveWasm.deleteDashPathEffect.callAsFunction(null, pointer),
  );

  js.JSAny _pointer;

  WebDashPath()
      : _pointer = RiveWasm.makeDashPathEffect.callAsFunction() as js.JSAny {
    _finalizer.attach(this, _pointer, detach: this);
  }

  @override
  void dispose() {
    _finalizer.detach(this);
    RiveWasm.deleteDashPathEffect.callAsFunction(null, _pointer);
    _pointer = 0.toJS;
  }

  @override
  double get pathLength =>
      (RiveWasm.dashPathEffectGetPathLength.callAsFunction(null, _pointer)
              as js.JSNumber)
          .toDartDouble;

  @override
  double get offset =>
      (RiveWasm.dashPathEffectGetOffset.callAsFunction(null, _pointer)
              as js.JSNumber)
          .toDartDouble;
  @override
  set offset(double value) => RiveWasm.dashPathEffectSetOffset.callAsFunction(
        null,
        _pointer,
        value.toJS,
      );

  @override
  bool get offsetIsPercentage => _wasmBool(
        RiveWasm.dashPathEffectGetOffsetIsPercentage
            .callAsFunction(null, _pointer),
      );
  @override
  set offsetIsPercentage(bool value) =>
      RiveWasm.dashPathEffectSetOffsetIsPercentage
          .callAsFunction(null, _pointer, _boolWasm(value));

  @override
  void clearDashArray() =>
      RiveWasm.dashPathClearDashes.callAsFunction(null, _pointer);

  @override
  void addToDashArray(double value, bool percentage) => RiveWasm.dashPathAddDash
      .callAsFunction(null, _pointer, value.toJS, _boolWasm(percentage));

  @override
  void invalidate() =>
      RiveWasm.dashPathInvalidate.callAsFunction(null, _pointer);

  @override
  RenderPath effectPath(covariant WebRenderPath path) =>
      WebRenderPath.fromPointer(
        path.riveFactory,
        RiveWasm.dashPathEffectPath.callAsFunction(
          null,
          path.riveFactory.pointer,
          _pointer,
          path.pointer,
        ),
      );
}

class WebTrimPath extends TrimPathEffect {
  static final _finalizer = Finalizer<js.JSAny>(
    (pointer) => RiveWasm.deleteTrimPathEffect.callAsFunction(null, pointer),
  );

  js.JSAny _pointer;

  WebTrimPath()
      : _pointer = RiveWasm.makeTrimPathEffect.callAsFunction() as js.JSAny {
    _finalizer.attach(this, _pointer, detach: this);
  }

  @override
  double get end =>
      (RiveWasm.trimPathEffectGetEnd.callAsFunction(null, _pointer)
              as js.JSNumber)
          .toDartDouble;

  @override
  set end(double value) =>
      RiveWasm.trimPathEffectSetEnd.callAsFunction(null, _pointer, value.toJS);

  @override
  TrimPathMode get mode =>
      TrimPathMode.values[(RiveWasm.trimPathEffectGetMode.callAsFunction(
        null,
        _pointer,
      ) as js.JSNumber)
          .toDartInt];

  @override
  set mode(TrimPathMode value) => RiveWasm.trimPathEffectSetMode.callAsFunction(
        null,
        _pointer,
        value.index.toJS,
      );

  @override
  double get offset =>
      (RiveWasm.trimPathEffectGetOffset.callAsFunction(null, _pointer)
              as js.JSNumber)
          .toDartDouble;

  @override
  set offset(double value) => RiveWasm.trimPathEffectSetOffset.callAsFunction(
        null,
        _pointer,
        value.toJS,
      );

  @override
  double get start =>
      (RiveWasm.trimPathEffectGetStart.callAsFunction(null, _pointer)
              as js.JSNumber)
          .toDartDouble;

  @override
  set start(double value) => RiveWasm.trimPathEffectSetStart.callAsFunction(
        null,
        _pointer,
        value.toJS,
      );

  @override
  void dispose() {
    _finalizer.detach(this);
    RiveWasm.deleteTrimPathEffect.callAsFunction(null, _pointer);
    _pointer = 0.toJS;
  }

  @override
  RenderPath effectPath(covariant WebRenderPath path, int shapePaintType) =>
      WebRenderPath.fromPointer(
        path.riveFactory,
        RiveWasm.trimPathEffectPath.callAsFunction(
          null,
          path.riveFactory.pointer,
          _pointer,
          path.pointer,
          shapePaintType.toJS,
        ),
      );

  @override
  void invalidate() =>
      RiveWasm.trimPathEffectInvalidate.callAsFunction(null, _pointer);
}

TrimPathEffect makeTrimPathEffect() => WebTrimPath();
DashPathEffect makeDashPathEffect() => WebDashPath();

class WebPathMeasure extends PathMeasure {
  static final _finalizer = Finalizer<js.JSAny>(
    (pointer) => RiveWasm.deletePathMeasure.callAsFunction(null, pointer),
  );

  js.JSAny _pointer;

  WebPathMeasure(WebRenderPath path, double tolerance)
      : _pointer = RiveWasm.makePathMeasure.callAsFunction(
          null,
          path.riveFactory.pointer,
          path.pointer,
          tolerance.toJS,
        ) as js.JSAny {
    _finalizer.attach(this, _pointer, detach: this);
  }

  @override
  void dispose() {
    _finalizer.detach(this);
    RiveWasm.deletePathMeasure.callAsFunction(null, _pointer);
    _pointer = 0.toJS;
  }

  @override
  (Vec2D, Vec2D) atDistance(double distance) {
    RiveWasm.pathMeasureAtDistance.callAsFunction(
      null,
      _pointer,
      distance.toJS,
      RiveWasm.scratchBufferPtr,
    );

    final floats = RiveWasm.scratchBufferFloat;
    final pos = Vec2D.fromValues(floats[0], floats[1]);
    final tan = Vec2D.fromValues(floats[2], floats[3]);
    return (pos, tan);
  }

  @override
  (Vec2D, Vec2D, double) atPercentage(double percentage) {
    RiveWasm.pathMeasureAtPercentage.callAsFunction(
      null,
      _pointer,
      percentage.toJS,
      RiveWasm.scratchBufferPtr,
    );
    final floats = RiveWasm.scratchBufferFloat;
    final pos = Vec2D.fromValues(floats[0], floats[1]);
    final tan = Vec2D.fromValues(floats[2], floats[3]);
    final distance = floats[4];
    return (pos, tan, distance);
  }

  @override
  double get length =>
      (RiveWasm.pathMeasureLength.callAsFunction(null, _pointer) as js.JSNumber)
          .toDartDouble;
}

PathMeasure makePathMeasure(RenderPath renderPath, double tolerance) =>
    WebPathMeasure(renderPath as WebRenderPath, tolerance);

class WebRawTextInput extends RawTextInput {
  static final Finalizer<js.JSAny?> _finalizer = Finalizer(
    (nativePtr) => RiveWasm.deleteRawTextInput.callAsFunction(null, nativePtr),
  );

  js.JSAny? _rawText;
  js.JSAny? get pointer => _rawText;

  final WebFactory riveFactory;

  WebRawTextInput(this.riveFactory)
      : _rawText = RiveWasm.makeRawTextInput.callAsFunction(null) as js.JSAny {
    _finalizer.attach(this, _rawText, detach: this);
  }

  @override
  void dispose() {
    if (_rawText == null) {
      return;
    }
    RiveWasm.deleteRawTextInput.callAsFunction(null, _rawText);
    _rawText = null;
    _finalizer.detach(this);
  }

  FontWasm? _font;

  @override
  FontWasm? get font => _font;

  @override
  set font(covariant FontWasm? value) {
    if (_font == value) {
      return;
    }
    _font = value;
    RiveWasm.rawTextInputSetFont.callAsFunction(
      null,
      _rawText,
      value?.fontPtr.toJS,
    );
  }

  @override
  double get fontSize =>
      (RiveWasm.rawTextInputGetFontSize.callAsFunction(null, _rawText)
              as js.JSNumber)
          .toDartDouble;

  @override
  set fontSize(double value) => RiveWasm.rawTextInputSetFontSize.callAsFunction(
        null,
        _rawText,
        value.toJS,
      );

  @override
  double get maxWidth =>
      (RiveWasm.rawTextInputGetMaxWidth.callAsFunction(null, _rawText)
              as js.JSNumber)
          .toDartDouble;

  @override
  set maxWidth(double value) => RiveWasm.rawTextInputSetMaxWidth.callAsFunction(
        null,
        _rawText,
        value.toJS,
      );

  @override
  double get maxHeight =>
      (RiveWasm.rawTextInputGetMaxHeight.callAsFunction(null, _rawText)
              as js.JSNumber)
          .toDartDouble;

  @override
  set maxHeight(double value) => RiveWasm.rawTextInputSetMaxHeight
      .callAsFunction(null, _rawText, value.toJS);

  @override
  double get paragraphSpacing =>
      (RiveWasm.rawTextInputGetParagraphSpacing.callAsFunction(null, _rawText)
              as js.JSNumber)
          .toDartDouble;

  @override
  set paragraphSpacing(double value) => RiveWasm.rawTextInputSetParagraphSpacing
      .callAsFunction(null, _rawText, value.toJS);

  @override
  TextSizing get sizing => TextSizing.values.elementAtOrFirst(
        (RiveWasm.rawTextInputGetSizing.callAsFunction(null, _rawText)
                as js.JSNumber)
            .toDartInt,
      );

  @override
  set sizing(TextSizing value) => RiveWasm.rawTextInputSetSizing.callAsFunction(
        null,
        _rawText,
        value.index.toJS,
      );

  @override
  TextOverflow get overflow => TextOverflow.values.elementAtOrFirst(
        (RiveWasm.rawTextInputGetOverflow.callAsFunction(null, _rawText)
                as js.JSNumber)
            .toDartInt,
      );

  @override
  set overflow(TextOverflow value) => RiveWasm.rawTextInputSetOverflow
      .callAsFunction(null, _rawText, value.index.toJS);

  @override
  double get selectionCornerRadius =>
      (RiveWasm.rawTextInputGetSelectionCornerRadius.callAsFunction(
        null,
        _rawText,
      ) as js.JSNumber)
          .toDartDouble;

  @override
  set selectionCornerRadius(double value) =>
      RiveWasm.rawTextInputSetSelectionCornerRadius
          .callAsFunction(null, _rawText, value.toJS);

  @override
  bool get separateSelectionText => _wasmBool(
        RiveWasm.rawTextInputGetSeparateSelectionText.callAsFunction(
          null,
          _rawText,
        ),
      );

  @override
  set separateSelectionText(bool value) =>
      RiveWasm.rawTextInputSetSeparateSelectionText
          .callAsFunction(null, _rawText, _boolWasm(value));

  @override
  String get text => RiveWasm.toDartString(
        ((RiveWasm.rawTextInputGetText.callAsFunction(null, _rawText)
                as js.JSNumber)
            .toDartInt),
        deleteNative: true,
      );

  @override
  set text(String value) {
    final nativeString = value.toWasmUtf8();
    RiveWasm.rawTextInputSetText.callAsFunction(
      null,
      _rawText,
      nativeString.pointer,
    );
    nativeString.dispose();
  }

  @override
  void setTextPreserveCursor(String value) {
    final nativeString = value.toWasmUtf8();
    RiveWasm.rawTextInputSetTextPreserveCursor.callAsFunction(
      null,
      _rawText,
      nativeString.pointer,
    );
    nativeString.dispose();
  }

  @override
  int get length => (RiveWasm.rawTextInputLength.callAsFunction(null, _rawText)
          as js.JSNumber)
      .toDartInt;

  @override
  AABB get bounds {
    RiveWasm.rawTextInputBounds.callAsFunction(
      null,
      _rawText,
      RiveWasm.scratchBufferPtr,
    );

    final floats = RiveWasm.scratchBufferFloat;

    return AABB.fromValues(floats[0], floats[1], floats[2], floats[3]);
  }

  @override
  int update() => (RiveWasm.rawTextInputUpdate.callAsFunction(
        null,
        _rawText,
        riveFactory.pointer,
      ) as js.JSNumber)
          .toDartInt;

  @override
  void backspace(int direction) =>
      RiveWasm.rawTextBackspace.callAsFunction(null, _rawText, direction.toJS);

  @override
  void cursorDown({bool select = false}) => RiveWasm.rawTextCursorDown
      .callAsFunction(null, _rawText, _boolWasm(select));

  @override
  void cursorLeft({
    CursorBoundary boundary = CursorBoundary.character,
    bool select = false,
  }) =>
      RiveWasm.rawTextCursorLeft.callAsFunction(
        null,
        _rawText,
        boundary.index.toJS,
        _boolWasm(select),
      );

  @override
  void cursorRight({
    CursorBoundary boundary = CursorBoundary.character,
    bool select = false,
  }) =>
      RiveWasm.rawTextCursorRight.callAsFunction(
        null,
        _rawText,
        boundary.index.toJS,
        _boolWasm(select),
      );

  @override
  void cursorUp({bool select = false}) => RiveWasm.rawTextCursorUp
      .callAsFunction(null, _rawText, _boolWasm(select));

  @override
  void erase() => RiveWasm.rawTextErase.callAsFunction(null, _rawText);

  @override
  void insertCodePoint(int codePoint) => RiveWasm.rawTextInsertCodePoint
      .callAsFunction(null, _rawText, codePoint.toJS);

  @override
  void insertText(String value) {
    final nativeString = value.toWasmUtf8();
    RiveWasm.rawTextInsertText.callAsFunction(
      null,
      _rawText,
      nativeString.pointer,
    );
    nativeString.dispose();
  }

  @override
  void moveCursorTo(Vec2D translation, {bool select = false}) =>
      RiveWasm.rawTextMoveCursorTo.callAsFunction(
        null,
        _rawText,
        translation.x.toJS,
        translation.y.toJS,
        _boolWasm(select),
      );

  @override
  void redo() => RiveWasm.rawTextRedo.callAsFunction(null, _rawText);

  @override
  void selectWord() =>
      RiveWasm.rawTextSelectWord.callAsFunction(null, _rawText);

  @override
  bool get hasSelection =>
      _wasmBool(RiveWasm.rawTextHasSelection.callAsFunction(null, _rawText));

  @override
  void clearSelection() =>
      RiveWasm.rawTextClearSelection.callAsFunction(null, _rawText);

  @override
  void undo() => RiveWasm.rawTextUndo.callAsFunction(null, _rawText);

  @override
  RenderPath get clipPath => WebRenderPath.fromPointer(
        riveFactory,
        RiveWasm.rawTextClipPath.callAsFunction(null, _rawText),
      );

  @override
  RenderPath get cursorPath => WebRenderPath.fromPointer(
        riveFactory,
        RiveWasm.rawTextCursorPath.callAsFunction(
          null,
          _rawText,
          riveFactory.pointer,
        ),
      );

  @override
  RenderPath get selectedTextPath => WebRenderPath.fromPointer(
        riveFactory,
        RiveWasm.rawTextSelectedTextPath.callAsFunction(
          null,
          _rawText,
          riveFactory.pointer,
        ),
      );

  @override
  RenderPath get selectionPath => WebRenderPath.fromPointer(
        riveFactory,
        RiveWasm.rawTextSelectionPath.callAsFunction(
          null,
          _rawText,
          riveFactory.pointer,
        ),
      );

  @override
  RenderPath get textPath => WebRenderPath.fromPointer(
        riveFactory,
        RiveWasm.rawTextTextPath.callAsFunction(
          null,
          _rawText,
          riveFactory.pointer,
        ),
      );

  @override
  CursorVisualPosition get cursorPosition {
    RiveWasm.rawTextInputCursorPosition.callAsFunction(
      null,
      _rawText,
      RiveWasm.scratchBufferPtr,
    );

    final floats = RiveWasm.scratchBufferFloat;

    return CursorVisualPosition(
      x: floats[0],
      top: floats[1],
      bottom: floats[2],
    );
  }

  @override
  AABB measure(ui.Size max) {
    RiveWasm.rawTextInputMeasure.callAsFunction(
      null,
      _rawText,
      max.width.toJS,
      max.height.toJS,
      RiveWasm.scratchBufferPtr,
    );

    var floats = Float32List.view(
      RiveWasm.scratchBuffer.buffer,
      RiveWasm.scratchBuffer.offsetInBytes,
      4,
    );

    return AABB.fromValues(floats[0], floats[1], floats[2], floats[3]);
  }
}

RawTextInput makeRawTextInput(Factory riveFactory) =>
    WebRawTextInput(riveFactory as WebFactory);
