import '../rive_player.dart';
import 'package:flutter/material.dart';

class ExampleBasic extends StatefulWidget {
  const ExampleBasic({super.key});

  @override
  State<ExampleBasic> createState() => _ExampleBasicState();
}

class _ExampleBasicState extends State<ExampleBasic> {
  @override
  Widget build(BuildContext context) {
    return RivePlayer(
      asset: "assets/rating.riv",
      stateMachineName: "State Machine 1",
      withStateMachine: (sm) {
        // Find the number rating and set it to 3
        // ignore: deprecated_member_use
        var ratingInput = sm.number("rating")!;
        ratingInput.value = 3;
        // Other inputs:
        // var trigger = sm.trigger("sometrigger");
        // var boolean = sm.boolean("someboolean");
      },
    );
  }
}
