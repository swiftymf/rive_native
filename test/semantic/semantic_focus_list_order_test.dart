import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

import '../src/utils.dart';

/// focus_nodes_list_order.riv — four button nodes authored at root level at
/// distinct vertical positions. The file is shaped so the top-to-bottom
/// visual order (minY = 0, 75, 150, 225) disagrees with the
/// manager-local id-assignment order (the bottom-most button has the
/// smallest id), locking in that the tree exposes nodes in visual order.

class _ExpectedSlot {
  const _ExpectedSlot(this.minX, this.minY, this.maxX, this.maxY);
  final double minX, minY, maxX, maxY;
}

const _expectedSlots = <_ExpectedSlot>[
  _ExpectedSlot(0.0, 0.0, 122.0, 59.0),
  _ExpectedSlot(0.0, 75.0, 122.0, 134.0),
  _ExpectedSlot(0.0, 150.0, 122.0, 209.0),
  _ExpectedSlot(0.0, 225.0, 500.0, 500.0),
];

class _Setup {
  final rive.File file;
  final rive.Artboard artboard;
  final rive.StateMachine sm;
  final SemanticTreeModel model;

  _Setup._({
    required this.file,
    required this.artboard,
    required this.sm,
    required this.model,
  });

  static Future<_Setup> create() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final bytes = loadFile('assets/semantic/focus_nodes_list_order.riv');
    final file =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(file, isNotNull);

    final artboard = file!.defaultArtboard();
    expect(artboard, isNotNull);

    final sm = artboard!.defaultStateMachine();
    expect(sm, isNotNull);
    sm!.enableSemantics();

    final viewModel = file.defaultArtboardViewModel(artboard);
    final vmi = viewModel?.createDefaultInstance();
    if (vmi != null) {
      artboard.bindViewModelInstance(vmi);
      sm.bindViewModelInstance(vmi);
    }

    for (var i = 0; i < 10; i++) {
      sm.advanceAndApply(0.1);
    }

    final model = SemanticTreeModel();
    model.applyDiff(sm.drainSemanticsDiff());

    return _Setup._(
      file: file,
      artboard: artboard,
      sm: sm,
      model: model,
    );
  }

  void dispose() {
    model.dispose();
    sm.dispose();
    artboard.dispose();
    file.dispose();
  }
}

void main() {
  test(
      'focus_nodes_list_order.riv: four root buttons are exposed in '
      'top-to-bottom visual order with expected bounds', () async {
    final s = await _Setup.create();

    final roots = s.model.roots
        .map((id) => s.model.flattened()
            .firstWhere((r) => r.node.id == id)
            .node)
        .toList();

    expect(roots, hasLength(_expectedSlots.length));

    for (var i = 0; i < _expectedSlots.length; i++) {
      final n = roots[i];
      final expected = _expectedSlots[i];
      expect(n.role, SemanticRole.button,
          reason: 'slot $i (id=${n.id}) role');
      expect(n.parentId, -1, reason: 'slot $i (id=${n.id}) parentId');
      expect(n.minX, closeTo(expected.minX, 0.001),
          reason: 'slot $i (id=${n.id}) minX');
      expect(n.minY, closeTo(expected.minY, 0.001),
          reason: 'slot $i (id=${n.id}) minY');
      expect(n.maxX, closeTo(expected.maxX, 0.001),
          reason: 'slot $i (id=${n.id}) maxX');
      expect(n.maxY, closeTo(expected.maxY, 0.001),
          reason: 'slot $i (id=${n.id}) maxY');
    }

    s.dispose();
  });

  test(
      'focus_nodes_list_order.riv: bottom button has the smallest id so '
      'ordering is genuinely driven by bounds, not insertion order',
      () async {
    // Guards the above test's meaningfulness: if the fixture is ever
    // re-authored so id order matches visual order, the ordering test
    // degenerates into trivial insertion-order check.
    final s = await _Setup.create();

    final rootIds = s.model.roots;
    expect(rootIds, hasLength(_expectedSlots.length));
    final minId = rootIds.reduce((a, b) => a < b ? a : b);
    expect(rootIds.last, minId,
        reason: 'bottom-most (last) root should carry the smallest id');

    s.dispose();
  });
}
