import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';
import 'package:rive_native/src/semantics/rive_semantics_test_helpers.dart';

import '../src/utils.dart';

/// data_binding_lists.riv — Main artboard with a data-bound list of
/// listItem artboards. The "main" view model has a "menu" list property.
/// Each listItem component has a text node with an inferred label.

const _dropdownLabel = 'Select a fandom';
const _expectedFandomLabels = <String>{
  'War of the Stars',
  'Scufflestar Galactica',
  'Galaxy Hike',
  'Dino Planet',
};

class _DataBindingListSetup {
  final rive.File file;
  final rive.Artboard artboard;
  final rive.StateMachine sm;
  final rive.ViewModelInstance viewModelInstance;
  final SemanticTreeModel model;

  _DataBindingListSetup({
    required this.file,
    required this.artboard,
    required this.sm,
    required this.viewModelInstance,
    required this.model,
  });

  static Future<_DataBindingListSetup> create() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final bytes = loadFile('assets/semantic/data_binding_lists.riv');
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

    return _DataBindingListSetup(
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

  SemanticNodeData dropdownButtonNode() {
    return model.flattened().map((r) => r.node).firstWhere(
        (n) => n.role == SemanticRole.button && n.label == _dropdownLabel);
  }

  bool get isDropdownExpanded {
    final button = dropdownButtonNode();
    return SemanticTrait.has(button.traitFlags, SemanticTrait.expandable) &&
        SemanticState.has(button.stateFlags, SemanticState.expanded);
  }

  Set<String> get fandomLabelNodes => model
      .flattened()
      .where((r) =>
          r.node.role == SemanticRole.text &&
          _expectedFandomLabels.contains(r.node.label))
      .map((r) => r.node.label)
      .toSet();

  void tapDropdownButton() {
    final button = dropdownButtonNode();
    final center = rive.Vec2D.fromValues(
      (button.minX + button.maxX) / 2,
      (button.minY + button.maxY) / 2,
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
  // ---------------------------------------------------------------------------
  // Model-level tests
  // ---------------------------------------------------------------------------

  test('dropdown button starts expanded and exposes four fandom label nodes',
      () async {
    final s = await _DataBindingListSetup.create();

    expect(s.dropdownButtonNode().label, equals(_dropdownLabel));
    expect(s.isDropdownExpanded, isTrue,
        reason: 'Dropdown should start with Expanded=true');
    expect(s.fandomLabelNodes, equals(_expectedFandomLabels),
        reason: 'Expanded dropdown should expose all four fandom labels');

    s.dispose();
  });

  test('tapping dropdown button sets Expanded=false and removes fandom labels',
      () async {
    final s = await _DataBindingListSetup.create();

    expect(s.isDropdownExpanded, isTrue);
    expect(s.fandomLabelNodes, equals(_expectedFandomLabels));

    s.tapDropdownButton();

    expect(s.isDropdownExpanded, isFalse,
        reason: 'Tap should collapse dropdown and clear Expanded state');
    expect(s.fandomLabelNodes, isEmpty,
        reason:
            'Fandom labels should not remain in semantic tree when collapsed');

    s.dispose();
  });

  test(
      'collapse → uncollapse → re-collapse cycle removes fandom labels each time',
      () async {
    final s = await _DataBindingListSetup.create();

    // Initial: expanded with all fandom labels.
    expect(s.isDropdownExpanded, isTrue);
    expect(s.fandomLabelNodes, equals(_expectedFandomLabels));

    // First collapse.
    s.tapDropdownButton();
    expect(s.isDropdownExpanded, isFalse);
    expect(s.fandomLabelNodes, isEmpty,
        reason: 'First collapse should remove all fandom labels');

    // Uncollapse (re-expand).
    s.tapDropdownButton();
    expect(s.isDropdownExpanded, isTrue,
        reason: 'Second tap should re-expand the dropdown');
    expect(s.fandomLabelNodes, equals(_expectedFandomLabels),
        reason: 'Re-expand should restore all fandom labels');

    // Re-collapse.
    s.tapDropdownButton();
    expect(s.isDropdownExpanded, isFalse);
    expect(s.fandomLabelNodes, isEmpty,
        reason: 'Re-collapse should remove all fandom labels again');

    s.dispose();
  });

  // ---------------------------------------------------------------------------
  // Widget-level test
  // ---------------------------------------------------------------------------

  testWidgets(
      'semantic tap collapses dropdown and removes fandom labels from Flutter tree',
      (tester) async {
    final handle = tester.ensureSemantics();

    // Set up file, artboard, and view model — but let the painter create
    // the only state machine to avoid a dual-SM conflict.
    final bytes = loadFile('assets/semantic/data_binding_lists.riv');
    final file =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(file, isNotNull);

    final artboard = file!.defaultArtboard();
    expect(artboard, isNotNull);

    final viewModel = file.defaultArtboardViewModel(artboard!);
    expect(viewModel, isNotNull, reason: 'View model must exist');
    final viewModelInstance = viewModel!.createDefaultInstance()!;
    artboard.bindViewModelInstance(viewModelInstance);

    final painter = rive.RivePainter.stateMachine(
      withStateMachine: (machine) {
        machine.bindViewModelInstance(viewModelInstance);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 400,
            child: rive.RiveSemanticsWidget(
              artboard: artboard,
              painter: painter,
              child: rive.RiveArtboardWidget(
                artboard: artboard,
                painter: painter,
              ),
            ),
          ),
        ),
      ),
    );

    // Pump several frames to let semantics settle.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final overlay = find.byType(RiveSemanticsOverlay);
    expect(overlay, findsOneWidget);

    final root = tester.getSemantics(overlay);

    final dropdownButton = root.findByLabelPattern(_dropdownLabel);
    expect(dropdownButton, isNotNull,
        reason: 'Should find dropdown button in Flutter semantics tree');
    expect(isSemanticsButton(dropdownButton!), isTrue);
    expect(
      dropdownButton.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'Dropdown button should expose a tap action',
    );

    for (final label in _expectedFandomLabels) {
      expect(root.findByLabel(label), isNotNull,
          reason: 'Expected "$label" while dropdown is expanded');
    }

    tester.renderObject(overlay).owner!.semanticsOwner!
        .performAction(dropdownButton.id, SemanticsAction.tap);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final updatedRoot = tester.getSemantics(overlay);
    final updatedDropdown = updatedRoot.findByLabelPattern(_dropdownLabel);
    expect(updatedDropdown, isNotNull);
    expect(
      updatedDropdown!.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    for (final label in _expectedFandomLabels) {
      expect(updatedRoot.findByLabel(label), isNull,
          reason: '"$label" should not be in semantic tree when collapsed');
    }

    painter.dispose();
    artboard.dispose();
    file.dispose();
    handle.dispose();
  });
}
