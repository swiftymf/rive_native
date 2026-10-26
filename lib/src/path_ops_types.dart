import 'dart:typed_data';

import 'package:rive_native/math.dart';
import 'package:rive_native/rive_text.dart';
import 'package:rive_native/src/rive_renderer.dart' show PathFillType;

/// Boolean path operations. Values match rive::PathOp in
/// packages/pathops/include/rive/pathops/pathops.hpp.
enum PathBooleanOp {
  /// Subtract the second path from the first.
  difference,

  /// Keep only the area covered by both paths.
  intersect,

  /// Union of both paths.
  join,

  /// Keep the area covered by exactly one path (xor).
  exclusion,

  /// Subtract the first path from the second.
  reverseDifference,
}

/// Result of a boolean path operation: flattened, overlap-free geometry and
/// the fill rule Skia reports for it. The path renders identically under any
/// fill rule since all overlaps have been resolved.
class PathOpsResult {
  final RawPath path;
  final PathFillType fillRule;

  PathOpsResult(this.path, this.fillRule);

  void dispose() => path.dispose();
}

/// A [RawPath] backed by Dart-side typed data, platform-neutral (used by
/// both the FFI and wasm pathops bindings). Verb byte values match
/// rive::PathVerb.
class PathOpsRawPath extends RawPath {
  final Float32List points;
  final Uint8List verbs;

  PathOpsRawPath(this.points, this.verbs);

  @override
  Iterator<RawPathCommand> get iterator => _PathOpsRawPathIterator(this);

  @override
  void dispose() {
    // Dart-managed data; nothing native to free.
  }
}

class _PathOpsRawPathCommand extends RawPathCommand {
  final Float32List _points;
  final int _pointOffset;

  _PathOpsRawPathCommand(super.verb, this._points, this._pointOffset);

  @override
  Vec2D point(int index) {
    final i = (_pointOffset + index) * 2;
    return Vec2D.fromValues(_points[i], _points[i + 1]);
  }
}

RawPathVerb _pathOpsVerbFromNative(int nativeVerb) {
  switch (nativeVerb) {
    case 0:
      return RawPathVerb.move;
    case 1:
      return RawPathVerb.line;
    case 2:
      return RawPathVerb.quad;
    case 4:
      return RawPathVerb.cubic;
    case 5:
      return RawPathVerb.close;
    default:
      throw UnsupportedError('Unexpected path verb $nativeVerb');
  }
}

int _pathOpsPtsAdvanceAfterVerb(RawPathVerb verb) {
  switch (verb) {
    case RawPathVerb.move:
      return 1;
    case RawPathVerb.line:
      return 1;
    case RawPathVerb.quad:
      return 2;
    case RawPathVerb.cubic:
      return 3;
    case RawPathVerb.close:
      return 0;
  }
}

int _pathOpsPtsBacksetForVerb(RawPathVerb verb) {
  switch (verb) {
    case RawPathVerb.move:
      return 0;
    case RawPathVerb.line:
    case RawPathVerb.quad:
    case RawPathVerb.cubic:
    case RawPathVerb.close:
      return -1;
  }
}

class _PathOpsRawPathIterator implements Iterator<RawPathCommand> {
  final PathOpsRawPath _path;
  int _verbIndex = -1;
  int _ptIndex = -1;
  RawPathVerb _verb = RawPathVerb.move;

  _PathOpsRawPathIterator(this._path);

  @override
  RawPathCommand get current => _PathOpsRawPathCommand(
        _verb,
        _path.points,
        _ptIndex + _pathOpsPtsBacksetForVerb(_verb),
      );

  @override
  bool moveNext() {
    if (++_verbIndex < _path.verbs.length) {
      _ptIndex += _pathOpsPtsAdvanceAfterVerb(_verb);
      _verb = _pathOpsVerbFromNative(_path.verbs[_verbIndex]);
      return true;
    }
    return false;
  }
}

/// Accumulates path commands into the flat verb/point buffers that cross the
/// native boundary. Verb byte values match rive::PathVerb (move=0, line=1,
/// quad=2, cubic=4, close=5); points are consumed per-verb on the native
/// side (move/line=1 point, quad=2, cubic=3, close=0).
class PathOpsPathBuffers {
  final List<double> _points = [];
  final List<int> _verbs = [];

  // The typed views are rebuilt at most once per mutation: hot paths
  // (containment tests on every mouse move, FFI marshalling per boolean op)
  // read these getters repeatedly while the buffers are logically immutable.
  Float32List? _pointsView;
  Uint8List? _verbsView;

  void _invalidate() {
    _pointsView = null;
    _verbsView = null;
  }

  void moveTo(double x, double y) {
    _invalidate();
    _verbs.add(0);
    _points
      ..add(x)
      ..add(y);
  }

  void lineTo(double x, double y) {
    _invalidate();
    _verbs.add(1);
    _points
      ..add(x)
      ..add(y);
  }

  void quadTo(double cx, double cy, double x, double y) {
    _invalidate();
    _verbs.add(2);
    _points
      ..add(cx)
      ..add(cy)
      ..add(x)
      ..add(y);
  }

  void cubicTo(
    double ox,
    double oy,
    double ix,
    double iy,
    double x,
    double y,
  ) {
    _invalidate();
    _verbs.add(4);
    _points
      ..add(ox)
      ..add(oy)
      ..add(ix)
      ..add(iy)
      ..add(x)
      ..add(y);
  }

  void close() {
    _invalidate();
    _verbs.add(5);
  }

  bool get isEmpty => _verbs.isEmpty;

  /// Whether [points] carries exactly the floats [verbs] consume. Always
  /// true for buffers built through the verb methods (they append in
  /// lockstep); checked at the native boundary anyway so a future
  /// construction path can't feed the C++ side a short buffer (it reads
  /// points by verb with no length information).
  bool get isConsistent => points.length == pointsRequiredForVerbs(verbs);

  Float32List get points => _pointsView ??= Float32List.fromList(_points);
  Uint8List get verbs => _verbsView ??= Uint8List.fromList(_verbs);
}

/// Floats consumed by [verbs] (move/line = 1 point, quad = 2, cubic = 3,
/// close = 0; two floats per point). Unknown verb bytes report -1 so a
/// caller comparing against an actual points length fails closed.
int pointsRequiredForVerbs(Uint8List verbs) {
  var floats = 0;
  for (final verb in verbs) {
    switch (verb) {
      case 0: // move
      case 1: // line
        floats += 2;
        break;
      case 2: // quad
        floats += 4;
        break;
      case 4: // cubic
        floats += 6;
        break;
      case 5: // close
        break;
      default:
        return -1;
    }
  }
  return floats;
}
