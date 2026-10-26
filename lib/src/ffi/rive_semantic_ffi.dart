import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:rive_native/src/ffi/rive_ffi.dart';
import 'package:rive_native/src/semantics/semantic_role.dart';
import 'package:rive_native/src/semantics/semantics_diff.dart';

// =============================================================================
// Native struct definitions
// =============================================================================

final class _SemanticsDiffNodeFFI extends Struct {
  @Uint32()
  external int id;

  @Uint32()
  external int role;

  external Pointer<Utf8> label;

  external Pointer<Utf8> value;

  external Pointer<Utf8> hint;

  @Uint32()
  external int stateFlags;

  @Uint32()
  external int traitFlags;

  @Float()
  external double minX;

  @Float()
  external double minY;

  @Float()
  external double maxX;

  @Float()
  external double maxY;

  @Int32()
  external int parentId;

  @Uint32()
  external int siblingIndex;

  @Uint32()
  external int headingLevel;
}

final class _SemanticsChildrenUpdateFFI extends Struct {
  @Int32()
  external int parentId;

  external Pointer<Uint32> childIds;

  @Uint32()
  external int childCount;
}

final class _SemanticsBoundsUpdateFFI extends Struct {
  @Uint32()
  external int id;

  @Float()
  external double minX;

  @Float()
  external double minY;

  @Float()
  external double maxX;

  @Float()
  external double maxY;
}

final class _SemanticsDiffFFI extends Struct {
  @Uint64()
  external int treeVersion;

  @Uint32()
  external int frameNumber;

  @Uint32()
  external int rootId;

  external Pointer<_SemanticsDiffNodeFFI> added;

  @Uint32()
  external int addedCount;

  external Pointer<Uint32> removed;

  @Uint32()
  external int removedCount;

  external Pointer<_SemanticsDiffNodeFFI> moved;

  @Uint32()
  external int movedCount;

  external Pointer<_SemanticsDiffNodeFFI> updatedSemantic;

  @Uint32()
  external int updatedSemanticCount;

  external Pointer<_SemanticsBoundsUpdateFFI> updatedGeometry;

  @Uint32()
  external int updatedGeometryCount;

  external Pointer<_SemanticsChildrenUpdateFFI> childrenUpdated;

  @Uint32()
  external int childrenUpdatedCount;
}

// =============================================================================
// Semantic FFI bindings
// =============================================================================

/// Groups all semantic-related native FFI bindings. Methods are called from
/// the concrete FFI implementations of [Artboard] and [StateMachine].
@internal
class SemanticsFFI {
  SemanticsFFI._();

  // ---- native function lookups ----

  static final Pointer<Void> Function(Pointer<Void>)
      _stateMachineDrainSemanticsDiff = nativeLib
          .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
              'stateMachineDrainSemanticsDiff')
          .asFunction();

  static final void Function(Pointer<Void>) _freeSemanticDiff = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>('freeSemanticDiff')
      .asFunction();

  static final bool Function(Pointer<Void>, int)
      _stateMachineFocusSemanticNode = nativeLib
          .lookup<NativeFunction<Bool Function(Pointer<Void>, Uint32)>>(
              'stateMachineFocusSemanticNode')
          .asFunction();

  static final void Function(Pointer<Void>, int, int)
      _stateMachineFireSemanticAction = nativeLib
          .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32, Uint8)>>(
              'stateMachineFireSemanticAction')
          .asFunction();

  static final void Function(Pointer<Void>) _stateMachineEnableSemantics =
      nativeLib
          .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
              'stateMachineEnableSemantics')
          .asFunction();

  /// Enable semantics on the given state machine.
  static void enableSemantics(Pointer<Void> stateMachine) {
    _stateMachineEnableSemantics(stateMachine);
  }

  /// Request focus on the FocusData sibling of the SemanticData that owns the
  /// given semantic node ID. Returns true if focus was set.
  static bool requestFocus(Pointer<Void> stateMachine, int semanticNodeId) {
    return _stateMachineFocusSemanticNode(stateMachine, semanticNodeId);
  }

  /// Fire a semantic action on the state machine for the given semantic node.
  static void fireAction(
      Pointer<Void> stateMachine, int semanticNodeId, int actionType) {
    _stateMachineFireSemanticAction(stateMachine, semanticNodeId, actionType);
  }

  /// Returns the semantic diff since the last call.
  static SemanticsDiff drainDiff(Pointer<Void> stateMachine) {
    final diffPtrRaw = _stateMachineDrainSemanticsDiff(stateMachine);
    if (diffPtrRaw == nullptr) {
      return SemanticsDiff.empty;
    }

    try {
      return _decodeDiff(diffPtrRaw);
    } finally {
      _freeSemanticDiff(diffPtrRaw);
    }
  }

  // ---- diff decoding ----

  static SemanticsDiff _decodeDiff(Pointer<Void> diffPtrRaw) {
    final nativeDiff = diffPtrRaw.cast<_SemanticsDiffFFI>().ref;

    final removed = _readUint32List(nativeDiff.removed, nativeDiff.removedCount);
    final childrenUpdated = _readChildrenUpdates(
        nativeDiff.childrenUpdated, nativeDiff.childrenUpdatedCount);

    return SemanticsDiff(
      treeVersion: nativeDiff.treeVersion,
      frameNumber: nativeDiff.frameNumber,
      rootId: nativeDiff.rootId,
      added: _readNodes(nativeDiff.added, nativeDiff.addedCount),
      removed: removed,
      moved: _readNodes(nativeDiff.moved, nativeDiff.movedCount),
      updatedSemantic: _readNodes(
          nativeDiff.updatedSemantic, nativeDiff.updatedSemanticCount),
      updatedGeometry: _readBoundsUpdates(
          nativeDiff.updatedGeometry, nativeDiff.updatedGeometryCount),
      childrenUpdated: childrenUpdated,
    );
  }

  // Owned copy — native buffer is freed when drainDiff() returns, so we cannot
  // hand out the zero-copy asTypedList view itself.
  static List<int> _readUint32List(Pointer<Uint32> ptr, int count) {
    if (ptr == nullptr || count <= 0) {
      return const [];
    }
    return Uint32List.fromList(ptr.asTypedList(count));
  }

  static List<SemanticsChildrenUpdate> _readChildrenUpdates(
      Pointer<_SemanticsChildrenUpdateFFI> ptr, int count) {
    if (ptr == nullptr || count <= 0) {
      return const [];
    }
    return List<SemanticsChildrenUpdate>.generate(count, (i) {
      final update = (ptr + i).ref;
      return SemanticsChildrenUpdate(
        parentId: update.parentId,
        childIds: _readUint32List(update.childIds, update.childCount),
      );
    }, growable: false);
  }

  static List<SemanticsBoundsUpdate> _readBoundsUpdates(
      Pointer<_SemanticsBoundsUpdateFFI> ptr, int count) {
    if (ptr == nullptr || count <= 0) {
      return const [];
    }
    return List<SemanticsBoundsUpdate>.generate(count, (i) {
      final b = (ptr + i).ref;
      return SemanticsBoundsUpdate(
        id: b.id,
        minX: b.minX,
        minY: b.minY,
        maxX: b.maxX,
        maxY: b.maxY,
      );
    }, growable: false);
  }

  static List<SemanticsDiffNode> _readNodes(
      Pointer<_SemanticsDiffNodeFFI> nodesPtr, int count) {
    if (nodesPtr == nullptr || count <= 0) {
      return const [];
    }
    return List<SemanticsDiffNode>.generate(count, (i) {
      final node = (nodesPtr + i).ref;
      final labelPtr = node.label;
      final valuePtr = node.value;
      final hintPtr = node.hint;
      return SemanticsDiffNode(
        id: node.id,
        role: SemanticRole.fromValue(node.role),
        label: labelPtr == nullptr ? '' : labelPtr.toDartString(),
        value: valuePtr == nullptr ? '' : valuePtr.toDartString(),
        hint: hintPtr == nullptr ? '' : hintPtr.toDartString(),
        stateFlags: node.stateFlags,
        traitFlags: node.traitFlags,
        headingLevel: node.headingLevel,
        minX: node.minX,
        minY: node.minY,
        maxX: node.maxX,
        maxY: node.maxY,
        parentId: node.parentId,
        siblingIndex: node.siblingIndex,
      );
    }, growable: false);
  }
}
