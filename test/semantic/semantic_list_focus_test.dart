import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

import '../src/utils.dart';

/// semantic_list_scroll_focus_fixed.riv — a list of focusable cards wired
/// into the focus system. The viewport shows five items labelled
/// "Element 1"…"Element 5"; semantically requesting focus on an item sets
/// its Focused state, and focusing the bottom-most slot scrolls the list
/// so every visible item's bounds shift upward.

const _visibleSlots = 5;

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

    final bytes =
        loadFile('assets/semantic/semantic_list_scroll_focus_fixed.riv');
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
    final vmi = viewModel!.createDefaultInstance()!;
    artboard.bindViewModelInstance(vmi);
    sm.bindViewModelInstance(vmi);

    for (var i = 0; i < 10; i++) {
      sm.advanceAndApply(0.1);
    }

    final model = SemanticTreeModel();
    final initial = sm.drainSemanticsDiff();
    if (initial.isNotEmpty) {
      model.applyDiff(initial);
    }

    return _Setup._(
      file: file,
      artboard: artboard,
      sm: sm,
      viewModelInstance: vmi,
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

  List<SemanticNodeData> get items => model
      .flattened()
      .map((r) => r.node)
      .where((n) => n.role == SemanticRole.listItem)
      .toList();

  SemanticNodeData? itemByLabel(String label) => items.firstWhere(
        (n) => n.label == label,
        orElse: () => throw StateError('no list item labelled "$label"'),
      );

  void dispose() {
    model.dispose();
    sm.dispose();
    artboard.dispose();
    file.dispose();
  }
}

void main() {
  test(
      'semantic_list_scroll_focus_fixed.riv exposes one list with five '
      'labelled list items', () async {
    final s = await _Setup.create();

    final lists = s.model
        .flattened()
        .map((r) => r.node)
        .where((n) => n.role == SemanticRole.list)
        .toList();
    expect(lists, hasLength(1), reason: 'fixture should have one list');

    final items = s.items;
    expect(items, hasLength(_visibleSlots));
    for (var i = 1; i <= _visibleSlots; i++) {
      final label = 'Element $i';
      expect(items.where((n) => n.label == label), hasLength(1),
          reason: 'list should contain "$label"');
    }

    s.dispose();
  });

  test(
      'semantic_list_scroll_focus_fixed.riv list items expose the Focusable '
      'trait', () async {
    final s = await _Setup.create();

    for (var i = 1; i <= _visibleSlots; i++) {
      final item = s.itemByLabel('Element $i');
      expect(
        SemanticTrait.has(item!.traitFlags, SemanticTrait.focusable),
        isTrue,
        reason: '"${item.label}" should carry the Focusable trait',
      );
    }

    s.dispose();
  });

  test(
      'semantic_list_scroll_focus_fixed.riv: focusSemanticNode sets '
      'Focused only on the target item', () async {
    final s = await _Setup.create();

    final target = s.itemByLabel('Element 3')!;
    final ok = s.sm.focusSemanticNode(target.id);
    expect(ok, isTrue);
    s.settle();

    for (var i = 1; i <= _visibleSlots; i++) {
      final item = s.itemByLabel('Element $i')!;
      final focused =
          SemanticState.has(item.stateFlags, SemanticState.focused);
      if (i == 3) {
        expect(focused, isTrue,
            reason: '"${item.label}" should carry Focused after requestFocus');
      } else {
        expect(focused, isFalse,
            reason: '"${item.label}" should not carry Focused');
      }
    }

    s.dispose();
  });

  test(
      'semantic_list_scroll_focus_fixed.riv: moving focus hands the Focused '
      'bit between items', () async {
    final s = await _Setup.create();

    s.sm.focusSemanticNode(s.itemByLabel('Element 1')!.id);
    s.settle();
    expect(
      SemanticState.has(
          s.itemByLabel('Element 1')!.stateFlags, SemanticState.focused),
      isTrue,
    );
    expect(
      SemanticState.has(
          s.itemByLabel('Element 3')!.stateFlags, SemanticState.focused),
      isFalse,
    );

    s.sm.focusSemanticNode(s.itemByLabel('Element 3')!.id);
    s.settle();
    expect(
      SemanticState.has(
          s.itemByLabel('Element 1')!.stateFlags, SemanticState.focused),
      isFalse,
    );
    expect(
      SemanticState.has(
          s.itemByLabel('Element 3')!.stateFlags, SemanticState.focused),
      isTrue,
    );

    s.dispose();
  });

  test(
      'semantic_list_scroll_focus_fixed.riv: focusing the bottom slot '
      'scrolls the list (all items shift upward)', () async {
    final s = await _Setup.create();

    // Snapshot each slot's starting Y so we can assert a uniform shift.
    final startMinY = <int, double>{
      for (var i = 1; i <= _visibleSlots; i++)
        s.itemByLabel('Element $i')!.id: s.itemByLabel('Element $i')!.minY,
    };

    s.sm.focusSemanticNode(s.itemByLabel('Element $_visibleSlots')!.id);
    s.settle();

    for (var i = 1; i <= _visibleSlots; i++) {
      final item = s.itemByLabel('Element $i')!;
      final before = startMinY[item.id]!;
      expect(item.minY, lessThan(before),
          reason: '"${item.label}" minY should decrease after scroll '
              '(before=$before, after=${item.minY})');
    }

    s.dispose();
  });
}
