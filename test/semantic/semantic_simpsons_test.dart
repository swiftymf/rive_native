import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

import '../src/utils.dart';

class _Setup {
  final String filename;
  final rive.File file;
  final rive.Artboard artboard;
  final rive.StateMachine sm;
  final rive.ViewModelInstance viewModelInstance;
  final SemanticTreeModel model;

  _Setup({
    required this.filename,
    required this.file,
    required this.artboard,
    required this.sm,
    required this.viewModelInstance,
    required this.model,
  });

  static Future<_Setup> create(String filename) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final bytes = loadFile('assets/semantic/$filename');
    final file =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(file, isNotNull, reason: '$filename should decode');

    final artboard = file!.defaultArtboard();
    expect(artboard, isNotNull, reason: '$filename should have artboard');

    final sm = artboard!.defaultStateMachine();
    expect(sm, isNotNull, reason: '$filename should have state machine');
    sm!.enableSemantics();

    final viewModel = file.defaultArtboardViewModel(artboard);
    expect(viewModel, isNotNull, reason: '$filename should have view model');
    final viewModelInstance = viewModel!.createDefaultInstance()!;
    artboard.bindViewModelInstance(viewModelInstance);
    sm.bindViewModelInstance(viewModelInstance);

    for (var i = 0; i < 10; i++) {
      sm.advanceAndApply(0.1);
    }

    final model = SemanticTreeModel();
    final initialDiff = sm.drainSemanticsDiff();
    if (initialDiff.isNotEmpty) {
      model.applyDiff(initialDiff);
    }

    return _Setup(
      filename: filename,
      file: file,
      artboard: artboard,
      sm: sm,
      viewModelInstance: viewModelInstance,
      model: model,
    );
  }

  void settle() {
    for (var i = 0; i < 10; i++) {
      sm.advanceAndApply(0.1);
    }
    final diff = sm.drainSemanticsDiff();
    if (diff.isNotEmpty) {
      model.applyDiff(diff);
    }
  }

  List<SemanticNodeData> get tabs => model
      .flattened()
      .map((r) => r.node)
      .where((n) => n.role == SemanticRole.tab)
      .toList();

  void tapPointer(SemanticNodeData node) {
    final center = rive.Vec2D.fromValues(
      (node.minX + node.maxX) / 2,
      (node.minY + node.maxY) / 2,
    );
    sm.pointerDown(center);
    sm.pointerUp(center);
    settle();
  }

  void tapSemantic(SemanticNodeData node) {
    sm.fireSemanticAction(node.id, rive.SemanticActionType.tap);
    settle();
  }

  /// Combined tap: semantic action + pointer (what the widget does).
  void tapWidget(SemanticNodeData node) {
    sm.fireSemanticAction(node.id, rive.SemanticActionType.tap);
    final center = rive.Vec2D.fromValues(
      (node.minX + node.maxX) / 2,
      (node.minY + node.maxY) / 2,
    );
    sm.pointerDown(center);
    sm.pointerUp(center);
    settle();
  }

  void dispose() {
    model.dispose();
    sm.dispose();
    artboard.dispose();
    file.dispose();
  }
}

void main() {
  test('simpsons.riv has expected semantic tree structure', () async {
    final setup = await _Setup.create('simpsons.riv');

    final flat = setup.model.flattened();
    expect(flat, isNotEmpty, reason: 'Semantic tree should not be empty');

    // Should contain a tab list.
    final tabLists = flat
        .map((r) => r.node)
        .where((n) => n.role == SemanticRole.tabList)
        .toList();
    expect(tabLists, hasLength(1), reason: 'Should have exactly one tab list');

    // Should have multiple tabs with non-empty labels.
    final tabs = setup.tabs;
    expect(tabs.length, greaterThanOrEqualTo(2),
        reason: 'Should have at least 2 tabs');
    for (final tab in tabs) {
      expect(tab.label, isNotEmpty,
          reason: 'Tab ${tab.id} should have a label');
    }

    // Exactly one tab should be initially selected.
    final selectedTabs = tabs
        .where((t) => SemanticState.has(t.stateFlags, SemanticState.selected))
        .toList();
    expect(selectedTabs, hasLength(1),
        reason: 'Exactly one tab should be initially selected');

    setup.dispose();
  });

  test('simpsons.riv pointer tap changes selected tab', () async {
    final setup = await _Setup.create('simpsons.riv');

    final tabs = setup.tabs;
    expect(tabs.length, greaterThanOrEqualTo(2));

    // Find the initially selected tab and a different one.
    final initiallySelected = tabs.firstWhere(
        (t) => SemanticState.has(t.stateFlags, SemanticState.selected));
    final other = tabs.firstWhere((t) => t.id != initiallySelected.id);

    // Pointer-tap the other tab.
    setup.tapPointer(other);

    // The other tab should now be selected.
    final updatedOther = setup.model.nodeById(other.id);
    expect(updatedOther, isNotNull);
    expect(
      SemanticState.has(updatedOther!.stateFlags, SemanticState.selected),
      isTrue,
      reason: '"${other.label}" should be selected after pointer tap',
    );

    // The originally selected tab should no longer be selected.
    final updatedInitial = setup.model.nodeById(initiallySelected.id);
    expect(updatedInitial, isNotNull);
    expect(
      SemanticState.has(updatedInitial!.stateFlags, SemanticState.selected),
      isFalse,
      reason: '"${initiallySelected.label}" should be deselected after tapping '
          '"${other.label}"',
    );

    setup.dispose();
  });

  test('simpsons.riv semantic tap produces same result as pointer tap',
      () async {
    // Create two independent setups so state doesn't carry over.
    final pointerSetup = await _Setup.create('simpsons.riv');
    final semanticSetup = await _Setup.create('simpsons.riv');

    final pointerTabs = pointerSetup.tabs;
    final semanticTabs = semanticSetup.tabs;
    expect(pointerTabs.length, greaterThanOrEqualTo(2));
    expect(semanticTabs.length, equals(pointerTabs.length));

    // Tap the second tab via pointer on one setup, and via semantic on
    // the other.
    final pointerTarget = pointerTabs[1];
    final semanticTarget =
        semanticTabs.firstWhere((t) => t.label == pointerTarget.label);

    pointerSetup.tapPointer(pointerTarget);
    semanticSetup.tapSemantic(semanticTarget);

    // Both should produce the same selected state on every tab.
    for (var i = 0; i < pointerTabs.length; i++) {
      final pNode = pointerSetup.model.nodeById(pointerTabs[i].id);
      final sNode = semanticSetup.model.nodeById(semanticTabs[i].id);
      expect(pNode, isNotNull);
      expect(sNode, isNotNull);

      final pSelected =
          SemanticState.has(pNode!.stateFlags, SemanticState.selected);
      final sSelected =
          SemanticState.has(sNode!.stateFlags, SemanticState.selected);
      expect(
        sSelected,
        equals(pSelected),
        reason: 'Tab "${pointerTabs[i].label}" selection should match between '
            'pointer tap ($pSelected) and semantic tap ($sSelected)',
      );
    }

    pointerSetup.dispose();
    semanticSetup.dispose();
  });

  test('simpsons.riv tabs filter the list below them into distinct counts',
      () async {
    // Fixture authoring: three tabs ("Parents" / "Children" / "All" or
    // similar) swap which authored cards are shown in the list below. The
    // counts are 2, 3, and 5 in some order.
    final setup = await _Setup.create('simpsons.riv');

    // Fixture must expose a single list container.
    final lists = setup.model
        .flattened()
        .map((r) => r.node)
        .where((n) => n.role == SemanticRole.list)
        .toList();
    expect(lists, hasLength(1), reason: 'simpsons.riv should have one list');

    final tabs = setup.tabs;
    expect(tabs, hasLength(3), reason: 'simpsons.riv should have 3 tabs');

    int listItemCount() => setup.model
        .flattened()
        .map((r) => r.node)
        .where((n) => n.role == SemanticRole.listItem)
        .length;

    final counts = <int>[];
    for (final tab in tabs) {
      setup.tapWidget(tab);
      counts.add(listItemCount());
    }
    counts.sort();

    expect(counts, equals(<int>[2, 3, 5]),
        reason: 'Each tab should filter the list to its authored count; '
            'observed (sorted) counts were $counts');

    setup.dispose();
  });

  test('tabtest.riv widget tap selects tabs', () async {
    final setup = await _Setup.create('tabtest.riv');

    final flat = setup.model.flattened();
    expect(flat, isNotEmpty);

    final tabs = setup.tabs;
    expect(tabs.length, greaterThanOrEqualTo(2),
        reason: 'tabtest.riv should have at least 2 tabs');

    // Record which tab is initially selected.
    final initiallySelected = tabs.firstWhere(
        (t) => SemanticState.has(t.stateFlags, SemanticState.selected));

    // Widget-tap each non-selected tab and verify it becomes selected.
    for (final tab in tabs) {
      if (tab.id == initiallySelected.id) continue;

      setup.tapWidget(tab);

      final updated = setup.model.nodeById(tab.id);
      expect(updated, isNotNull);
      expect(
        SemanticState.has(updated!.stateFlags, SemanticState.selected),
        isTrue,
        reason: '"${tab.label}" should be selected after widget tap',
      );

      // Previous selection should be cleared — only one tab selected.
      final allSelected = setup.tabs
          .where((t) => SemanticState.has(t.stateFlags, SemanticState.selected))
          .toList();
      expect(allSelected, hasLength(1),
          reason: 'Only one tab should be selected after tapping '
              '"${tab.label}"');
    }

    setup.dispose();
  });
}
