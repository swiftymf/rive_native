// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

void main() {
  late rive.File riveFile;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final riveBytes = loadFile('assets/rating.riv');
    riveFile =
        await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
            as rive.File;
  });

  test('onStateChanged is called with state names when setting inputs and advancing', () async {
    final artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);
    final stateMachine = artboard!.stateMachine('State Machine 1');
    expect(stateMachine, isNotNull);

    final stateChanges = <String>[];
    final handler =
        stateMachine!.onStateChanged((stateName) => stateChanges.add(stateName));
    addTearDown(handler.dispose);

    final rating = stateMachine.number('rating');
    expect(rating, isNotNull);

    // Set rating and advance; each transition should report via onStateChanged
    final sequence = [3, 4, 3, 2, 1, 2, 3];
    for (final value in sequence) {
      rating!.value = value.toDouble();
      stateMachine.advanceAndApply(0.016);
    }

    const expected = [
      '3_stars',
      '4_stars',
      '3_stars',
      '2_stars',
      '1_star',
      '2_stars',
      '3_stars',
    ];
    expect(stateChanges, expected);
  });
}
