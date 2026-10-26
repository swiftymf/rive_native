import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:rive_native/rive_pathops.dart';
import 'package:rive_native/src/rive_renderer.dart' show PathFillType;

late js.JSObject _module;
late js.JSFunction _deletePathOpsResult;
bool _linked = false;

/// Whether the wasm module carries the pathops exports. False in
/// flutter_runtime builds, where pathops is excluded (editor-only).
bool get pathOpsAvailable => _linked;

/// Links the pathops wasm exports. Only present in editor builds of the wasm
/// module (pathops is excluded from flutter_runtime builds).
class PathOpsWasm {
  static void link(js.JSObject module) {
    bool callable(js.JSAny? export) =>
        export != null && export.isA<js.JSFunction>();
    final deleteFn = module['deletePathOpsResult'];
    if (!callable(module['combinePaths']) ||
        !callable(module['simplifyPath']) ||
        !callable(deleteFn)) {
      // flutter_runtime wasm module (pathops not compiled in), or a
      // partial/mismatched module: fail closed, pathOpsAvailable stays
      // false.
      return;
    }
    _module = module;
    _deletePathOpsResult = deleteFn as js.JSFunction;
    _linked = true;
  }
}

PathOpsResult? _toResult(js.JSAny? resultAny) {
  if (resultAny == null) {
    return null;
  }
  final result = resultAny as js.JSObject;
  if ((result['success'] as js.JSNumber).toDartInt == 0) {
    return null;
  }
  // Buffers are views over the wasm heap; copy them out before the heap can
  // be re-allocated, then free the native RawPath.
  final verbs = Uint8List.fromList(
    (result['verbs'] as js.JSUint8Array).toDart,
  );
  final points = Float32List.fromList(
    (result['points'] as js.JSFloat32Array).toDart,
  );
  final fillRule = (result['fillRule'] as js.JSNumber).toDartInt;
  _deletePathOpsResult.callAsFunction(null, result['rawPath']);
  if (fillRule < 0 || fillRule >= PathFillType.values.length) {
    // ABI mismatch/corruption: fail closed like an op failure (the native
    // result is already freed above).
    return null;
  }
  return PathOpsResult(
    PathOpsRawPath(points, verbs),
    PathFillType.values[fillRule],
  );
}

/// Combines two paths with a boolean operation. Returns null when the
/// operation fails to resolve (degenerate/unsortable geometry) or when the
/// wasm module was built without pathops.
PathOpsResult? combineRawPaths(
  PathBooleanOp op,
  PathOpsPathBuffers a,
  PathFillType fillRuleA,
  PathOpsPathBuffers b,
  PathFillType fillRuleB,
) {
  if (!_linked || !a.isConsistent || !b.isConsistent) {
    return null;
  }
  return _toResult(_module.callMethodVarArgs('combinePaths'.toJS, [
    op.index.toJS,
    a.points.toJS,
    a.verbs.toJS,
    fillRuleA.index.toJS,
    b.points.toJS,
    b.verbs.toJS,
    fillRuleB.index.toJS,
  ]));
}

/// Flattens a single path under its fill rule into overlap-free geometry.
/// Returns null when simplification fails or when the wasm module was built
/// without pathops.
PathOpsResult? simplifyRawPath(
  PathOpsPathBuffers path,
  PathFillType fillRule,
) {
  if (!_linked || !path.isConsistent) {
    return null;
  }
  return _toResult(_module.callMethodVarArgs('simplifyPath'.toJS, [
    path.points.toJS,
    path.verbs.toJS,
    fillRule.index.toJS,
  ]));
}
