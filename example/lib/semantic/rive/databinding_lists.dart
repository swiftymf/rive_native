import 'package:example/rive_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../app.dart';

class SemanticDemoRiveDatabindingLists extends StatefulWidget {
  const SemanticDemoRiveDatabindingLists({super.key});

  @override
  State<SemanticDemoRiveDatabindingLists> createState() =>
      _SemanticDemoRiveDatabindingListsState();
}

class _SemanticDemoRiveDatabindingListsState
    extends State<SemanticDemoRiveDatabindingLists> {
  rive.ViewModelInstanceList? _menuList;
  rive.ViewModel? _listItemViewModel;
  rive.File? _viewModelSourceFile;

  String filename = 'data_binding_lists.riv';

  final TextEditingController _addController = TextEditingController();
  final TextEditingController _updateIndexController = TextEditingController();
  final TextEditingController _updateTextController = TextEditingController();
  final TextEditingController _deleteController = TextEditingController();
  final TextEditingController _swapFirstController = TextEditingController();
  final TextEditingController _swapSecondController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadListItemViewModel();
  }

  Future<void> _loadListItemViewModel() async {
    final bytes = await rootBundle.load('assets/$filename');
    _viewModelSourceFile = await rive.File.decode(
      bytes.buffer.asUint8List(),
      riveFactory: RiveExampleApp.getCurrentFactory,
    );
    _listItemViewModel = _viewModelSourceFile?.viewModelByName('listItem');
    if (mounted) setState(() {});
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  rive.ViewModelInstanceString? _labelPropertyFor(
    rive.ViewModelInstance instance,
  ) {
    return instance.string('label') ?? instance.string('name');
  }

  void _onLoadedViewModel(rive.ViewModelInstance viewModelInstance) {
    // RivePlayer invokes this while building the painter, so avoid calling
    // setState synchronously during that build phase.
    if (_menuList != null) return;
    _menuList = viewModelInstance.list('menu');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onAdd() {
    final list = _menuList;
    final vm = _listItemViewModel;
    if (list == null || vm == null) {
      _showError('List data is not ready yet.');
      return;
    }

    final text = _addController.text.trim();
    if (text.isEmpty) return;

    final item = vm.createInstance();
    if (item == null) {
      _showError('Failed to create list item instance.');
      return;
    }

    final labelProperty = _labelPropertyFor(item);
    if (labelProperty == null) {
      _showError('List item has no label/name string property.');
      item.dispose();
      return;
    }

    labelProperty.value = text;
    list.add(item);
    item.dispose();
    _addController.clear();
    setState(() {});
  }

  void _onUpdate() {
    final list = _menuList;
    if (list == null) {
      _showError('List data is not ready yet.');
      return;
    }

    final index = int.tryParse(_updateIndexController.text.trim());
    final text = _updateTextController.text.trim();
    if (index == null || text.isEmpty) return;

    try {
      final instance = list.instanceAt(index);
      final labelProperty = _labelPropertyFor(instance);
      if (labelProperty == null) {
        _showError('Item has no label/name string property.');
        return;
      }
      labelProperty.value = text;
      setState(() {});
    } catch (error) {
      _showError('Update failed: $error');
    }
  }

  void _onDelete() {
    final list = _menuList;
    if (list == null) {
      _showError('List data is not ready yet.');
      return;
    }

    final index = int.tryParse(_deleteController.text.trim());
    if (index == null) return;

    try {
      list.removeAt(index);
      setState(() {});
    } catch (error) {
      _showError('Delete failed: $error');
    }
  }

  void _onSwap() {
    final list = _menuList;
    if (list == null) {
      _showError('List data is not ready yet.');
      return;
    }

    final first = int.tryParse(_swapFirstController.text.trim());
    final second = int.tryParse(_swapSecondController.text.trim());
    if (first == null || second == null) return;

    try {
      list.swap(first, second);
      setState(() {});
    } catch (error) {
      _showError('Swap failed: $error');
    }
  }

  @override
  void dispose() {
    _addController.dispose();
    _updateIndexController.dispose();
    _updateTextController.dispose();
    _deleteController.dispose();
    _swapFirstController.dispose();
    _swapSecondController.dispose();
    _viewModelSourceFile?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rive Semantic Data Binding Lists')),
      body: Column(
        children: [
          Expanded(
            child: RivePlayer(
              asset: 'assets/$filename',
              semanticsEnabled: true,
              withViewModelInstance: _onLoadedViewModel,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _menuList == null
                      ? 'Loading list...'
                      : 'Current item count: ${_menuList!.length}',
                ),
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
                        onSubmitted: (_) => _onAdd(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _onAdd, child: const Text('Add')),
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
                        onSubmitted: (_) => _onUpdate(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _onUpdate,
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
                      onPressed: _onSwap,
                      child: const Text('Swap'),
                    ),
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
                        onSubmitted: (_) => _onDelete(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _onDelete,
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
        ],
      ),
    );
  }
}
