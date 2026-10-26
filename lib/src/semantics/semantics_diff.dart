import 'package:meta/meta.dart';

import 'semantic_role.dart';

@experimental
@internal
class SemanticsDiffNode {
  final int id;
  final SemanticRole role;
  final String label;
  final String value;
  final String hint;
  final int stateFlags;
  final int traitFlags;
  final int headingLevel;
  final double minX, minY, maxX, maxY;
  final int parentId;
  final int siblingIndex;

  const SemanticsDiffNode({
    required this.id,
    required this.role,
    required this.label,
    this.value = '',
    this.hint = '',
    this.stateFlags = 0,
    this.traitFlags = 0,
    this.headingLevel = 0,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.parentId,
    required this.siblingIndex,
  });
}

@experimental
@internal
class SemanticsChildrenUpdate {
  final int parentId;
  final List<int> childIds;

  const SemanticsChildrenUpdate({
    required this.parentId,
    required this.childIds,
  });
}

@experimental
@internal
class SemanticsBoundsUpdate {
  final int id;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const SemanticsBoundsUpdate({
    required this.id,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });
}

/// Incremental semantic delta produced by the native runtime and consumed
/// by platform accessibility adapters.
///
/// ## Ordering contract
///
/// All lists are emitted in deterministic tree order so a consumer can apply
/// them in a single pass without a deferred-attachment queue:
///
/// * [added], [moved], [updatedSemantic], [updatedGeometry] — current-tree
///   pre-order. For any entry, its parent (if present in the same list or
///   already resident) has been emitted earlier.
/// * [removed] — previous-tree pre-order.
/// * [childrenUpdated] — parent ids appear in the order their subtrees are
///   first entered during a pre-order walk of the current tree; parents that
///   only existed in the previous tree are appended in previous-tree order.
///
/// A minimal adapter can therefore process the lists in the order declared by
/// [SemanticsDiff] fields (removed → added → moved → childrenUpdated →
/// updatedSemantic → updatedGeometry) and, within each list, iterate linearly.
@experimental
@internal
class SemanticsDiff {
  final int treeVersion;
  final int frameNumber;
  final int rootId;

  /// Nodes newly present in the semantic tree. Tree pre-order: a parent
  /// appears before its children.
  final List<SemanticsDiffNode> added;

  /// Ids of nodes that were present in the previous snapshot and are absent
  /// from the current one. Previous-tree pre-order.
  final List<int> removed;

  /// Nodes whose parent or sibling position changed. Tree pre-order in the
  /// new tree; consumers should reparent/reorder in place.
  final List<SemanticsDiffNode> moved;

  /// Nodes whose role, label, value, hint, stateFlags, traitFlags, or
  /// headingLevel changed. Tree pre-order. Bounds in these entries may be
  /// stale — use [updatedGeometry] for positional updates.
  final List<SemanticsDiffNode> updatedSemantic;

  /// Bounds-only updates for hot-path geometry changes. Tree pre-order.
  final List<SemanticsBoundsUpdate> updatedGeometry;

  /// Authoritative child ordering for any parent whose child list changed
  /// (reorder, reparent, add, or remove). Parent ids in pre-order; each
  /// entry lists the full ordered children for that parent.
  final List<SemanticsChildrenUpdate> childrenUpdated;

  const SemanticsDiff({
    required this.treeVersion,
    required this.frameNumber,
    required this.rootId,
    required this.added,
    required this.removed,
    required this.moved,
    required this.updatedSemantic,
    required this.updatedGeometry,
    required this.childrenUpdated,
  });

  static const SemanticsDiff empty = SemanticsDiff(
    treeVersion: 0,
    frameNumber: 0,
    rootId: 0,
    added: [],
    removed: [],
    moved: [],
    updatedSemantic: [],
    updatedGeometry: [],
    childrenUpdated: [],
  );

  bool get isEmpty =>
      added.isEmpty &&
      removed.isEmpty &&
      moved.isEmpty &&
      updatedSemantic.isEmpty &&
      updatedGeometry.isEmpty &&
      childrenUpdated.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
