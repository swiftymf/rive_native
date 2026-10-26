import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

import '../src/utils.dart';

/// data_binding_lists_items.riv — an artboard with a component of
/// role=list that hosts dynamically-created listItem artboards via data
/// binding. Exercises the path where list item state machines are created
/// after the parent artboard's initial buildSemanticTree and therefore
/// must be reparented under the enclosing list role node (rather than
/// added as roots, which would violate Flutter's assertion that
/// listItem roles must live under a list role).

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

    final bytes = loadFile('assets/semantic/data_binding_lists_items.riv');
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

  List<SemanticNodeData> get lists => model
      .flattened()
      .map((r) => r.node)
      .where((n) => n.role == SemanticRole.list)
      .toList();

  List<SemanticNodeData> get items => model
      .flattened()
      .map((r) => r.node)
      .where((n) => n.role == SemanticRole.listItem)
      .toList();

  /// Walk ancestors of [node] (excluding self) via parentId and return them
  /// in order from nearest to farthest. Stops at a root (parentId < 0).
  List<SemanticNodeData> ancestorsOf(SemanticNodeData node) {
    final out = <SemanticNodeData>[];
    var current = node.parentId;
    while (current >= 0) {
      final parent = model.nodeById(current);
      if (parent == null) break;
      out.add(parent);
      current = parent.parentId;
    }
    return out;
  }

  void dispose() {
    model.dispose();
    sm.dispose();
    artboard.dispose();
    file.dispose();
  }
}

void main() {
  test('exposes a list-role node and at least one listItem-role node',
      () async {
    final s = await _Setup.create();

    expect(s.lists, hasLength(1),
        reason: 'fixture should have exactly one list-role node');
    expect(s.items, isNotEmpty,
        reason: 'fixture should populate at least one listItem-role node');

    s.dispose();
  });

  test('listItem nodes are not roots', () async {
    final s = await _Setup.create();

    expect(s.items, isNotEmpty);
    for (final item in s.items) {
      expect(item.parentId, isNot(lessThan(0)),
          reason: 'listItem "${item.label}" (id=${item.id}) should not be a '
              'root — Flutter requires listItem roles to live under a list '
              'role parent');
      expect(s.model.roots, isNot(contains(item.id)),
          reason: 'listItem "${item.label}" (id=${item.id}) should not appear '
              'in tree roots');
    }

    s.dispose();
  });

  test('every listItem has a list-role ancestor', () async {
    final s = await _Setup.create();

    final listIds = s.lists.map((n) => n.id).toSet();
    expect(listIds, isNotEmpty);

    for (final item in s.items) {
      final ancestors = s.ancestorsOf(item);
      final hasListAncestor = ancestors.any((a) => listIds.contains(a.id));
      expect(hasListAncestor, isTrue,
          reason: 'listItem "${item.label}" (id=${item.id}) must have a '
              'list-role ancestor; ancestor roles were '
              '${ancestors.map((a) => '${a.id}:${a.role}').toList()}');
    }

    s.dispose();
  });
}
