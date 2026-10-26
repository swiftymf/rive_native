import 'package:flutter/material.dart';

class SemanticDemoFlutterLists extends StatefulWidget {
  const SemanticDemoFlutterLists({super.key});

  @override
  State<SemanticDemoFlutterLists> createState() =>
      _SemanticDemoFlutterListsState();
}

class _SemanticDemoFlutterListsState extends State<SemanticDemoFlutterLists> {
  static const List<int> _itemCountOptions = [10, 25, 50, 100, 250, 500, 1000];
  int _selectedItemCount = 100;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleColor = colorScheme.onSurface;
    final subtitleColor = colorScheme.onSurfaceVariant;
    final tileColor = colorScheme.surfaceContainerHighest;

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Semantic Lists')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('Number of list items:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _selectedItemCount,
                    items: _itemCountOptions
                        .map(
                          (count) => DropdownMenuItem<int>(
                            value: count,
                            child: Text('$count'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedItemCount = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                interactive: true,
                thickness: 6,
                thumbVisibility: true,
                radius: const Radius.circular(3),
                child: ListView.builder(
                  addSemanticIndexes: true,
                  semanticChildCount: _selectedItemCount,
                  itemCount: _selectedItemCount,
                  itemBuilder: (context, index) {
                    final number = index + 1;
                    return _SemanticListItem(
                      number: number,
                      totalItems: _selectedItemCount,
                      tileColor: tileColor,
                      titleColor: titleColor,
                      subtitleColor: subtitleColor,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SemanticListItem extends StatefulWidget {
  const _SemanticListItem({
    required this.number,
    required this.totalItems,
    required this.tileColor,
    required this.titleColor,
    required this.subtitleColor,
  });

  final int number;
  final int totalItems;
  final Color tileColor;
  final Color titleColor;
  final Color subtitleColor;

  @override
  State<_SemanticListItem> createState() => _SemanticListItemState();
}

class _SemanticListItemState extends State<_SemanticListItem> {
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final focusedTileColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.18),
      widget.tileColor,
    );

    return ListTile(
      focusNode: _focusNode,
      onFocusChange: (hasFocus) {
        if (_hasFocus == hasFocus) return;
        setState(() {
          _hasFocus = hasFocus;
        });
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: _hasFocus ? focusedTileColor : widget.tileColor,
      title: Text(
        'Item ${widget.number}',
        style: TextStyle(color: widget.titleColor),
      ),
      subtitle: Text(
        'Semantic test content for item ${widget.number}',
        style: TextStyle(color: widget.subtitleColor),
      ),
      trailing: _hasFocus
          ? Icon(Icons.center_focus_strong, color: colorScheme.primary)
          : null,
      onTap: () {
        _focusNode.requestFocus();
      },
    );
  }
}
