import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/semantics.dart';

/// Unit tests for [SemanticTreeModel.applyDiff] using hand-crafted diffs.
/// These tests exercise the applyDiff state machine directly and do not
/// load any .riv file or spin up a state machine — the native-produced
/// diff is fully characterised by the [SemanticsDiff] input.

SemanticsDiffNode _node({
  required int id,
  int parentId = -1,
  int siblingIndex = 0,
  SemanticRole role = SemanticRole.none,
  String label = '',
  String value = '',
  String hint = '',
  int stateFlags = 0,
  int traitFlags = 0,
  int headingLevel = 0,
  double minX = 0,
  double minY = 0,
  double maxX = 0,
  double maxY = 0,
}) =>
    SemanticsDiffNode(
      id: id,
      role: role,
      label: label,
      value: value,
      hint: hint,
      stateFlags: stateFlags,
      traitFlags: traitFlags,
      headingLevel: headingLevel,
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
      parentId: parentId,
      siblingIndex: siblingIndex,
    );

SemanticsDiff _diff({
  List<SemanticsDiffNode> added = const [],
  List<int> removed = const [],
  List<SemanticsDiffNode> moved = const [],
  List<SemanticsDiffNode> updatedSemantic = const [],
  List<SemanticsBoundsUpdate> updatedGeometry = const [],
  List<SemanticsChildrenUpdate> childrenUpdated = const [],
  int treeVersion = 1,
  int frameNumber = 0,
  int rootId = 0,
}) =>
    SemanticsDiff(
      treeVersion: treeVersion,
      frameNumber: frameNumber,
      rootId: rootId,
      added: added,
      removed: removed,
      moved: moved,
      updatedSemantic: updatedSemantic,
      updatedGeometry: updatedGeometry,
      childrenUpdated: childrenUpdated,
    );

void main() {
  group('SemanticState.effectiveChecked / effectiveMixed', () {
    test('Mixed takes precedence when both bits are set', () {
      final both = SemanticState.checked | SemanticState.mixed;
      expect(SemanticState.effectiveChecked(both), isFalse);
      expect(SemanticState.effectiveMixed(both), isTrue);
    });

    test('Checked only → effectiveChecked is true', () {
      expect(SemanticState.effectiveChecked(SemanticState.checked), isTrue);
      expect(SemanticState.effectiveMixed(SemanticState.checked), isFalse);
    });

    test('Mixed only → effectiveMixed is true, effectiveChecked is false', () {
      expect(SemanticState.effectiveChecked(SemanticState.mixed), isFalse);
      expect(SemanticState.effectiveMixed(SemanticState.mixed), isTrue);
    });

    test('Neither bit set → both effective states are false', () {
      expect(SemanticState.effectiveChecked(0), isFalse);
      expect(SemanticState.effectiveMixed(0), isFalse);
    });

    test('Unrelated bits do not affect the check', () {
      final flags = SemanticState.mixed |
          SemanticState.selected |
          SemanticState.focused;
      expect(SemanticState.effectiveMixed(flags), isTrue);
      expect(SemanticState.effectiveChecked(flags), isFalse);
    });
  });

  group('SemanticTreeModel.applyDiff', () {
    test('empty diff is a no-op: no version bump, no listener notification',
        () {
      final model = SemanticTreeModel();
      var notifyCount = 0;
      model.addListener(() => notifyCount++);

      model.applyDiff(SemanticsDiff.empty);

      expect(model.version, 0);
      expect(notifyCount, 0);
      expect(model.nodeCount, 0);

      model.dispose();
    });

    test('first-frame diff populates the tree in pre-order', () {
      final model = SemanticTreeModel();
      var notifyCount = 0;
      model.addListener(() => notifyCount++);

      //    1 (root)
      //    ├── 2
      //    └── 3
      //        └── 4
      final diff = _diff(added: [
        _node(id: 1, parentId: -1, siblingIndex: 0, role: SemanticRole.group),
        _node(id: 2, parentId: 1, siblingIndex: 0, role: SemanticRole.text),
        _node(id: 3, parentId: 1, siblingIndex: 1, role: SemanticRole.group),
        _node(id: 4, parentId: 3, siblingIndex: 0, role: SemanticRole.text),
      ], childrenUpdated: [
        const SemanticsChildrenUpdate(parentId: -1, childIds: [1]),
        const SemanticsChildrenUpdate(parentId: 1, childIds: [2, 3]),
        const SemanticsChildrenUpdate(parentId: 3, childIds: [4]),
      ]);

      model.applyDiff(diff);

      expect(model.nodeCount, 4);
      expect(model.roots, [1]);
      expect(model.nodeById(1)?.children, [2, 3]);
      expect(model.nodeById(3)?.children, [4]);
      expect(model.nodeById(4)?.parentId, 3);
      expect(model.version, 1);
      expect(notifyCount, 1);

      model.dispose();
    });

    test(
        'non-empty diff whose payload matches the current model does not notify',
        () {
      final model = SemanticTreeModel();

      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1, role: SemanticRole.button, label: 'A'),
      ]));
      expect(model.version, 1);

      var notifyCount = 0;
      model.addListener(() => notifyCount++);

      // updatedSemantic carrying the same field values — should be a no-op.
      model.applyDiff(_diff(updatedSemantic: [
        _node(id: 1, parentId: -1, role: SemanticRole.button, label: 'A'),
      ]));
      expect(model.version, 1, reason: 'version should not advance');
      expect(notifyCount, 0, reason: 'listeners should not fire');

      // updatedGeometry carrying the same bounds — also a no-op.
      model.applyDiff(_diff(updatedGeometry: const [
        SemanticsBoundsUpdate(id: 1, minX: 0, minY: 0, maxX: 0, maxY: 0),
      ]));
      expect(model.version, 1);
      expect(notifyCount, 0);

      // childrenUpdated whose child list matches — also a no-op.
      model.applyDiff(_diff(childrenUpdated: const [
        SemanticsChildrenUpdate(parentId: -1, childIds: [1]),
      ]));
      expect(model.version, 1);
      expect(notifyCount, 0);

      model.dispose();
    });

    test('version increments by exactly one per non-empty diff', () {
      final model = SemanticTreeModel();

      model.applyDiff(_diff(added: [_node(id: 1, parentId: -1)]));
      expect(model.version, 1);

      model.applyDiff(_diff(added: [_node(id: 2, parentId: 1)]));
      expect(model.version, 2);

      model.applyDiff(SemanticsDiff.empty);
      expect(model.version, 2, reason: 'empty diff must not bump version');

      model.dispose();
    });

    test('listeners are notified exactly once per non-empty applyDiff', () {
      final model = SemanticTreeModel();
      var notifyCount = 0;
      model.addListener(() => notifyCount++);

      // One apply with many entries → one notify.
      model.applyDiff(_diff(
        added: [
          _node(id: 1, parentId: -1),
          _node(id: 2, parentId: 1),
          _node(id: 3, parentId: 1),
        ],
        updatedGeometry: const [
          SemanticsBoundsUpdate(
              id: 1, minX: 0, minY: 0, maxX: 10, maxY: 10),
        ],
      ));

      expect(notifyCount, 1);

      model.dispose();
    });

    test('removed tears down the entire subtree', () {
      final model = SemanticTreeModel();

      //    1
      //    ├── 2
      //    │   ├── 4
      //    │   └── 5
      //    └── 3
      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1),
        _node(id: 2, parentId: 1, siblingIndex: 0),
        _node(id: 3, parentId: 1, siblingIndex: 1),
        _node(id: 4, parentId: 2, siblingIndex: 0),
        _node(id: 5, parentId: 2, siblingIndex: 1),
      ]));
      expect(model.nodeCount, 5);

      // Removing 2 should also evict 4 and 5.
      model.applyDiff(_diff(removed: const [2]));

      expect(model.nodeCount, 2);
      expect(model.nodeById(2), isNull);
      expect(model.nodeById(4), isNull);
      expect(model.nodeById(5), isNull);
      expect(model.nodeById(1)?.children, [3],
          reason: '2 should be unlinked from its parent');

      model.dispose();
    });

    test('added with an existing id updates fields in place', () {
      final model = SemanticTreeModel();

      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1, role: SemanticRole.group, label: 'A'),
      ]));
      expect(model.nodeById(1)?.label, 'A');

      // Same id re-added with new payload → in-place update (no duplicate).
      model.applyDiff(_diff(added: [
        _node(
          id: 1,
          parentId: -1,
          role: SemanticRole.button,
          label: 'Clicked',
          value: 'v2',
          stateFlags: 0x4,
          traitFlags: 0x2,
          minX: 10,
          maxX: 20,
        ),
      ]));

      expect(model.nodeCount, 1);
      final n = model.nodeById(1)!;
      expect(n.role, SemanticRole.button);
      expect(n.label, 'Clicked');
      expect(n.value, 'v2');
      expect(n.stateFlags, 0x4);
      expect(n.traitFlags, 0x2);
      expect(n.minX, 10);
      expect(n.maxX, 20);

      model.dispose();
    });

    test('moved updates bounds and re-attaches to new parent/sibling slot',
        () {
      final model = SemanticTreeModel();

      //    1
      //    ├── 2
      //    ├── 3
      //    └── 4
      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1),
        _node(id: 2, parentId: 1, siblingIndex: 0),
        _node(id: 3, parentId: 1, siblingIndex: 1),
        _node(id: 4, parentId: 1, siblingIndex: 2),
      ]));

      // Swap 2 and 4: 4 becomes sibling 0, 2 becomes sibling 2.
      // Also update bounds on 4.
      model.applyDiff(_diff(moved: [
        _node(
            id: 4,
            parentId: 1,
            siblingIndex: 0,
            minX: 5,
            minY: 5,
            maxX: 15,
            maxY: 15),
        _node(id: 2, parentId: 1, siblingIndex: 2),
      ], childrenUpdated: const [
        SemanticsChildrenUpdate(parentId: 1, childIds: [4, 3, 2]),
      ]));

      expect(model.nodeById(1)?.children, [4, 3, 2]);
      expect(model.nodeById(4)?.minX, 5);
      expect(model.nodeById(4)?.maxY, 15);

      model.dispose();
    });

    test('updatedSemantic patches content fields only, not bounds', () {
      final model = SemanticTreeModel();

      model.applyDiff(_diff(added: [
        _node(
          id: 1,
          parentId: -1,
          role: SemanticRole.button,
          label: 'old',
          minX: 0,
          minY: 0,
          maxX: 100,
          maxY: 50,
        ),
      ]));

      model.applyDiff(_diff(updatedSemantic: [
        _node(
          id: 1,
          parentId: -1,
          role: SemanticRole.link,
          label: 'new label',
          value: 'val',
          hint: 'tap it',
          stateFlags: 0x10,
          traitFlags: 0x20,
          headingLevel: 3,
          // NOTE: stale bounds intentionally supplied; must be ignored.
          minX: 999,
          minY: 999,
          maxX: 999,
          maxY: 999,
        ),
      ]));

      final n = model.nodeById(1)!;
      expect(n.role, SemanticRole.link);
      expect(n.label, 'new label');
      expect(n.value, 'val');
      expect(n.hint, 'tap it');
      expect(n.stateFlags, 0x10);
      expect(n.traitFlags, 0x20);
      expect(n.headingLevel, 3);
      // Bounds preserved from the initial payload.
      expect(n.minX, 0);
      expect(n.maxX, 100);
      expect(n.maxY, 50);

      model.dispose();
    });

    test('updatedGeometry patches bounds only, not content', () {
      final model = SemanticTreeModel();

      model.applyDiff(_diff(added: [
        _node(
          id: 1,
          parentId: -1,
          role: SemanticRole.button,
          label: 'stable',
          stateFlags: 0x3,
          minX: 0,
          minY: 0,
          maxX: 10,
          maxY: 10,
        ),
      ]));

      model.applyDiff(_diff(updatedGeometry: const [
        SemanticsBoundsUpdate(
            id: 1, minX: 100, minY: 200, maxX: 300, maxY: 400),
      ]));

      final n = model.nodeById(1)!;
      expect(n.minX, 100);
      expect(n.minY, 200);
      expect(n.maxX, 300);
      expect(n.maxY, 400);
      // Content preserved.
      expect(n.role, SemanticRole.button);
      expect(n.label, 'stable');
      expect(n.stateFlags, 0x3);

      model.dispose();
    });

    test('childrenUpdated rewrites child order; ids not in model are filtered',
        () {
      final model = SemanticTreeModel();

      //    1
      //    ├── 2
      //    └── 3
      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1),
        _node(id: 2, parentId: 1, siblingIndex: 0),
        _node(id: 3, parentId: 1, siblingIndex: 1),
      ]));

      // Reorder to [3, 2] and include a stale id 99 that should be filtered.
      model.applyDiff(_diff(childrenUpdated: const [
        SemanticsChildrenUpdate(parentId: 1, childIds: [3, 2, 99]),
      ]));

      expect(model.nodeById(1)?.children, [3, 2]);

      model.dispose();
    });

    test('childrenUpdated with parentId -1 rewrites roots', () {
      final model = SemanticTreeModel();

      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1, siblingIndex: 0),
        _node(id: 2, parentId: -1, siblingIndex: 1),
        _node(id: 3, parentId: -1, siblingIndex: 2),
      ]));
      expect(model.roots, [1, 2, 3]);

      model.applyDiff(_diff(childrenUpdated: const [
        SemanticsChildrenUpdate(parentId: -1, childIds: [3, 1, 2]),
      ]));

      expect(model.roots, [3, 1, 2]);
      expect(model.nodeById(3)?.parentId, -1);

      model.dispose();
    });

    test('updatedSemantic for an unknown id is silently ignored', () {
      final model = SemanticTreeModel();

      model.applyDiff(_diff(added: [_node(id: 1, parentId: -1)]));

      // 42 was never added — must not throw, must not create a phantom entry.
      model.applyDiff(_diff(updatedSemantic: [
        _node(id: 42, parentId: -1, label: 'ghost'),
      ]));

      expect(model.nodeCount, 1);
      expect(model.nodeById(42), isNull);

      model.dispose();
    });

    test('flattened() returns nodes in depth-first pre-order with depth', () {
      final model = SemanticTreeModel();

      //    1           depth 0
      //    ├── 2       depth 1
      //    │   └── 4   depth 2
      //    └── 3       depth 1
      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1),
        _node(id: 2, parentId: 1, siblingIndex: 0),
        _node(id: 3, parentId: 1, siblingIndex: 1),
        _node(id: 4, parentId: 2, siblingIndex: 0),
      ]));

      final flat = model.flattened();
      expect(flat.map((r) => r.node.id), [1, 2, 4, 3]);
      expect(flat.map((r) => r.depth), [0, 1, 2, 1]);

      model.dispose();
    });

    test('full lifecycle: add → update → move → remove', () {
      final model = SemanticTreeModel();

      // Add a list with two items.
      model.applyDiff(_diff(added: [
        _node(id: 1, parentId: -1, role: SemanticRole.list),
        _node(
            id: 2,
            parentId: 1,
            siblingIndex: 0,
            role: SemanticRole.listItem,
            label: 'A'),
        _node(
            id: 3,
            parentId: 1,
            siblingIndex: 1,
            role: SemanticRole.listItem,
            label: 'B'),
      ]));
      expect(model.nodeCount, 3);

      // Update label on 2.
      model.applyDiff(_diff(updatedSemantic: [
        _node(id: 2, parentId: 1, role: SemanticRole.listItem, label: 'A2'),
      ]));
      expect(model.nodeById(2)?.label, 'A2');

      // Move 3 above 2.
      model.applyDiff(_diff(
        moved: [
          _node(id: 3, parentId: 1, siblingIndex: 0),
          _node(id: 2, parentId: 1, siblingIndex: 1),
        ],
        childrenUpdated: const [
          SemanticsChildrenUpdate(parentId: 1, childIds: [3, 2]),
        ],
      ));
      expect(model.nodeById(1)?.children, [3, 2]);

      // Remove 2.
      model.applyDiff(_diff(removed: const [2]));
      expect(model.nodeCount, 2);
      expect(model.nodeById(2), isNull);
      expect(model.nodeById(1)?.children, [3]);

      expect(model.version, 4);

      model.dispose();
    });
  });
}
