import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

void main() {
  group('Request advance tests', () {
    late rive.File riveFile;
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final riveBytes = loadFile('assets/databinding.riv');
      riveFile =
          await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
              as rive.File;
    });

    test('Request advance listeners should be correct', () async {
      final artboard = riveFile.defaultArtboard();
      expect(artboard, isNotNull);
      final stateMachine = artboard!.defaultStateMachine();
      final viewModel = riveFile.defaultArtboardViewModel(artboard);
      final viewModelInstance = viewModel!.createInstance();
      expect(viewModel, isNotNull);
      expect(stateMachine, isNotNull);
      expect(stateMachine!.numberOfAdvanceRequestListeners, 0);
      expect(viewModelInstance!.numberOfAdvanceRequestListeners, 0);
      void smRequestAdvanceCallback() {}
      void vmRequestAdvanceCallback() {}
      stateMachine.addAdvanceRequestListener(smRequestAdvanceCallback);
      viewModelInstance.addAdvanceRequestListener(vmRequestAdvanceCallback);
      expect(stateMachine.numberOfAdvanceRequestListeners, 1);
      expect(viewModelInstance.numberOfAdvanceRequestListeners, 1);

      // Should add listener to view model instance
      stateMachine.bindViewModelInstance(viewModelInstance);
      expect(stateMachine.numberOfAdvanceRequestListeners, 1);
      expect(viewModelInstance.numberOfAdvanceRequestListeners, 2);

      // Should remove listener from state machine
      stateMachine.removeAdvanceRequestListener(smRequestAdvanceCallback);
      viewModelInstance.removeAdvanceRequestListener(vmRequestAdvanceCallback);
      expect(stateMachine.numberOfAdvanceRequestListeners, 0);
      expect(viewModelInstance.numberOfAdvanceRequestListeners, 1);

      // Binding a new instance should remove the old listener
      final anotherViewModelInstance = viewModel.createInstance();
      expect(anotherViewModelInstance, isNotNull);
      expect(anotherViewModelInstance!.numberOfAdvanceRequestListeners, 0);
      stateMachine.bindViewModelInstance(anotherViewModelInstance);
      expect(stateMachine.numberOfAdvanceRequestListeners, 0,
          reason: "should still be 0");
      expect(anotherViewModelInstance.numberOfAdvanceRequestListeners, 1,
          reason: "should now be bound to the state machine");
      expect(viewModelInstance.numberOfAdvanceRequestListeners, 0,
          reason: "should now be unbound from the state machine");

      stateMachine.addAdvanceRequestListener(smRequestAdvanceCallback);
      expect(stateMachine.numberOfAdvanceRequestListeners, 1);
      // Disposing the state machine should remove the listener on the view model instance and all listeners on the state machine
      stateMachine.dispose();
      expect(stateMachine.numberOfAdvanceRequestListeners, 0);
      expect(anotherViewModelInstance.numberOfAdvanceRequestListeners, 0);

      viewModelInstance.addAdvanceRequestListener(vmRequestAdvanceCallback);
      expect(viewModelInstance.numberOfAdvanceRequestListeners, 1);
      viewModelInstance.dispose();
      // Disposing the view model instance should remove all the listeners on the view model instance
      expect(viewModelInstance.numberOfAdvanceRequestListeners, 0);
    });
  });
}
