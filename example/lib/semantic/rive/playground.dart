// ignore_for_file: experimental_member_use

import 'package:example/rive_player.dart';
import 'package:flutter/material.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

class SemanticDemoRivePlayground extends StatefulWidget {
  const SemanticDemoRivePlayground({super.key});

  @override
  State<SemanticDemoRivePlayground> createState() =>
      _SemanticDemoRivePlaygroundState();
}

class _SemanticDemoRivePlaygroundState
    extends State<SemanticDemoRivePlayground> {
  rive.Artboard? _artboard;
  rive.StateMachinePainter? _painter;

  void _onArtboard(rive.Artboard artboard) {
    setState(() => _artboard = artboard);
  }

  void _onPainter(rive.StateMachinePainter painter) {
    setState(() => _painter = painter);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RivePlayer(
            asset: 'assets/semantic_list_scroll_focus_fixed.riv',
            // asset: 'assets/simpsons.riv',
            withArtboard: _onArtboard,
            withPainter: _onPainter,
            semanticsEnabled: true,
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final model = _painter?.semanticTree;
              if (model == null) {
                return const Center(child: Text('No semantic tree yet'));
              }
              return SemanticDebugOverlay(
                model: model,
                artboardBounds: _artboard?.worldBounds,
              );
            },
          ),
        ),
      ],
    );
  }
}
