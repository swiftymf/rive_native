import 'package:example/rive_player.dart';
import 'package:flutter/material.dart';

class SemanticDemoRiveSimpsons extends StatefulWidget {
  const SemanticDemoRiveSimpsons({super.key});

  @override
  State<SemanticDemoRiveSimpsons> createState() =>
      _SemanticDemoRiveSimpsonsState();
}

class _SemanticDemoRiveSimpsonsState extends State<SemanticDemoRiveSimpsons> {
  @override
  Widget build(BuildContext context) {
    return RivePlayer(
      asset: 'assets/simpsons.riv',
      semanticsEnabled: true,
    );
  }
}
