import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

import '../src/utils.dart';

/// tabtest.riv — Row with three tappable children. On tap, sets
/// enumProperty to "all", "child", or "parent". Each child becomes
/// selected. The Row has a TabList semantic, each child has a Tab semantic.

class _TabTestSetup {
  final rive.File file;
  final rive.Artboard artboard;
  final rive.StateMachine sm;
  final rive.ViewModelInstance viewModelInstance;
  final SemanticTreeModel model;

  _TabTestSetup({
    required this.file,
    required this.artboard,
    required this.sm,
    required this.viewModelInstance,
    required this.model,
  });

  static Future<_TabTestSetup> create() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final bytes = loadFile('assets/semantic/tabtest.riv');
    final file =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(file, isNotNull);

    final artboard = file!.defaultArtboard();
    expect(artboard, isNotNull);

    final sm = artboard!.defaultStateMachine();
    expect(sm, isNotNull);
    sm!.enableSemantics();

    final viewModel = file.defaultArtboardViewModel(artboard);
    expect(viewModel, isNotNull, reason: 'View model must exist');
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

    return _TabTestSetup(
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

  String? get enumValue => viewModelInstance.enumerator('enumProperty')?.value;

  List<SemanticNodeData> get tabs => model
      .flattened()
      .map((r) => r.node)
      .where((n) => n.role == SemanticRole.tab)
      .toList();

  /// Simulates a pointer tap at the center of a semantic node's bounds.
  void tapNodePointer(SemanticNodeData node) {
    final center = rive.Vec2D.fromValues(
      (node.minX + node.maxX) / 2,
      (node.minY + node.maxY) / 2,
    );
    sm.pointerDown(center);
    sm.pointerUp(center);
    settle();
  }

  /// Mimics the widget's semantic tap: fires the semantic action AND
  /// simulates a pointer down/up at the node center. On web the semantic
  /// DOM overlay intercepts clicks before they reach the canvas, so the
  /// pointer simulation ensures regular state machine listeners fire.
  void tapNodeSemantic(SemanticNodeData node) {
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
  test('tabtest.riv has expected semantic structure', () async {
    final setup = await _TabTestSetup.create();

    final flat = setup.model.flattened();
    expect(flat, isNotEmpty);

    final tabLists = flat
        .map((r) => r.node)
        .where((n) => n.role == SemanticRole.tabList)
        .toList();
    expect(tabLists, hasLength(1));

    expect(setup.tabs, hasLength(3));
    expect(setup.tabs.map((t) => t.label),
        containsAll(['All', 'Parent', 'Child']));

    // "All" tab should be initially selected (stateFlags bit 1 = Selected).
    final allTab = setup.tabs.firstWhere((t) => t.label == 'All');
    expect(
      SemanticState.has(allTab.stateFlags, SemanticState.selected),
      isTrue,
      reason: '"All" tab should be initially selected',
    );

    setup.dispose();
  });

  test('pointer tap on tab triggers state machine', () async {
    final setup = await _TabTestSetup.create();

    expect(setup.enumValue, equals('All'));

    final parentTab = setup.tabs.firstWhere((t) => t.label == 'Parent');
    setup.tapNodePointer(parentTab);
    expect(setup.enumValue, equals('Parent'));

    final childTab = setup.tabs.firstWhere((t) => t.label == 'Child');
    setup.tapNodePointer(childTab);
    expect(setup.enumValue, equals('Child'));

    setup.dispose();
  });

  test('semantic tap on tab triggers state machine', () async {
    final setup = await _TabTestSetup.create();

    expect(setup.enumValue, equals('All'));

    final parentTab = setup.tabs.firstWhere((t) => t.label == 'Parent');
    setup.tapNodeSemantic(parentTab);
    expect(setup.enumValue, equals('Parent'),
        reason:
            'Semantic tap should trigger state machine via pointer simulation');

    final childTab = setup.tabs.firstWhere((t) => t.label == 'Child');
    setup.tapNodeSemantic(childTab);
    expect(setup.enumValue, equals('Child'));

    setup.dispose();
  });
}
