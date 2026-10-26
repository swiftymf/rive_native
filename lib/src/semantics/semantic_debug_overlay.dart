import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:rive_native/math.dart';
import 'package:rive_native/src/semantics/semantic_tree_model.dart';

/// A debug panel that renders the live semantic tree below a Rive widget.
///
/// Wrap or stack this alongside a Rive rendering widget. It listens to [model]
/// and rebuilds automatically whenever the tree changes.
///
/// ```dart
/// Column(
///   children: [
///     SizedBox(height: 300, child: myRiveWidget),
///     Expanded(
///       child: SemanticDebugOverlay(
///         model: _semanticModel,
///         artboardBounds: _artboard?.worldBounds,
///       ),
///     ),
///   ],
/// )
/// ```
@experimental
@internal
class SemanticDebugOverlay extends StatelessWidget {
  const SemanticDebugOverlay({
    required this.model,
    this.artboardBounds,
    super.key,
  });

  final SemanticTreeModel model;

  /// When provided, displays the artboard dimensions in the header row.
  final AABB? artboardBounds;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => _DebugPanel(
        model: model,
        artboardBounds: artboardBounds,
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.model, this.artboardBounds});

  final SemanticTreeModel model;
  final AABB? artboardBounds;

  @override
  Widget build(BuildContext context) {
    final bounds = artboardBounds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: Row(
            children: [
              Text(
                'Semantic tree — ${model.nodeCount} nodes',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (bounds != null)
                Text(
                  'artboard: ${bounds.width.toStringAsFixed(0)}'
                  'x${bounds.height.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ),
        Expanded(
          child: model.nodeCount == 0
              ? const Center(
                  child: Text(
                    'No semantic nodes yet.\n'
                    'Load a .riv file with SemanticData components.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _SemanticTreeListView(model: model),
        ),
      ],
    );
  }
}

class _SemanticTreeListView extends StatelessWidget {
  const _SemanticTreeListView({required this.model});

  final SemanticTreeModel model;

  @override
  Widget build(BuildContext context) {
    final rows = model.flattened();
    if (rows.isEmpty) {
      return const Center(child: Text('Empty tree'));
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final label =
            row.node.label.isEmpty ? '<no label>' : '"${row.node.label}"';
        return Padding(
          padding: EdgeInsets.only(
            left: 12.0 + row.depth * 16.0,
            top: 2,
            bottom: 2,
            right: 8,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade700,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  row.node.role.name,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'id=${row.node.id} $label  '
                  '${row.node.boundsString}',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
