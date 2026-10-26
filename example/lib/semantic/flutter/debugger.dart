// ignore_for_file: experimental_member_use

import 'package:example/app.dart';
import 'package:flutter/material.dart';
import 'package:rive_native/semantics.dart';

/// Example host for [SemanticDebugger].
///
/// The asset / artboard / state-machine inputs live in a modal dialog so
/// they're only in the widget tree when the user opens the configure sheet.
/// This keeps them out of the main view's semantic tree without fighting
/// TextField's platform input channel (ExcludeSemantics + TextField is
/// unreliable on several targets because IME connects via semantics).
class SemanticDebuggerDemo extends StatefulWidget {
  const SemanticDebuggerDemo({super.key});

  @override
  State<SemanticDebuggerDemo> createState() => _SemanticDebuggerDemoState();
}

class _SemanticDebuggerDemoState extends State<SemanticDebuggerDemo> {
  String _asset = 'assets/semantic_list_scroll_focus_fixed.riv';
  String? _artboard;
  String? _stateMachine;

  Future<void> _openConfigure() async {
    final result = await showDialog<_DebuggerConfig>(
      context: context,
      builder: (_) => _ConfigureDialog(
        initialAsset: _asset,
        initialArtboard: _artboard,
        initialStateMachine: _stateMachine,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _asset = result.asset;
      _artboard = result.artboard;
      _stateMachine = result.stateMachine;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Semantic Debugger'),
        actions: [
          IconButton(
            tooltip: 'Configure',
            icon: const Icon(Icons.tune),
            onPressed: _openConfigure,
          ),
        ],
      ),
      body: SemanticDebugger(
        key: ValueKey('$_asset|$_artboard|$_stateMachine'),
        asset: _asset,
        factory: RiveExampleApp.getCurrentFactory,
        artboardName: _artboard,
        stateMachineName: _stateMachine,
      ),
    );
  }
}

class _DebuggerConfig {
  const _DebuggerConfig({
    required this.asset,
    required this.artboard,
    required this.stateMachine,
  });

  final String asset;
  final String? artboard;
  final String? stateMachine;
}

class _ConfigureDialog extends StatefulWidget {
  const _ConfigureDialog({
    required this.initialAsset,
    required this.initialArtboard,
    required this.initialStateMachine,
  });

  final String initialAsset;
  final String? initialArtboard;
  final String? initialStateMachine;

  @override
  State<_ConfigureDialog> createState() => _ConfigureDialogState();
}

class _ConfigureDialogState extends State<_ConfigureDialog> {
  late final _assetCtrl = TextEditingController(text: widget.initialAsset);
  late final _artboardCtrl =
      TextEditingController(text: widget.initialArtboard ?? '');
  late final _stateMachineCtrl =
      TextEditingController(text: widget.initialStateMachine ?? '');

  @override
  void dispose() {
    _assetCtrl.dispose();
    _artboardCtrl.dispose();
    _stateMachineCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final asset = _assetCtrl.text.trim();
    if (asset.isEmpty) return;
    Navigator.of(context).pop(_DebuggerConfig(
      asset: asset,
      artboard: _artboardCtrl.text.trim().isEmpty
          ? null
          : _artboardCtrl.text.trim(),
      stateMachine: _stateMachineCtrl.text.trim().isEmpty
          ? null
          : _stateMachineCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure debugger'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _assetCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Asset path',
                hintText: 'assets/...riv',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artboardCtrl,
              decoration: const InputDecoration(
                labelText: 'Artboard (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stateMachineCtrl,
              decoration: const InputDecoration(
                labelText: 'State machine (optional)',
              ),
              onSubmitted: (_) => _apply(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Load')),
      ],
    );
  }
}
