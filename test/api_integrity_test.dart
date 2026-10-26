// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/layout_engine.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/debug_symbols.dart';
import 'src/utils.dart';

void main() {
  test('can load a rive file', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/tree_loading_bar.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);
    expect(debugFileCount(), 1);

    riveFile?.dispose();
    expect(debugFileCount(), 0);
  });

  test('file lives with artboard', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/tree_loading_bar.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);
    expect(debugFileCount(), 1);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);
    expect(debugArtboardCount(), 1);

    // Dispose the file
    riveFile?.dispose();

    // Expect native to still hold onto the file as we still have an artboard
    // that references it.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);

    // Dispose the artboard and the expect the file to finally be deleted.
    artboard?.dispose();
    expect(debugArtboardCount(), 0);
    expect(debugFileCount(), 0);
  });

  test('file dies when all artboard instances die', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/tree_loading_bar.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);
    expect(debugFileCount(), 1);

    final artboardA = riveFile?.defaultArtboard();
    expect(artboardA, isNotNull);
    expect(debugArtboardCount(), 1);

    final artboardB = riveFile?.defaultArtboard();
    expect(artboardB, isNotNull);
    expect(debugArtboardCount(), 2);

    // Dispose the file
    riveFile?.dispose();

    // Expect native to still hold onto the file as we still have 2 artboards
    // that reference it.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 2);

    // Dispose artboareA, file should live on as there's still ArtboardB reffing
    // it.
    artboardA?.dispose();
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);

    // Dispose artboareA, file should live on as there's still ArtboardB reffing
    // it.
    artboardB?.dispose();
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);
  });

  test('file lives on with state machine', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/tree_loading_bar.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);
    expect(debugFileCount(), 1);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);

    final stateMachine = artboard?.stateMachine('Loading');
    expect(stateMachine, isNotNull);
    expect(debugStateMachineCount(), 1);

    // Dispose the file
    riveFile?.dispose();

    // Expect native to still hold onto the file as we still have an artboard
    // and a stateMachine that reference it.
    expect(debugFileCount(), 1);
    expect(debugStateMachineCount(), 1);

    // Dispose the artboard and state machine and expect the file to finally be
    // deleted.
    artboard?.dispose();
    expect(debugStateMachineCount(), 1);
    stateMachine?.dispose();
    expect(debugFileCount(), 0);
    expect(debugStateMachineCount(), 0);
  });

  test('file lives on with state machine', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/tree_loading_bar.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);

    final stateMachine = artboard?.stateMachine('Loading');
    expect(stateMachine, isNotNull);
    rive.NumberInput? progress = stateMachine?.number('Progress');
    expect(progress, isNotNull);
    rive.BooleanInput? downloading = stateMachine?.boolean('Downloading');
    expect(downloading, isNotNull);

    expect(progress?.value, 0.0);
    expect(downloading?.value, true);
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    stateMachine?.dispose();
    artboard?.dispose();
    riveFile?.dispose();

    // They're all still held on to from native as an input is still reffing
    // them.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    // Input is still around and can be set without throwing an exception
    // (because underlying artboard and state machine are still around in
    // native).
    progress?.value = 24;
    expect(progress?.value, 24);

    progress?.dispose();
    // Downloading input still hangs on:
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    downloading?.dispose();
    // They finally clean up.
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);
    expect(debugStateMachineCount(), 0);
  });

  test('file lives on with nested inputs referenced', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/runtime_nested_inputs.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);

    final stateMachine = artboard?.defaultStateMachine();
    expect(stateMachine, isNotNull);
    rive.BooleanInput? outer =
        stateMachine?.boolean('CircleOuterState', path: 'CircleOuter');
    expect(outer, isNotNull);
    rive.BooleanInput? inner = stateMachine?.boolean('CircleInnerState',
        path: 'CircleOuter/CircleInner');

    // All should still be active, as nothing is dipsosed.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    stateMachine?.dispose();
    artboard?.dispose();
    riveFile?.dispose();

    // They should still be held on to as both inputs are still around.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    expect(outer?.value, false);
    outer?.value = true;
    expect(outer?.value, true);
    expect(inner?.value, false);
    inner?.value = true;
    expect(inner?.value, true);

    outer?.dispose();

    // They should still be held on to as [inner] input is still around.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    inner?.dispose();

    // They should finally be cleaned up.
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);
    expect(debugStateMachineCount(), 0);
  });

  test('components delete correctly', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/rigging_a_character.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);
    expect(riveFile, isNotNull);
    riveFile?.dispose();

    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);

    final hips = artboard?.component('Hips');
    expect(hips, isNotNull);
    expect(hips?.x, 19.19441032409668);

    artboard?.dispose();

    // Even though the artboard has been disposed, native should still hold on
    // to it as we have a ref to a component.
    expect(hips?.x, 19.19441032409668);
    expect(debugArtboardCount(), 1);
    expect(debugFileCount(), 1);

    hips?.dispose();

    expect(debugArtboardCount(), 0);
    expect(debugFileCount(), 0);
  });

  test('file lives on with a reference to an event', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/events_test.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);

    final stateMachine = artboard?.defaultStateMachine();
    expect(stateMachine, isNotNull);

    rive.Event? observedEvent;

    eventCallback(rive.Event event) {
      observedEvent = event;
    }

    stateMachine!.addEventListener(eventCallback);
    final trigger = stateMachine.trigger('FireGeneralEvent');
    trigger!.fire();
    // This advance processes the fire but because we internally grab the latest events
    // before advancing the artboard, we don't catch "this frame's" events until the next
    // advance, which is why we advance twice here.
    stateMachine.advanceAndApply(0.016);
    stateMachine.advanceAndApply(0.016);
    expect(observedEvent, isNotNull);

    expect(stateMachine.eventListenerCount, 1);
    stateMachine.removeEventListener(eventCallback);
    expect(stateMachine.eventListenerCount, 0);

    // All should still be active, as nothing is dipsosed.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    stateMachine.dispose();
    artboard?.dispose();
    riveFile?.dispose();
    trigger.dispose();

    // They should still be held on to as the event is still around.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    observedEvent?.dispose();

    // They should finally be cleaned up.
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);
    expect(debugStateMachineCount(), 0);
  });

  test(
    'file lives on with a reference to an audio event',
    () async {
      expect(debugFileCount(), 0);
      final bytes = loadFile('assets/audio_event_test.riv');
      var riveFile =
          await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
      expect(riveFile, isNotNull);

      final artboard = riveFile?.defaultArtboard();
      expect(artboard, isNotNull);

      final stateMachine = artboard?.defaultStateMachine();
      expect(stateMachine, isNotNull);

      expect(debugFileCount(), 1);
      expect(debugArtboardCount(), 1);
      expect(debugStateMachineCount(), 1);

      rive.Event? observedEvent;
      void eventListener(rive.Event event) {
        observedEvent = event;
      }

      stateMachine?.addEventListener(eventListener);

      expect(stateMachine?.eventListenerCount, 1);

      final trigger = stateMachine?.trigger('playAudio');
      expect(trigger, isNotNull);
      trigger?.fire();

      const stepSeconds = 0.016;
      const maxSteps = 32;
      var steps = 0;
      while (observedEvent is! rive.AudioRuntimeEvent && steps < maxSteps) {
        stateMachine?.advanceAndApply(stepSeconds);
        steps++;
      }

      expect(observedEvent, isA<rive.AudioRuntimeEvent>(),
          reason: 'Expected an AudioRuntimeEvent within '
              '${maxSteps * stepSeconds}s of playback.');

      trigger?.dispose();

      stateMachine?.dispose();
      artboard?.dispose();
      riveFile?.dispose();

      // The retained AudioRuntimeEvent transitively keeps the
      // file/artboard/state machine alive
      expect(debugFileCount(), 1);
      expect(debugArtboardCount(), 1);
      expect(debugStateMachineCount(), 1);

      observedEvent?.dispose();

      expect(debugFileCount(), 0);
      expect(debugArtboardCount(), 0);
      expect(debugStateMachineCount(), 0);
    },
  );

  test('file lives on with a reference to an event custom property', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/events_test.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);

    final stateMachine = artboard?.defaultStateMachine();
    expect(stateMachine, isNotNull);

    rive.Event? observedEvent;
    rive.CustomNumberProperty? customNumber;
    rive.CustomBooleanProperty? customBoolean;
    rive.CustomStringProperty? customString;

    eventCallback(rive.Event event) {
      observedEvent = event;
      customNumber = event.numberProperty('SomeNumber');
      customBoolean = event.booleanProperty('SomeBoolean');
      customString = event.stringProperty('SomeString');
    }

    stateMachine!.addEventListener(eventCallback);
    final trigger = stateMachine.trigger('FireGeneralEvent');
    trigger!.fire();
    // This advance processes the fire but because we internally grab the latest events
    // before advancing the artboard, we don't catch "this frame's" events until the next
    // advance, which is why we advance twice here.
    stateMachine.advanceAndApply(0.016);
    stateMachine.advanceAndApply(0.016);
    expect(observedEvent, isNotNull);

    expect(stateMachine.eventListenerCount, 1);
    stateMachine.removeEventListener(eventCallback);
    expect(stateMachine.eventListenerCount, 0);

    expect(customNumber, isNotNull);
    expect(customBoolean, isNotNull);
    expect(customString, isNotNull);

    // All should still be active, as nothing is dipsosed.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    stateMachine.dispose();
    artboard?.dispose();
    riveFile?.dispose();
    trigger.dispose();

    // They should still be held on to as the event is still around.
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    observedEvent?.dispose();

    // They should still be held on to as there are custom properties around
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    customNumber?.dispose();
    customBoolean?.dispose();

    // One custom property is still alive...
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);
    expect(debugStateMachineCount(), 1);

    customString?.dispose();

    // They should finally be cleaned up.
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);
    expect(debugStateMachineCount(), 0);
  });

  test('FileAsset live on after file is disposed', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/out_of_band.riv');
    List<rive.ImageAsset> imageAssets = [];
    List<rive.FontAsset> fontAssets = [];
    List<rive.AudioAsset> audioAssets = [];

    var riveFile = await rive.File.decode(
      bytes,
      riveFactory: rive.Factory.flutter,
      assetLoader: (fileAsset, bytes) {
        switch (fileAsset) {
          case rive.ImageAsset imageAsset:
            imageAssets.add(imageAsset);
            break;
          case rive.FontAsset fontAsset:
            fontAssets.add(fontAsset);
            break;
          case rive.AudioAsset audioAsset:
            audioAssets.add(audioAsset);
            break;
          case rive.UnknownAsset _:
            break;
        }
        return true;
      },
    );
    expect(riveFile, isNotNull);
    expect(imageAssets.length, 3);
    expect(fontAssets.length, 3);
    expect(audioAssets.length, 3);
    expect(debugFileCount(), 1);

    // Assets should remain alive after the file is disposed
    riveFile?.dispose();
    expect(debugFileCount(), 0);

    // Validate assets are still around
    expect(imageAssets[0].assetId, 2929282);
    expect(imageAssets[1].assetId, 2929283);
    expect(imageAssets[2].assetId, 2989123);
    expect(fontAssets[0].assetId, 594377);
    expect(fontAssets[1].assetId, 593562);
    expect(fontAssets[2].assetId, 593587);
    expect(audioAssets[0].assetId, 2929275);
    expect(audioAssets[1].assetId, 2929340);
    expect(audioAssets[2].assetId, 2989208);

    final riveFactory = rive.Factory.flutter;

    // Decode font
    final fontBytes = loadFile('assets/fonts/Inter-594377.ttf');
    final font = await riveFactory.decodeFont(fontBytes);

    // Audio
    final audioBytes = loadFile('assets/audio/referenced_audio-2929340.wav');
    final audio = await riveFactory.decodeAudio(audioBytes);

    // Image
    final imageBytes = loadFile('assets/images/referenced-image-2929282.png');
    final image = await riveFactory.decodeImage(imageBytes);

    // File is disposed, assets should still be accessible
    expect(imageAssets[0].renderImage(image!), true);
    expect(fontAssets[0].font(font!), true);
    expect(audioAssets[0].audio(audio!), true);

    // Dispose assets
    imageAssets[0].dispose();
    imageAssets[1].dispose();
    imageAssets[2].dispose();
    fontAssets[0].dispose();
    fontAssets[1].dispose();
    fontAssets[2].dispose();
    audioAssets[0].dispose();
    audioAssets[1].dispose();
    audioAssets[2].dispose();

    // Asset should be diposed
    expect(imageAssets[0].assetId, 0);
    expect(imageAssets[1].assetId, 0);
    expect(imageAssets[2].assetId, 0);
    expect(fontAssets[0].assetId, 0);
    expect(fontAssets[1].assetId, 0);
    expect(fontAssets[2].assetId, 0);
    expect(audioAssets[0].assetId, 0);
    expect(audioAssets[1].assetId, 0);
    expect(audioAssets[2].assetId, 0);

    expect(debugFileCount(), 0); // should still be 0
  });

  test('View Model lives on when Rive file is disposed', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/databinding.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    var artboard = riveFile!.defaultArtboard();
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);

    expect(debugViewModelRuntimeCount(), 0);
    final viewModelByName = riveFile.viewModelByName('Person');
    final viewModelDefault = riveFile.defaultArtboardViewModel(artboard!);
    final viewModelByIndex = riveFile.viewModelByIndex(0);
    expect(debugViewModelRuntimeCount(), 3);

    artboard.dispose();
    riveFile.dispose();

    /// The reference to the view model should keep the file alive
    expect(debugFileCount(), 1);

    /// But not the artboard
    expect(debugArtboardCount(), 0);

    /// All view models should still be alive
    expect(debugViewModelRuntimeCount(), 3);

    // Dispose one view model
    viewModelByIndex!.dispose();

    /// Only two view models should still be alive
    expect(debugViewModelRuntimeCount(), 2);

    viewModelByName!.dispose();

    /// Only one view model should still be alive
    /// which should still keep the file alive
    expect(debugViewModelRuntimeCount(), 1);
    expect(debugFileCount(), 1);

    /// No view model instances
    expect(debugViewModelInstanceRuntimeCount(), 0);

    var nulVMI = viewModelByName.createInstanceByName('Gordon');

    /// Trying to create an instance from a diposed view model should return null
    expect(nulVMI, null);

    /// Instance count should still be zero
    expect(debugViewModelInstanceRuntimeCount(), 0);

    var vmiFromName = viewModelDefault!.createInstanceByName('Gordon');
    expect(vmiFromName, isNotNull);
    expect(debugViewModelInstanceRuntimeCount(), 1);

    /// Access a number property works
    expect(vmiFromName, isNotNull);
    var ageProperty = vmiFromName!.number('age');
    expect(ageProperty, isNotNull);
    expect(ageProperty!.value, 30);
    expect(debugViewModelInstanceValueRuntimeCount(), 1);

    var vmiDefault = viewModelDefault.createDefaultInstance();
    var vmiIndex = viewModelDefault.createInstanceByIndex(0);

    /// Increase/decrease vmi runtime count
    expect(debugViewModelInstanceRuntimeCount(), 3);
    vmiDefault!.dispose();
    vmiIndex!.dispose();
    expect(debugViewModelInstanceRuntimeCount(), 1);

    /// Disposing the last view model should now delete the file and view model
    viewModelDefault.dispose();
    expect(debugFileCount(), 0);
    expect(debugViewModelRuntimeCount(), 0);

    /// The `vmiPerson` should still be alive. This is not
    /// tied to the file or the view model. And can be reasigned to a different
    /// view model on a different file.
    expect(debugViewModelInstanceRuntimeCount(), 1);

    /// The `ageProperty` should still be alive
    expect(debugViewModelInstanceValueRuntimeCount(), 1);

    /// Access other properties
    var stringProperty = vmiFromName.string('name');
    expect(stringProperty, isNotNull);
    var colorProperty = vmiFromName.color('favourite_color');
    expect(colorProperty, isNotNull);
    var booleanProperty = vmiFromName.boolean('likes_popcorn');
    expect(booleanProperty, isNotNull);
    var enumProperty = vmiFromName.enumerator('favourite_pet');
    expect(enumProperty, isNotNull);

    // Runtime property instance count should now be five
    expect(debugViewModelInstanceValueRuntimeCount(), 5);

    // Accessing a view model should not increase the value count
    // but increase the instance runtime count
    var viewModelProperty = vmiFromName.viewModel('pet');
    expect(debugViewModelInstanceValueRuntimeCount(), 5);
    expect(debugViewModelInstanceRuntimeCount(), 2);

    viewModelProperty!.dispose();
    expect(debugViewModelInstanceRuntimeCount(), 1);

    /// Accessing by path should increase the value count but not
    /// the view model instance count
    var petType = vmiFromName.enumerator('pet/type');
    expect(debugViewModelInstanceValueRuntimeCount(), 6);
    expect(debugViewModelInstanceRuntimeCount(), 1);

    /// Runtime property instance count should now be one after disposing
    /// all but one property
    petType!.dispose();
    stringProperty!.dispose();
    colorProperty!.dispose();
    booleanProperty!.dispose();
    enumProperty!.dispose();
    expect(debugViewModelInstanceValueRuntimeCount(), 1);

    vmiFromName.dispose();

    /// This should still be alive as there is a property that
    /// references the view model instance
    expect(debugViewModelInstanceRuntimeCount(), 1);

    /// `ageProperty` should still be accessible
    expect(ageProperty.value, 30);
    ageProperty.dispose();

    // All properties and view model instances are disposed. Should be 0
    expect(debugViewModelInstanceRuntimeCount(), 0);

    /// This should return null as the view model instance is disposed
    var nullProp = vmiDefault.number('age');
    expect(nullProp, isNull);

    // Everything should be null
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);
    expect(debugViewModelRuntimeCount(), 0);
    expect(debugViewModelInstanceRuntimeCount(), 0);
    expect(debugViewModelInstanceValueRuntimeCount(), 0);
  });

  test('yoga nodes destroy as expected', () async {
    if (!builtWithRiveTools()) {
      return;
    }
    final layoutNode = LayoutNode.make();
    expect(debugYogaNodeCount(), 1);
    final layoutNode2 = LayoutNode.make();
    expect(debugYogaNodeCount(), 2);
    layoutNode.dispose();
    layoutNode2.dispose();
    expect(debugYogaNodeCount(), 0);

    final bytes = loadFile('assets/tree_loading_bar.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);
    expect(debugFileCount(), 1);

    {
      final artboardA = riveFile?.defaultArtboard();
      expect(artboardA, isNotNull);
      expect(debugArtboardCount(), 1);
      expect(debugYogaNodeCount(), 2);
      artboardA?.dispose();

      // One more owned by artboard in file
      expect(debugYogaNodeCount(), 1);
    }

    {
      final artboardA = riveFile?.defaultArtboard();
      expect(artboardA, isNotNull);
      expect(debugArtboardCount(), 1);
      expect(debugYogaNodeCount(), 2);
      final layout = LayoutNode.fromExternal(artboardA?.takeLayoutNode());
      final layoutNodeHost = LayoutNode.make();
      expect(debugYogaNodeCount(), 3);
      layoutNodeHost.insertChild(layout, 0);
      expect(debugYogaNodeCount(), 3);
      artboardA?.dispose();
      layout.dispose();
      expect(debugYogaNodeCount(), 3);
      riveFile?.dispose();
      // File artboard gets disposed since no artboard or file remains, but
      // layout nodes do.
      expect(debugYogaNodeCount(), 2);

      // Expected to not crash
      layoutNodeHost.calculateLayout(100, 100, LayoutDirection.ltr);
      layoutNodeHost.dispose();
      expect(debugYogaNodeCount(), 0);
    }
  });

  test('BindableArtboard lives on when Rive File is disposed', () async {
    expect(debugFileCount(), 0);
    final bytes = loadFile('assets/artboard_db_test.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);
    expect(debugFileCount(), 1);

    final artboardRed = riveFile?.artboardToBind('ArtboardRed');
    final artboardBlue = riveFile?.artboardToBind('ArtboardRed');
    final artboardGreen = riveFile?.artboardToBind('ArtboardRed');
    expect(artboardRed, isNotNull);
    expect(artboardBlue, isNotNull);
    expect(artboardGreen, isNotNull);

    expect(debugBindableArtboardCount(), 3);

    // Dispose the file
    riveFile?.dispose();

    // Expect native to still hold onto the file as we still have BindableArtboards
    expect(debugFileCount(), 1);
    expect(debugBindableArtboardCount(), 3);

    // Dispose the artboard and state machine and expect the file to finally be
    // deleted.
    artboardRed?.dispose();
    expect(debugBindableArtboardCount(), 2);
    expect(debugFileCount(), 1);
    artboardBlue?.dispose();
    expect(debugBindableArtboardCount(), 1);
    expect(debugFileCount(), 1);
    artboardGreen?.dispose();
    expect(debugBindableArtboardCount(), 0);
    expect(debugFileCount(), 0);
  });

  test('file and artboard live on with text runs referenced', () async {
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);

    final bytes = loadFile('assets/get_all_text_runs_test.riv');
    var riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull);
    expect(debugFileCount(), 1);

    final artboard = riveFile?.defaultArtboard();
    expect(artboard, isNotNull);
    expect(debugArtboardCount(), 1);

    // Get all text runs
    final textRuns = artboard!.textRuns;
    expect(textRuns.length, 10);

    // Verify initial state
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);

    // Dispose the file and artboard
    riveFile?.dispose();
    artboard.dispose();

    // File and artboard should still be alive because text runs reference them
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);

    // Text runs should still be accessible
    final firstTextRun = textRuns.firstWhere((tr) => tr.name == 'Run 1 name');
    expect(firstTextRun.text, 'run 1 value');

    // Can still modify text runs
    firstTextRun.text = 'modified value';
    expect(firstTextRun.text, 'modified value');

    // Dispose all but one text run
    for (int i = 0; i < textRuns.length - 1; i++) {
      textRuns[i].dispose();
    }

    // File and artboard should still be alive because one text run remains
    expect(debugFileCount(), 1);
    expect(debugArtboardCount(), 1);

    // Last text run should still be accessible
    final lastTextRun = textRuns.last;
    expect(lastTextRun.name, isNotEmpty);

    // Dispose the last text run
    lastTextRun.dispose();

    // Now file and artboard should finally be cleaned up
    expect(debugFileCount(), 0);
    expect(debugArtboardCount(), 0);
  });
}
