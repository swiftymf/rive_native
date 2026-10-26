import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

void main() {
  late rive.File riveFile;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final riveBytes = loadFile('assets/off_road_car.riv');
    riveFile =
        await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
            as rive.File;
  });

  test('Artboad and StateMachine name getter', () async {
    final artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);
    expect(artboard!.name, 'New Artboard');
    final stateMachine = artboard.defaultStateMachine();
    expect(stateMachine, isNotNull);
    expect(stateMachine!.name, 'State Machine 1');
    final animation = artboard.animationAt(0);
    expect(animation, isNotNull);
    expect(animation.name, 'idle');
  });
}
