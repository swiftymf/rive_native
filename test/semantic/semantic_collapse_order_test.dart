import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

import '../src/utils.dart';

/// Validates that semantic node ordering follows visual position after
/// collapse / uncollapse cycles in data_binding_lists.riv.
///
/// The artboard has a dropdown button ("Select a fandom") that collapses
/// and uncollapses a list of four fandom items. The button is above the
/// list items. After collapse→uncollapse, the button must still appear
/// before all list items in the semantic traversal order.

const _dropdownLabel = 'Select a fandom';
const _fandomLabels = [
  'War of the Stars',
  'Scufflestar Galactica',
  'Galaxy Hike',
  'Dino Planet',
];

class _Setup {
  final rive.File file;
  final rive.Artboard artboard;
  final rive.StateMachine sm;
  final rive.ViewModelInstance viewModelInstance;
  final SemanticTreeModel model;

  _Setup._({
    required this.file,
    required this.artboard,
    required this.sm,
    required this.viewModelInstance,
    required this.model,
  });

  static Future<_Setup> create() async {
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
    expect(viewModel, isNotNull);
    final viewModelInstance = viewModel!.createDefaultInstance()!;
    artboard.bindViewModelInstance(viewModelInstance);
    sm.bindViewModelInstance(viewModelInstance);

    // Settle initial state — enough frames for layout + first diff.
    for (var i = 0; i < 10; i++) {
      sm.advanceAndApply(0.1);
    }

    final model = SemanticTreeModel();
    final initialDiff = sm.drainSemanticsDiff();
    if (initialDiff.isNotEmpty) {
      model.applyDiff(initialDiff);
    }

    return _Setup._(
      file: file,
      artboard: artboard,
      sm: sm,
      viewModelInstance: viewModelInstance,
      model: model,
    );
  }

  /// Advance enough frames to settle layout + animation, applying
  /// incremental diffs each frame so the model stays current.
  void settle({int frames = 30, double dt = 0.05}) {
    for (var i = 0; i < frames; i++) {
      sm.advanceAndApply(dt);
      final diff = sm.drainSemanticsDiff();
      if (diff.isNotEmpty) {
        model.applyDiff(diff);
      }
    }
  }

  SemanticNodeData? findButton() {
    return model
        .flattened()
        .map((r) => r.node)
        .where(
            (n) => n.role == SemanticRole.button && n.label == _dropdownLabel)
        .firstOrNull;
  }

  List<SemanticNodeData> findFandomItems() {
    return model
        .flattened()
        .map((r) => r.node)
        .where((n) =>
            n.role == SemanticRole.text && _fandomLabels.contains(n.label))
        .toList();
  }

  /// Returns all nodes in depth-first traversal order. Used to check
  /// relative ordering of the button among the fandom items.
  List<SemanticNodeData> traversalOrder() {
    return model.flattened().map((r) => r.node).toList();
  }

  void tapDropdownButton() {
    final button = findButton()!;
    final center = rive.Vec2D.fromValues(
      (button.minX + button.maxX) / 2,
      (button.minY + button.maxY) / 2,
    );
    sm.pointerDown(center);
    sm.pointerUp(center);
    // Settle with many frames to let the animation complete (1s animation).
    settle(frames: 60, dt: 0.05);
  }

  void dispose() {
    model.dispose();
    sm.dispose();
    artboard.dispose();
    file.dispose();
  }
}

/// Given the flat traversal order, extract the position of the dropdown
/// button relative to the fandom labels. Returns the index of the button
/// among the set of [button + fandom labels], or -1 if not found.
///
/// For example, if traversal is [button, War, Scufflestar, Galaxy, Dino],
/// the button position is 0 (correct — it's first).
/// If traversal is [War, Scufflestar, button, Galaxy, Dino],
/// the button position is 2 (wrong — it's in the middle).
int buttonPositionAmongItems(List<SemanticNodeData> traversal) {
  final relevantLabels = {_dropdownLabel, ..._fandomLabels};
  final filtered =
      traversal.where((n) => relevantLabels.contains(n.label)).toList();
  for (var i = 0; i < filtered.length; i++) {
    if (filtered[i].label == _dropdownLabel) return i;
  }
  return -1;
}

void main() {
  test('initial expanded state: button is before all fandom items', () async {
    final s = await _Setup.create();

    final button = s.findButton();
    expect(button, isNotNull, reason: 'Dropdown button must exist');
    expect(
        SemanticState.has(button!.stateFlags, SemanticState.expanded), isTrue,
        reason: 'Dropdown should start expanded');

    final items = s.findFandomItems();
    expect(items.length, 4, reason: 'All four fandom items should be present');

    // Button Y should be less than all item Ys.
    for (final item in items) {
      expect(button.minY, lessThan(item.minY),
          reason:
              'Button (y=${button.minY}) should be above "${item.label}" (y=${item.minY})');
    }

    // In traversal order, button should come first.
    final pos = buttonPositionAmongItems(s.traversalOrder());
    expect(pos, 0,
        reason: 'Button should be first in traversal order (position $pos)');

    s.dispose();
  });

  test('after collapse→uncollapse: button is still before all fandom items',
      () async {
    final s = await _Setup.create();

    // Verify initial state.
    expect(s.findFandomItems().length, 4);
    expect(buttonPositionAmongItems(s.traversalOrder()), 0);

    // Collapse.
    s.tapDropdownButton();
    expect(s.findButton(), isNotNull);
    expect(s.findFandomItems(), isEmpty,
        reason: 'Fandom items should be gone after collapse');

    // Uncollapse.
    s.tapDropdownButton();

    final button = s.findButton();
    expect(button, isNotNull, reason: 'Button must exist after uncollapse');
    expect(
        SemanticState.has(button!.stateFlags, SemanticState.expanded), isTrue,
        reason: 'Should be expanded again');

    final items = s.findFandomItems();
    expect(items.length, 4, reason: 'All four fandom items must reappear');

    // Button Y should still be less than all item Ys.
    for (final item in items) {
      expect(button.minY, lessThan(item.minY),
          reason: 'After uncollapse: button (y=${button.minY}) should be above '
              '"${item.label}" (y=${item.minY})');
    }

    // In traversal order, button should still come first.
    final pos = buttonPositionAmongItems(s.traversalOrder());
    expect(pos, 0,
        reason: 'After uncollapse: button should be first in traversal order '
            '(got position $pos)');

    s.dispose();
  });

  test('multiple collapse→uncollapse cycles maintain correct order', () async {
    final s = await _Setup.create();

    for (var cycle = 0; cycle < 3; cycle++) {
      // Collapse.
      s.tapDropdownButton();
      expect(s.findFandomItems(), isEmpty,
          reason: 'Cycle $cycle collapse: items should be gone');

      // Uncollapse.
      s.tapDropdownButton();

      final items = s.findFandomItems();
      expect(items.length, 4,
          reason: 'Cycle $cycle uncollapse: all items must reappear');

      final pos = buttonPositionAmongItems(s.traversalOrder());
      expect(pos, 0,
          reason: 'Cycle $cycle: button should be first in traversal order '
              '(got position $pos)');
    }

    s.dispose();
  });

  test('fandom items are in top-to-bottom visual order after uncollapse',
      () async {
    final s = await _Setup.create();

    // Collapse then uncollapse.
    s.tapDropdownButton();
    s.tapDropdownButton();

    final items = s.findFandomItems();
    expect(items.length, 4);

    // Items should be in ascending Y order (matching _fandomLabels order).
    for (var i = 1; i < items.length; i++) {
      expect(items[i].minY, greaterThanOrEqualTo(items[i - 1].minY),
          reason:
              '"${items[i].label}" (y=${items[i].minY}) should not be above '
              '"${items[i - 1].label}" (y=${items[i - 1].minY})');
    }

    s.dispose();
  });
}
