import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:rive_native/src/semantics/semantic_role.dart';
import 'package:rive_native/src/semantics/semantics_diff.dart';

/// A single node in the semantic tree.
@experimental
@internal
class SemanticNodeData {
  final int id;
  int parentId;
  SemanticRole role;
  String label;
  String value;
  String hint;
  int stateFlags;
  int traitFlags;
  int headingLevel;
  double minX, minY, maxX, maxY;
  final List<int> children = [];

  SemanticNodeData({
    required this.id,
    required this.parentId,
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
  });

  String get boundsString =>
      '(${minX.toStringAsFixed(1)}, ${minY.toStringAsFixed(1)}, '
      '${maxX.toStringAsFixed(1)}, ${maxY.toStringAsFixed(1)})';
}

/// Maintains an in-memory semantic tree built from incremental [SemanticsDiff]
/// updates. Notifies listeners whenever [applyDiff] changes the tree.
@experimental
@internal
class SemanticTreeModel extends ChangeNotifier {
  final Map<int, SemanticNodeData> _nodesById = {};
  final List<int> _roots = [];
  int _version = 0;

  int get nodeCount => _nodesById.length;

  /// Monotonically increasing version, incremented on each [applyDiff] that
  /// changes the tree. Useful for change detection without deep comparison.
  int get version => _version;

  /// The root node IDs in sibling order.
  List<int> get roots => _roots;

  /// Look up a node by its ID.
  SemanticNodeData? nodeById(int id) => _nodesById[id];

  void _detach(int id) {
    final node = _nodesById[id];
    if (node == null) return;
    if (node.parentId < 0) {
      _roots.remove(id);
    } else {
      _nodesById[node.parentId]?.children.remove(id);
    }
  }

  void _attach(int id, int parentId, int siblingIndex) {
    final node = _nodesById[id];
    if (node == null) return;
    if (parentId < 0) {
      node.parentId = -1;
      final index = siblingIndex.clamp(0, _roots.length);
      _roots.insert(index, id);
    } else {
      final parent = _nodesById[parentId];
      if (parent == null) {
        node.parentId = -1;
        _roots.add(id);
      } else {
        node.parentId = parentId;
        final index = siblingIndex.clamp(0, parent.children.length);
        parent.children.insert(index, id);
      }
    }
  }

  void _removeSubtree(int id) {
    final node = _nodesById[id];
    if (node == null) return;
    for (final child in List<int>.from(node.children)) {
      _removeSubtree(child);
    }
    _detach(id);
    _nodesById.remove(id);
  }

  /// Apply an incremental diff to the tree and notify listeners if anything
  /// changed. No-op diffs (payload whose field values exactly match the
  /// current model) do not bump the version or notify — the native side
  /// guards against emitting these, but applyDiff defends its subscribers
  /// regardless.
  void applyDiff(SemanticsDiff diff) {
    if (diff.isEmpty) return;

    var changed = false;

    for (final id in diff.removed) {
      if (_nodesById.containsKey(id)) {
        _removeSubtree(id);
        changed = true;
      }
    }
    for (final n in diff.added) {
      final existing = _nodesById[n.id];
      if (existing != null) {
        if (existing.role != n.role ||
            existing.label != n.label ||
            existing.value != n.value ||
            existing.hint != n.hint ||
            existing.stateFlags != n.stateFlags ||
            existing.traitFlags != n.traitFlags ||
            existing.headingLevel != n.headingLevel ||
            existing.minX != n.minX ||
            existing.minY != n.minY ||
            existing.maxX != n.maxX ||
            existing.maxY != n.maxY) {
          existing.role = n.role;
          existing.label = n.label;
          existing.value = n.value;
          existing.hint = n.hint;
          existing.stateFlags = n.stateFlags;
          existing.traitFlags = n.traitFlags;
          existing.headingLevel = n.headingLevel;
          existing.minX = n.minX;
          existing.minY = n.minY;
          existing.maxX = n.maxX;
          existing.maxY = n.maxY;
          changed = true;
        }
      } else {
        _nodesById[n.id] = SemanticNodeData(
          id: n.id,
          parentId: -1,
          role: n.role,
          label: n.label,
          value: n.value,
          hint: n.hint,
          stateFlags: n.stateFlags,
          traitFlags: n.traitFlags,
          headingLevel: n.headingLevel,
          minX: n.minX,
          minY: n.minY,
          maxX: n.maxX,
          maxY: n.maxY,
        );
        changed = true;
      }
      _detach(n.id);
      _attach(n.id, n.parentId, n.siblingIndex);
    }
    for (final n in diff.moved) {
      final existing = _nodesById[n.id];
      if (existing == null) continue;
      if (existing.minX != n.minX ||
          existing.minY != n.minY ||
          existing.maxX != n.maxX ||
          existing.maxY != n.maxY) {
        existing.minX = n.minX;
        existing.minY = n.minY;
        existing.maxX = n.maxX;
        existing.maxY = n.maxY;
        changed = true;
      }
      _detach(n.id);
      _attach(n.id, n.parentId, n.siblingIndex);
      changed = true;
    }
    for (final update in diff.childrenUpdated) {
      if (update.parentId < 0) {
        final next = update.childIds.where(_nodesById.containsKey).toList();
        if (!listEquals(_roots, next)) {
          _roots
            ..clear()
            ..addAll(next);
          for (final id in _roots) {
            _nodesById[id]?.parentId = -1;
          }
          changed = true;
        }
      } else {
        final parent = _nodesById[update.parentId];
        if (parent == null) continue;
        final next = update.childIds.where(_nodesById.containsKey).toList();
        if (!listEquals(parent.children, next)) {
          parent.children
            ..clear()
            ..addAll(next);
          for (final id in parent.children) {
            _nodesById[id]?.parentId = update.parentId;
          }
          changed = true;
        }
      }
    }
    for (final n in diff.updatedSemantic) {
      final existing = _nodesById[n.id];
      if (existing == null) continue;
      if (existing.role == n.role &&
          existing.label == n.label &&
          existing.value == n.value &&
          existing.hint == n.hint &&
          existing.stateFlags == n.stateFlags &&
          existing.traitFlags == n.traitFlags &&
          existing.headingLevel == n.headingLevel) {
        continue;
      }
      existing.role = n.role;
      existing.label = n.label;
      existing.value = n.value;
      existing.hint = n.hint;
      existing.stateFlags = n.stateFlags;
      existing.traitFlags = n.traitFlags;
      existing.headingLevel = n.headingLevel;
      changed = true;
    }
    for (final n in diff.updatedGeometry) {
      final existing = _nodesById[n.id];
      if (existing == null) continue;
      if (existing.minX == n.minX &&
          existing.minY == n.minY &&
          existing.maxX == n.maxX &&
          existing.maxY == n.maxY) {
        continue;
      }
      existing.minX = n.minX;
      existing.minY = n.minY;
      existing.maxX = n.maxX;
      existing.maxY = n.maxY;
      changed = true;
    }

    if (!changed) return;
    _version++;
    notifyListeners();
  }

  /// Returns every node in depth-first order, paired with its depth level.
  List<({int depth, SemanticNodeData node})> flattened() {
    final out = <({int depth, SemanticNodeData node})>[];
    void walk(int id, int depth) {
      final node = _nodesById[id];
      if (node == null) return;
      out.add((depth: depth, node: node));
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    for (final root in _roots) {
      walk(root, 0);
    }
    return out;
  }
}
