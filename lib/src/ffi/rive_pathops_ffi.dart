import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rive_native/rive_pathops.dart';
import 'package:rive_native/src/ffi/dynamic_library_helper.dart';
import 'package:rive_native/src/rive_renderer.dart' show PathFillType;

final DynamicLibrary _nativeLib = DynamicLibraryHelper.nativeLib;

/// Whether the loaded native library carries the pathops symbols. False in
/// flutter_runtime builds, where pathops is excluded (editor-only); callers
/// (and tests) must check before using combineRawPaths/simplifyRawPath --
/// the lazily-initialized lookups below throw on first use otherwise.
final bool pathOpsAvailable = () {
  try {
    _nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deletePathOpsResult');
    return true;
  } on ArgumentError {
    return false;
  }
}();

final class _PathOpsResultStruct extends Struct {
  external Pointer<Void> rawPath;
  external Pointer<Float> points;
  external Pointer<Uint8> verbs;

  @Uint32()
  external int verbCount;

  @Uint32()
  external int pointCount;

  @Uint32()
  external int fillRule;

  @Uint32()
  external int success;
}

final _PathOpsResultStruct Function(
  int pathOp,
  Pointer<Float> pointsA,
  Pointer<Uint8> verbsA,
  int verbCountA,
  int fillRuleA,
  Pointer<Float> pointsB,
  Pointer<Uint8> verbsB,
  int verbCountB,
  int fillRuleB,
) _combinePaths = _nativeLib
    .lookup<
        NativeFunction<
            _PathOpsResultStruct Function(
              Uint32,
              Pointer<Float>,
              Pointer<Uint8>,
              Uint32,
              Uint32,
              Pointer<Float>,
              Pointer<Uint8>,
              Uint32,
              Uint32,
            )>>('combinePaths')
    .asFunction();

final _PathOpsResultStruct Function(
  Pointer<Float> points,
  Pointer<Uint8> verbs,
  int verbCount,
  int fillRule,
) _simplifyPath = _nativeLib
    .lookup<
        NativeFunction<
            _PathOpsResultStruct Function(
              Pointer<Float>,
              Pointer<Uint8>,
              Uint32,
              Uint32,
            )>>('simplifyPath')
    .asFunction();

final void Function(Pointer<Void> rawPath) _deletePathOpsResult = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('deletePathOpsResult')
    .asFunction();

class _NativeBuffers {
  final Pointer<Float> points;
  final Pointer<Uint8> verbs;
  final int verbCount;

  // PathOpsPathBuffers.points/.verbs copy the whole list on every access;
  // read each exactly once.
  factory _NativeBuffers(PathOpsPathBuffers buffers) =>
      _NativeBuffers._(buffers.points, buffers.verbs);

  _NativeBuffers._(Float32List sourcePoints, Uint8List sourceVerbs)
      : points = calloc<Float>(sourcePoints.length),
        verbs = calloc<Uint8>(sourceVerbs.length),
        verbCount = sourceVerbs.length {
    points.asTypedList(sourcePoints.length).setAll(0, sourcePoints);
    verbs.asTypedList(sourceVerbs.length).setAll(0, sourceVerbs);
  }

  void free() {
    calloc.free(points);
    calloc.free(verbs);
  }
}

PathOpsResult? _toResult(_PathOpsResultStruct native) {
  if (native.success == 0) {
    return null;
  }
  if (native.fillRule >= PathFillType.values.length) {
    // ABI mismatch/corruption: fail closed like an op failure, but still
    // free the native result.
    _deletePathOpsResult(native.rawPath);
    return null;
  }
  // Copy the result out of native memory, then free the native RawPath.
  final points = Float32List.fromList(
    native.points.asTypedList(native.pointCount * 2),
  );
  final verbs = Uint8List.fromList(
    native.verbs.asTypedList(native.verbCount),
  );
  _deletePathOpsResult(native.rawPath);
  return PathOpsResult(
    PathOpsRawPath(points, verbs),
    PathFillType.values[native.fillRule],
  );
}

/// Combines two paths with a boolean operation. Returns null when the
/// operation fails to resolve (degenerate/unsortable geometry).
PathOpsResult? combineRawPaths(
  PathBooleanOp op,
  PathOpsPathBuffers a,
  PathFillType fillRuleA,
  PathOpsPathBuffers b,
  PathFillType fillRuleB,
) {
  if (!a.isConsistent || !b.isConsistent) {
    // The C++ side reads points by verb with no length information; never
    // hand it a short buffer.
    return null;
  }
  final bufA = _NativeBuffers(a);
  final bufB = _NativeBuffers(b);
  try {
    return _toResult(_combinePaths(
      op.index,
      bufA.points,
      bufA.verbs,
      bufA.verbCount,
      fillRuleA.index,
      bufB.points,
      bufB.verbs,
      bufB.verbCount,
      fillRuleB.index,
    ));
  } finally {
    bufA.free();
    bufB.free();
  }
}

/// Flattens a single path under its fill rule into overlap-free geometry.
/// Returns null when simplification fails.
PathOpsResult? simplifyRawPath(
  PathOpsPathBuffers path,
  PathFillType fillRule,
) {
  if (!path.isConsistent) {
    return null;
  }
  final buf = _NativeBuffers(path);
  try {
    return _toResult(_simplifyPath(
      buf.points,
      buf.verbs,
      buf.verbCount,
      fillRule.index,
    ));
  } finally {
    buf.free();
  }
}
