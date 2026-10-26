import 'package:flutter/material.dart';

class SemanticDemoFlutterDropDownLists extends StatefulWidget {
  const SemanticDemoFlutterDropDownLists({super.key});

  @override
  State<SemanticDemoFlutterDropDownLists> createState() =>
      _SemanticDemoFlutterDropDownListsState();
}

class _SemanticDemoFlutterDropDownListsState
    extends State<SemanticDemoFlutterDropDownLists> {
  final List<String> _items = <String>[
    'War of the Stars',
    'Scufflestar Galactica',
    'Galaxy Hike',
    'Dino Planet',
  ];

  bool _isOpen = false;
  int? _selectedIndex;

  final TextEditingController _addController = TextEditingController();
  final TextEditingController _updateIndexController = TextEditingController();
  final TextEditingController _updateTextController = TextEditingController();
  final TextEditingController _deleteController = TextEditingController();
  final TextEditingController _swapFirstController = TextEditingController();
  final TextEditingController _swapSecondController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    _updateIndexController.dispose();
    _updateTextController.dispose();
    _deleteController.dispose();
    _swapFirstController.dispose();
    _swapSecondController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleOpen() {
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  void _selectIndex(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  void _addItem() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(text);
      _selectedIndex ??= 0;
    });
    _addController.clear();
  }

  void _updateItem() {
    final index = int.tryParse(_updateIndexController.text.trim());
    final text = _updateTextController.text.trim();
    if (index == null || text.isEmpty) return;
    if (index < 0 || index >= _items.length) {
      _showError('Update failed: index out of range.');
      return;
    }
    setState(() {
      _items[index] = text;
    });
  }

  void _deleteItem() {
    final index = int.tryParse(_deleteController.text.trim());
    if (index == null) return;
    if (index < 0 || index >= _items.length) {
      _showError('Delete failed: index out of range.');
      return;
    }

    setState(() {
      _items.removeAt(index);
      if (_items.isEmpty) {
        _selectedIndex = null;
      } else if (_selectedIndex != null) {
        if (_selectedIndex == index) {
          _selectedIndex = null;
        } else if (_selectedIndex! > index) {
          _selectedIndex = _selectedIndex! - 1;
        }
      }
    });
  }

  void _swapItems() {
    final first = int.tryParse(_swapFirstController.text.trim());
    final second = int.tryParse(_swapSecondController.text.trim());
    if (first == null || second == null) return;
    if (first < 0 ||
        second < 0 ||
        first >= _items.length ||
        second >= _items.length) {
      _showError('Swap failed: index out of range.');
      return;
    }
    if (first == second) return;

    setState(() {
      final temp = _items[first];
      _items[first] = _items[second];
      _items[second] = temp;

      if (_selectedIndex == first) {
        _selectedIndex = second;
      } else if (_selectedIndex == second) {
        _selectedIndex = first;
      }
    });
  }

  String get _headerLabel {
    if (_selectedIndex == null ||
        _selectedIndex! < 0 ||
        _selectedIndex! >= _items.length) {
      return 'Select a fandom';
    }
    return _items[_selectedIndex!];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Semantic Dropdown List')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border:
                    Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    container: true,
                    button: true,
                    expanded: _isOpen,
                    excludeSemantics: true,
                    label: _isOpen
                        ? 'Collapse fandom options'
                        : 'Expand fandom options',
                    onTap: _toggleOpen,
                    child: ExcludeSemantics(
                      child: InkWell(
                        onTap: _toggleOpen,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _headerLabel,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Icon(
                                _isOpen
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_isOpen) const Divider(height: 1),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final selected = _selectedIndex == index;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        title: Text(_items[index]),
                        onTap: () => _selectIndex(index),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Current item count: ${_items.length}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(
                      labelText: 'Add item text',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _addItem, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _updateIndexController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Update index',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _updateTextController,
                    decoration: const InputDecoration(
                      labelText: 'New text',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _updateItem(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _updateItem,
                  child: const Text('Update'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _swapFirstController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Swap index A',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _swapSecondController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Swap index B',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _swapItems, child: const Text('Swap')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deleteController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Delete index',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _deleteItem(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _deleteItem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
