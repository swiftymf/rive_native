// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

void main() {
  late rive.File riveFile;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final riveBytes = loadFile('assets/audio_event.riv');
    riveFile =
        await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
            as rive.File;
  });

  test('AudioRuntimeEvent fires while the state machine plays', () async {
    final artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);
    final stateMachine = artboard!.defaultStateMachine();
    expect(stateMachine, isNotNull);

    final observedEvents = <rive.Event>[];
    stateMachine!.addEventListener(observedEvents.add);

    // Play the state machine for up to ~500 ms in 16 ms steps. The audio event
    // is expected to fire within the first few advances.
    const stepSeconds = 0.016;
    const maxSteps = 32;
    var steps = 0;
    while (observedEvents.whereType<rive.AudioRuntimeEvent>().isEmpty &&
        steps < maxSteps) {
      stateMachine.advanceAndApply(stepSeconds);
      steps++;
    }

    final audioEvents =
        observedEvents.whereType<rive.AudioRuntimeEvent>().toList();
    expect(audioEvents, isNotEmpty,
        reason: 'Expected audio_event.riv to emit an AudioEvent within '
            '${maxSteps * stepSeconds}s of playback. Saw: $observedEvents');

    final audioEvent = audioEvents.first;
    expect(audioEvent, isA<rive.AudioRuntimeEvent>());
    expect(audioEvent.type, rive.EventType.audio);
    expect(audioEvent.name, 'Event');
    expect(audioEvent.secondsDelay, greaterThanOrEqualTo(0.0));
    expect(audioEvent.properties, isEmpty);

    // The fixture's audio event references an embedded audio asset.
    expect(audioEvent.assetId, 0);
    expect(audioEvent.assetName, 'Balloon Leaking Air Out Fast Flubery');
    expect(audioEvent.volume, 1.0);
  });
}
