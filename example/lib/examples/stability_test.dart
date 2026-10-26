import 'package:example/app.dart';
import 'package:rive_native/rive_native.dart';

import 'package:flutter/material.dart';

class StabilityTest extends StatefulWidget {
  const StabilityTest({super.key});

  @override
  State<StabilityTest> createState() => _StabilityTestState();
}

class _StabilityTestState extends State<StabilityTest> {
  File? _riveFile;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _riveFile = await File.asset(
      'assets/little_machine.riv',
      riveFactory: RiveExampleApp.getCurrentFactory,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final file = _riveFile;
    if (file == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
          _rivePlayer(Factory.rive, file),
        ],
      ),
    );
  }

  Widget _rivePlayer(Factory riveFactory, File file) {
    return SizedBox(
      width: 100,
      height: 100,
      child: _MyRive(
        riveFile: file,
      ),
    );
  }
}

class _MyRive extends StatefulWidget {
  const _MyRive({required this.riveFile});

  final File riveFile;

  @override
  State<_MyRive> createState() => _MyRiveState();
}

class _MyRiveState extends State<_MyRive> {
  late final Artboard? _artboard;
  final painter = StateMachinePainter();

  @override
  void initState() {
    super.initState();
    _artboard = widget.riveFile.defaultArtboard();
  }

  @override
  Widget build(BuildContext context) {
    if (_artboard == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RiveArtboardWidget(
      artboard: _artboard,
      painter: painter,
    );
  }
}
