// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

/// Helper class to manage common test setup and assertions for nested input tests
class NestedInputTestHelper {
  late rive.Artboard artboard;
  late rive.StateMachine stateMachine;
  late int requestAdvanceCount;
  late void Function() requestAdvanceCallback;

  void setupArtboardAndStateMachine(rive.File riveFile) {
    artboard = riveFile.defaultArtboard()!;
    expect(artboard, isNotNull);
    stateMachine = artboard.defaultStateMachine()!;
    expect(stateMachine, isNotNull);
  }

  void setupRequestAdvanceListener() {
    requestAdvanceCount = 0;
    requestAdvanceCallback = () {
      requestAdvanceCount++;
    };
    stateMachine.addAdvanceRequestListener(requestAdvanceCallback);
  }

  // Waits for and verifies the request advance was called
  // Each call to an input will trigger a request advance
  void verifyRequestAdvanceCalled({String? reason}) {
    expect(requestAdvanceCount, 1, reason: reason);
  }

  void cleanup() {
    stateMachine.removeAdvanceRequestListener(requestAdvanceCallback);
  }

  /// Runs a complete test with setup, execution, and cleanup
  Future<void> runTest(
    Future<void> Function() testAction, {
    String? reason,
  }) async {
    setupRequestAdvanceListener();
    await testAction();
    verifyRequestAdvanceCalled(reason: reason);
    cleanup();
  }
}

void main() {
  late rive.File riveFile;
  late NestedInputTestHelper helper;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final riveBytes = loadFile('assets/runtime_nested_inputs.riv');
    riveFile =
        await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
            as rive.File;
    helper = NestedInputTestHelper();
    helper.setupArtboardAndStateMachine(riveFile);
  });

  test('Nested boolean input can be get/set', () async {
    await helper.runTest(() async {
      final boolean =
          helper.stateMachine.boolean("CircleOuterState", path: "CircleOuter");
      expect(boolean, isNotNull);
      expect(boolean!.value, false);
      boolean.value = true;
      expect(boolean.value, true);
    },
        reason:
            'Request advance should be called on the state machine after the boolean value is set');
  });

  test('Nested number input can be get/set', () async {
    await helper.runTest(() async {
      final num =
          helper.stateMachine.number("CircleOuterNumber", path: "CircleOuter");
      expect(num, isNotNull);
      expect(num!.value, 0);
      num.value = 99;
      expect(num.value, 99);
    },
        reason:
            'Request advance should be called on the state machine after the number value is set');
  });

  test('Nested trigger can be get/fired', () async {
    await helper.runTest(() async {
      final trigger = helper.stateMachine
          .trigger("CircleOuterTrigger", path: "CircleOuter");
      expect(trigger, isNotNull);
      expect(() => trigger!.fire(), returnsNormally);
    },
        reason:
            'Request advance should be called on the state machine after the trigger is fired');
  });

  test('Nested boolean input can be get/set multiple levels deep', () async {
    await helper.runTest(() async {
      final boolean = helper.stateMachine
          .boolean("CircleInnerState", path: "CircleOuter/CircleInner");
      expect(boolean, isNotNull);
      expect(boolean!.value, false);
      boolean.value = true;
      expect(boolean.value, true);
    },
        reason:
            'Request advance should be called on the state machine after the boolean value is set');
  });

  test('Number of inputs in state machine', () async {
    final inputs = helper.stateMachine.inputs;
    expect(inputs.length, 1);
    expect(inputs.map((e) => e.name).toList(), ['MainBool']);

    final anotherFile = await rive.File.decode(
        loadFile('assets/skins_demo.riv'),
        riveFactory: rive.Factory.flutter);
    final moreInputs =
        anotherFile?.defaultArtboard()?.defaultStateMachine()?.inputs;
    expect(moreInputs, isNotNull);
    expect(moreInputs!.length, 2);
    expect(moreInputs.map((e) => e.name).toList(), ['Skin', 'Number 1']);
  });
}
