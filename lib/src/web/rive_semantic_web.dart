import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:rive_native/src/rive_native_web.dart' show RiveWasm;
import 'package:rive_native/src/semantics/semantic_role.dart';
import 'package:rive_native/src/semantics/semantics_diff.dart';

// =============================================================================
// WASM struct layout constants (32-bit WASM)
//
// SemanticsDiffNodeFFI (56 bytes):
//   0: id (uint32)
//   4: role (uint32)
//   8: label (ptr, 4 bytes)
//  12: value (ptr, 4 bytes)
//  16: hint (ptr, 4 bytes)
//  20: stateFlags (uint32)
//  24: traitFlags (uint32)
//  28: minX (float32)
//  32: minY (float32)
//  36: maxX (float32)
//  40: maxY (float32)
//  44: parentId (int32)
//  48: siblingIndex (uint32)
//  52: headingLevel (uint32)
//
// SemanticsChildrenUpdateFFI (12 bytes):
//   0: parentId (int32)
//   4: childIds (ptr, 4 bytes)
//   8: childCount (uint32)
//
// SemanticsBoundsUpdateFFI (20 bytes):
//   0: id (uint32)
//   4: minX (float32)
//   8: minY (float32)
//  12: maxX (float32)
//  16: maxY (float32)
//
// SemanticsDiffFFI (64 bytes):
//   0: treeVersion (uint64)
//   8: frameNumber (uint32)
//  12: rootId (uint32)
//  16: added (ptr)
//  20: addedCount (uint32)
//  24: removed (ptr)  — points to uint32[] of removed node IDs
//  28: removedCount (uint32)
//  32: moved (ptr)
//  36: movedCount (uint32)
//  40: updatedSemantic (ptr)
//  44: updatedSemanticCount (uint32)
//  48: updatedGeometry (ptr)
//  52: updatedGeometryCount (uint32)
//  56: childrenUpdated (ptr)
//  60: childrenUpdatedCount (uint32)
// =============================================================================

/// Groups all semantic-related WASM bindings.
class SemanticsWasm {
  SemanticsWasm._();

  static const int _nodeSize = 56;
  static const int _childrenUpdateSize = 12;
  static const int _boundsUpdateSize = 20;

  // ---- WASM function references ----

  static late js.JSFunction _freeSemanticDiff;
  static late js.JSFunction _stateMachineFireSemanticAction;
  static late js.JSFunction _stateMachineDrainSemanticsDiff;
  static late js.JSFunction _stateMachineFocusSemanticNode;
  static late js.JSFunction _stateMachineEnableSemantics;

  /// Initialize WASM function references from the loaded module.
  static void link(js.JSObject module) {
    _freeSemanticDiff = module['_freeSemanticDiff'] as js.JSFunction;
    _stateMachineFireSemanticAction =
        module['_stateMachineFireSemanticAction'] as js.JSFunction;
    _stateMachineDrainSemanticsDiff =
        module['_stateMachineDrainSemanticsDiff'] as js.JSFunction;
    _stateMachineFocusSemanticNode =
        module['_stateMachineFocusSemanticNode'] as js.JSFunction;
    _stateMachineEnableSemantics =
        module['_stateMachineEnableSemantics'] as js.JSFunction;
  }

  /// Enable semantics on the given state machine.
  static void enableSemantics(int stateMachinePtr) {
    if (stateMachinePtr == 0) return;
    _stateMachineEnableSemantics.callAsFunction(null, stateMachinePtr.toJS);
  }

  /// Fire a semantic action on the state machine for the given semantic node.
  static void fireAction(
      int stateMachinePtr, int semanticNodeId, int actionType) {
    _stateMachineFireSemanticAction.callAsFunction(
        null, stateMachinePtr.toJS, semanticNodeId.toJS, actionType.toJS);
  }

  /// Request focus on the FocusData sibling of the SemanticData that owns the
  /// given semantic node ID. Returns true if focus was set.
  static bool requestFocus(int stateMachinePtr, int semanticNodeId) {
    if (stateMachinePtr == 0) return false;
    final result = _stateMachineFocusSemanticNode.callAsFunction(
        null, stateMachinePtr.toJS, semanticNodeId.toJS);
    return (result as js.JSNumber).toDartInt != 0;
  }

  /// Returns the semantic diff since the last call.
  static SemanticsDiff drainDiff(int stateMachinePtr) {
    if (stateMachinePtr == 0) return SemanticsDiff.empty;

    final diffPtr = (_stateMachineDrainSemanticsDiff.callAsFunction(
            null, stateMachinePtr.toJS) as js.JSNumber)
        .toDartInt;
    if (diffPtr == 0) return SemanticsDiff.empty;

    try {
      return _decodeDiff(diffPtr);
    } finally {
      _freeSemanticDiff.callAsFunction(null, diffPtr.toJS);
    }
  }

  // ---- diff decoding from WASM heap ----

  static SemanticsDiff _decodeDiff(int diffPtr) {
    final data = RiveWasm.heapDataView(diffPtr, 64);

    // treeVersion is uint64 at offset 0 — read as two uint32s (little-endian).
    // Use multiplication rather than `<< 32`: on Dart Web, `int` is a JS
    // Number and bitwise shifts are 32-bit (JS takes shift amount mod 32),
    // so the high word would be dropped. Multiply by 2^32 instead — the
    // result stays within JS Number's 53-bit integer precision for our use.
    final treeVersionLow = data.getUint32(0, Endian.little);
    final treeVersionHigh = data.getUint32(4, Endian.little);
    final treeVersion = treeVersionLow + treeVersionHigh * 0x100000000;

    final frameNumber = data.getUint32(8, Endian.little);
    final rootId = data.getUint32(12, Endian.little);

    final addedPtr = data.getUint32(16, Endian.little);
    final addedCount = data.getUint32(20, Endian.little);
    final removedPtr = data.getUint32(24, Endian.little);
    final removedCount = data.getUint32(28, Endian.little);
    final movedPtr = data.getUint32(32, Endian.little);
    final movedCount = data.getUint32(36, Endian.little);
    final updatedSemanticPtr = data.getUint32(40, Endian.little);
    final updatedSemanticCount = data.getUint32(44, Endian.little);
    final updatedGeometryPtr = data.getUint32(48, Endian.little);
    final updatedGeometryCount = data.getUint32(52, Endian.little);
    final childrenUpdatedPtr = data.getUint32(56, Endian.little);
    final childrenUpdatedCount = data.getUint32(60, Endian.little);

    return SemanticsDiff(
      treeVersion: treeVersion,
      frameNumber: frameNumber,
      rootId: rootId,
      added: _readNodes(addedPtr, addedCount),
      removed: _readUint32List(removedPtr, removedCount),
      moved: _readNodes(movedPtr, movedCount),
      updatedSemantic: _readNodes(updatedSemanticPtr, updatedSemanticCount),
      updatedGeometry:
          _readBoundsUpdates(updatedGeometryPtr, updatedGeometryCount),
      childrenUpdated:
          _readChildrenUpdates(childrenUpdatedPtr, childrenUpdatedCount),
    );
  }

  static List<SemanticsDiffNode> _readNodes(int ptr, int count) {
    if (ptr == 0 || count <= 0) return const [];
    final data = RiveWasm.heapDataView(ptr, count * _nodeSize);
    return List<SemanticsDiffNode>.generate(count, (i) {
      final o = i * _nodeSize;
      final labelPtr = data.getUint32(o + 8, Endian.little);
      final valuePtr = data.getUint32(o + 12, Endian.little);
      final hintPtr = data.getUint32(o + 16, Endian.little);
      return SemanticsDiffNode(
        id: data.getUint32(o, Endian.little),
        role: SemanticRole.fromValue(data.getUint32(o + 4, Endian.little)),
        label: labelPtr == 0 ? '' : RiveWasm.toDartString(labelPtr),
        value: valuePtr == 0 ? '' : RiveWasm.toDartString(valuePtr),
        hint: hintPtr == 0 ? '' : RiveWasm.toDartString(hintPtr),
        stateFlags: data.getUint32(o + 20, Endian.little),
        traitFlags: data.getUint32(o + 24, Endian.little),
        minX: data.getFloat32(o + 28, Endian.little),
        minY: data.getFloat32(o + 32, Endian.little),
        maxX: data.getFloat32(o + 36, Endian.little),
        maxY: data.getFloat32(o + 40, Endian.little),
        parentId: data.getInt32(o + 44, Endian.little),
        siblingIndex: data.getUint32(o + 48, Endian.little),
        headingLevel: data.getUint32(o + 52, Endian.little),
      );
    }, growable: false);
  }

  static List<SemanticsBoundsUpdate> _readBoundsUpdates(int ptr, int count) {
    if (ptr == 0 || count <= 0) return const [];
    final data = RiveWasm.heapDataView(ptr, count * _boundsUpdateSize);
    return List<SemanticsBoundsUpdate>.generate(count, (i) {
      final o = i * _boundsUpdateSize;
      return SemanticsBoundsUpdate(
        id: data.getUint32(o, Endian.little),
        minX: data.getFloat32(o + 4, Endian.little),
        minY: data.getFloat32(o + 8, Endian.little),
        maxX: data.getFloat32(o + 12, Endian.little),
        maxY: data.getFloat32(o + 16, Endian.little),
      );
    }, growable: false);
  }

  // Owned copy — heapViewU32 aliases WASM memory, which is freed when the
  // native diff is freed and invalidated on memory growth.
  static List<int> _readUint32List(int ptr, int count) {
    if (ptr == 0 || count <= 0) return const [];
    return Uint32List.fromList(RiveWasm.heapViewU32(ptr, count));
  }

  static List<SemanticsChildrenUpdate> _readChildrenUpdates(
      int ptr, int count) {
    if (ptr == 0 || count <= 0) return const [];
    final data = RiveWasm.heapDataView(ptr, count * _childrenUpdateSize);
    return List<SemanticsChildrenUpdate>.generate(count, (i) {
      final o = i * _childrenUpdateSize;
      return SemanticsChildrenUpdate(
        parentId: data.getInt32(o, Endian.little),
        childIds: _readUint32List(
          data.getUint32(o + 4, Endian.little),
          data.getUint32(o + 8, Endian.little),
        ),
      );
    }, growable: false);
  }
}
