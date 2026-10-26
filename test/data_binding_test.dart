// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

/// Data binding images from:
/// - https://picsum.photos/id/237/200/300
/// - https://picsum.photos/id/238/200/300

final List<rive.ViewModelProperty> _viewModelPropertiesToCompare = [
  const rive.ViewModelProperty('pet', rive.DataType.viewModel),
  const rive.ViewModelProperty('jump', rive.DataType.trigger),
  const rive.ViewModelProperty('likes_popcorn', rive.DataType.boolean),
  const rive.ViewModelProperty('favourite_pet', rive.DataType.enumType),
  const rive.ViewModelProperty('favourite_color', rive.DataType.color),
  const rive.ViewModelProperty('age', rive.DataType.number),
  const rive.ViewModelProperty('website', rive.DataType.string),
  const rive.ViewModelProperty('name', rive.DataType.string),
];
final List<rive.DataEnum> _dataEnumsToCompare = [
  const rive.DataEnum('Pets', ['chipmunk', 'rat', 'frog', 'owl', 'cat', 'dog']),
];

void main() {
  late rive.File riveFile;

  setUpAll(() {
    return Future(() async {
      final bytes = loadFile('assets/databinding.riv');
      riveFile =
          await rive.File.decode(bytes, riveFactory: rive.Factory.flutter)
              as rive.File;
    });
  });

  test('view model count', () async {
    expect(riveFile.viewModelCount, 2);
  });

  test('view model file enums', () async {
    expect(riveFile.enums, _dataEnumsToCompare);
  });

  test('view model by index exists', () async {
    var viewModel = riveFile.viewModelByIndex(0);
    expect(viewModel, isNotNull);
    viewModel!.dispose();

    viewModel = riveFile.viewModelByIndex(-1);
    expect(viewModel, isNull);
  });

  test('view model by name exists', () async {
    var viewModel = riveFile.viewModelByName("Person");
    expect(viewModel, isNotNull);
    viewModel!.dispose();

    viewModel = riveFile.viewModelByName("DoesNotExist");
    expect(viewModel, isNull);
  });

  test('null on non existing items', () async {
    // View Models that do not exist should return null.
    var viewModel = riveFile.viewModelByIndex(100); // out of range
    expect(viewModel, isNull);
    viewModel = riveFile.viewModelByName("DoesNotExist"); // out of range
    expect(viewModel, isNull);

    // This exists, and is used in the rest of the tests.
    viewModel = riveFile.viewModelByName("Person");
    expect(viewModel, isNotNull);

    // Instances that do not exist should return null.
    var viewModelInstance = viewModel!.createInstanceByIndex(100);
    expect(viewModelInstance, isNull);
    viewModelInstance = viewModel.createInstanceByName("DoesNotExist");
    expect(viewModelInstance, isNull);

    // This exists, and is used in the rest of the tests.
    viewModelInstance = viewModel.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    // Properties that do not exist should return null.
    var numberProperty = viewModelInstance!.number('numberDoesNotExist');
    var stringProperty = viewModelInstance.string('stringDoesNotExist');
    var colorProperty = viewModelInstance.color('colorDoesNotExist');
    var booleanProperty = viewModelInstance.boolean('booleanDoesNotExist');
    var enumProperty = viewModelInstance.enumerator('enumDoesNotExist');
    var triggerProperty = viewModelInstance.trigger('triggerDoesNotExist');
    var viewModelProperty =
        viewModelInstance.viewModel('viewModelDoesNotExist');
    expect(numberProperty, isNull);
    expect(stringProperty, isNull);
    expect(colorProperty, isNull);
    expect(booleanProperty, isNull);
    expect(enumProperty, isNull);
    expect(triggerProperty, isNull);
    expect(viewModelProperty, isNull);
  });

  test('view model by artboard default exists', () async {
    var artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);

    var viewModel = riveFile.defaultArtboardViewModel(artboard!);
    expect(viewModel, isNotNull);
    artboard.dispose();
    viewModel!.dispose();
  });

  test('can bind view model instances', () async {
    var artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);
    var stateMachine = artboard!.defaultStateMachine();
    expect(stateMachine, isNotNull);
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(() => artboard.bindViewModelInstance(viewModelInstance!),
        returnsNormally);
    expect(() => stateMachine!.bindViewModelInstance(viewModelInstance!),
        returnsNormally);

    // Request advance on view model instance should request advance on bound state machine
    int requestAdvanceCount = 0;
    void requestAdvanceCallback() {
      requestAdvanceCount++;
    }

    stateMachine!.addAdvanceRequestListener(requestAdvanceCallback);
    viewModelInstance!.requestAdvance();
    expect(requestAdvanceCount, 1);
    stateMachine.removeAdvanceRequestListener(requestAdvanceCallback);
  });

  test('view model properties are correct', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    expect(viewModel!.name, "Person");
    expect(viewModel.propertyCount, 8);
    expect(viewModel.instanceCount, 2);

    final properties = viewModel.properties;
    expect(properties, _viewModelPropertiesToCompare);
    viewModel.dispose();
  });

  test('view model instance create from index', () async {
    var viewModel = riveFile.viewModelByIndex(0);
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByIndex(0);
    expect(viewModelInstance, isNotNull);
    viewModelInstance!.dispose();
  });

  test('view model instance create from name', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);
    viewModelInstance!.dispose();
  });

  test('view model instance create default', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createDefaultInstance();
    expect(viewModelInstance, isNotNull);
    viewModelInstance!.dispose();
  });

  test('view model instance create empty', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstance();
    expect(viewModelInstance, isNotNull);
    viewModelInstance!.dispose();
  });

  test('view model instance property values', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    int requestAdvanceCount = 0;
    void requestAdvanceCallback() {
      requestAdvanceCount++;
    }

    viewModelInstance!.addAdvanceRequestListener(requestAdvanceCallback);

    // view model instance name
    expect(viewModelInstance.name, "Gordon");

    // properties
    final properties = viewModel.properties;
    expect(properties, _viewModelPropertiesToCompare);

    // number
    var numberProperty = viewModelInstance.number('age');
    expect(numberProperty, isNotNull);
    expect(numberProperty!.value, 30);
    numberProperty.value = 33;
    expect(requestAdvanceCount, 1);
    expect(numberProperty.value, 33);

    // string
    var stringProperty = viewModelInstance.string('name');
    expect(stringProperty, isNotNull);
    expect(stringProperty!.value, "Gordon");
    stringProperty.value = "Peter";
    expect(requestAdvanceCount, 2);
    expect(stringProperty.value, "Peter");

    // color
    var colorProperty = viewModelInstance.color('favourite_color');
    expect(colorProperty, isNotNull);
    var color = colorProperty!.value;
    expect(color.red, 255);
    expect(color.green, 0);
    expect(color.blue, 0);
    colorProperty.value = const Color.fromARGB(143, 0, 255, 0);
    expect(requestAdvanceCount, 3);
    color = colorProperty.value;
    expect(color.alpha, 143);
    expect(color.red, 0);
    expect(color.green, 255);
    expect(color.blue, 0);
    colorProperty.value = colorProperty.value.withAlpha(0);
    expect(requestAdvanceCount, 4);
    color = colorProperty.value;
    expect(color.alpha, 0);
    const originalColor = Color.fromRGBO(255, 23, 79, 0.5123);
    colorProperty.value = originalColor;
    expect(requestAdvanceCount, 5);
    expect(colorProperty.value.value, originalColor.value);
    expect(colorProperty.value.red, originalColor.red);
    expect(colorProperty.value.green, originalColor.green);
    expect(colorProperty.value.blue, originalColor.blue);
    expect(colorProperty.value.opacity, originalColor.opacity);

    // boolean
    var booleanProperty = viewModelInstance.boolean('likes_popcorn');
    expect(booleanProperty, isNotNull);
    expect(booleanProperty!.value, false);
    booleanProperty.value = true;
    expect(requestAdvanceCount, 6);
    expect(booleanProperty.value, true);

    // enum
    var enumProperty = viewModelInstance.enumerator('favourite_pet');
    expect(enumProperty!.enumType, "Pets"); // name of the enum
    expect(enumProperty, isNotNull);
    expect(enumProperty.value, "dog");
    enumProperty.value = "cat";
    expect(requestAdvanceCount, 7);
    expect(enumProperty.value, "cat");
    enumProperty.value = "snakeLizard"; // does not exist as a valid enum
    expect(requestAdvanceCount, 8);
    expect(enumProperty.value, "cat",
        reason: 'should not change to invalid enum');

    // trigger
    var triggerProperty = viewModelInstance.trigger('jump');
    expect(triggerProperty, isNotNull);
    triggerProperty!.trigger(); // expect this to not throw
    expect(requestAdvanceCount, 9);

    // view model instance
    var viewModelProperty = viewModelInstance.viewModel('pet');
    expect(viewModelProperty, isNotNull);
    var petName = viewModelProperty!.string('name');
    expect(petName, isNotNull);
    expect(petName!.value, "Jameson");

    var petType = viewModelProperty.enumerator('type')!;
    expect(petType.enumType, "Pets"); // name of the enum
    expect(petType.value, "frog");
    petType.value = "chipmunk";
    expect(requestAdvanceCount, 10);
    expect(petType.value, "chipmunk");

    viewModelInstance.removeAdvanceRequestListener(requestAdvanceCallback);
  });

  test('view model instance value has changed and clear changes work',
      () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var numberProperty = viewModelInstance!.number('age');
    expect(numberProperty!.hasChanged, false);
    numberProperty.value = 100;
    expect(numberProperty.hasChanged, true);
    numberProperty.clearChanges();
    expect(numberProperty.hasChanged, false);
  });

  test('view model instance value callbacks', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon')!;
    expect(viewModelInstance, isNotNull);

    // number
    var numberProperty = viewModelInstance.number('age')!;
    Completer<void> numberCompleter = Completer();
    numberCallback(value) {
      expect(value, 100);
      numberCompleter.complete();
    }

    // string
    var stringProperty = viewModelInstance.string('name')!;
    Completer<void> stringCompleter = Completer();
    stringCallback(value) {
      expect(value, "Peter Parker");
      stringCompleter.complete();
    }

    // color
    var colorProperty = viewModelInstance.color('favourite_color')!;
    Completer<void> colorCompleter = Completer();
    Completer<void> colorCompleter2 = Completer();
    colorCallback(value) {
      expect(value, const Color(0xFF00FF00));
      colorCompleter.complete();
    }

    colorCallback2(value) {
      expect(value, const Color(0xFF00FF00));
      colorCompleter2.complete();
    }

    // enumerator
    var enumProperty = viewModelInstance.enumerator('favourite_pet')!;
    expect(enumProperty.enumType, "Pets"); // name of the enum
    Completer<void> enumCompleter = Completer();
    enumCallback(value) {
      expect(value, "cat");
      enumCompleter.complete();
    }

    // boolean
    var booleanProperty = viewModelInstance.boolean('likes_popcorn')!;
    Completer<void> booleanCompleter = Completer();
    booleanCallback(value) {
      expect(value, true);
      booleanCompleter.complete();
    }

    // trigger
    var triggerProperty = viewModelInstance.trigger('jump')!;
    Completer<void> triggerCompleter = Completer();
    triggerCallback(bool value) {
      triggerCompleter.complete();
    }

    // view model instance property
    var viewModelProperty = viewModelInstance.viewModel('pet')!;

    // Nested enum property
    var petTypeProperty = viewModelProperty.enumerator('type')!;
    expect(petTypeProperty.enumType, "Pets"); // name of the enum
    Completer<void> petTypeCompleter = Completer();
    petTypeCallback(value) {
      expect(value, "chipmunk");
      petTypeCompleter.complete();
    }

    // ADD LISTENERS
    numberProperty.addListener(numberCallback);
    numberProperty.addListener(
        numberCallback); // this should not do anything as this callback is already added
    expect(numberProperty.numberOfListeners, 1,
        reason: "should only have one listener");

    stringProperty.addListener(stringCallback);
    expect(numberProperty.numberOfListeners, 1);

    colorProperty.addListener(colorCallback);
    colorProperty.addListener(colorCallback2);
    expect(colorProperty.numberOfListeners, 2);

    enumProperty.addListener(enumCallback);
    expect(enumProperty.numberOfListeners, 1);

    booleanProperty.addListener(booleanCallback);
    expect(booleanProperty.numberOfListeners, 1);

    triggerProperty.addListener(triggerCallback);
    expect(triggerProperty.numberOfListeners, 1);

    petTypeProperty.addListener(petTypeCallback);
    expect(petTypeProperty.numberOfListeners, 1);

    // CHANGE VALUES
    numberProperty.value = 100;
    stringProperty.value = "Peter Parker";
    colorProperty.value = const Color.fromARGB(255, 0, 255, 0);
    enumProperty.value = "cat";
    booleanProperty.value = true;
    expect(booleanProperty.hasChanged, true);
    triggerProperty.trigger();
    petTypeProperty.value = "chipmunk";

    viewModelInstance.handleCallbacks(); // Simulate a frame advance.

    // VERIFY CALLBACKS
    expect(viewModelInstance.numberOfCallbacks, 7,
        reason: "should be incremented for each value property");

    numberProperty.removeListener(numberCallback);
    expect(numberProperty.numberOfListeners, 0);

    stringProperty.clearListeners();
    expect(stringProperty.numberOfListeners, 0);

    triggerProperty.clearListeners();
    expect(triggerProperty.numberOfListeners, 0);

    expect(viewModelInstance.numberOfCallbacks, 4,
        reason: "not all callbacks should be removed yet");

    colorProperty.clearListeners();
    expect(colorProperty.numberOfListeners, 0);

    expect(viewModelInstance.numberOfCallbacks, 3,
        reason: "callbacks should be less but not 0");

    await Future.wait([
      numberCompleter.future,
      stringCompleter.future,
      colorCompleter.future,
      colorCompleter2.future,
      booleanCompleter.future,
      enumCompleter.future,
      triggerCompleter.future,
      petTypeCompleter.future
    ]);

    viewModelInstance.dispose();

    expect(viewModelInstance.numberOfCallbacks, 0,
        reason: "callbacks should be 0");

    expect(enumProperty.numberOfListeners, 0);
    expect(booleanProperty.numberOfListeners, 0);
    expect(petTypeProperty.numberOfListeners, 0);
  });

  test('view model properties by nested path', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var nestedStringProperty = viewModelInstance!.string('pet/name');
    var nestedEnumProperty = viewModelInstance.enumerator('pet/type');
    expect(nestedStringProperty, isNotNull);
    expect(nestedEnumProperty, isNotNull);

    expect(nestedStringProperty!.value, "Jameson");
    expect(nestedEnumProperty!.value, "frog");

    Completer<void> stringCompleter = Completer();
    stringCallback(value) {
      expect(nestedStringProperty.value, "Peter Parker");
      stringCompleter.complete();
    }

    Completer<void> enumCompleter = Completer();
    enumCallback(value) {
      expect(nestedEnumProperty.value, "chipmunk");
      enumCompleter.complete();
    }

    nestedStringProperty.addListener(stringCallback);
    expect(nestedStringProperty.numberOfListeners, 1);
    expect(viewModelInstance.numberOfCallbacks, 1);

    nestedEnumProperty.addListener(enumCallback);
    expect(nestedEnumProperty.numberOfListeners, 1);
    expect(viewModelInstance.numberOfCallbacks, 2);

    nestedStringProperty.value = "Peter Parker";
    nestedEnumProperty.value = "chipmunk";

    viewModelInstance.handleCallbacks(); // Simulate a frame advance.

    await Future.wait([
      stringCompleter.future,
      enumCompleter.future,
    ]);

    nestedStringProperty.clearListeners();
    expect(nestedStringProperty.numberOfListeners, 0);
    expect(viewModelInstance.numberOfCallbacks, 1);
    nestedEnumProperty.clearListeners();
    expect(nestedEnumProperty.numberOfListeners, 0);
    expect(viewModelInstance.numberOfCallbacks, 0);
  });

  test('databinding images test', () async {
    final bytes = loadFile('assets/databinding_images.riv');
    final imageFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter)
            as rive.File;
    final viewModel = imageFile.viewModelByName('MyViewModel');
    expect(viewModel, isNotNull);
    var properties = viewModel!.properties;
    expect(properties.length, 1);
    expect(properties[0].type, rive.DataType.image);
    expect(properties[0].name, 'bound_image');
    final viewModelInstance = viewModel.createInstanceByIndex(0);
    expect(viewModelInstance, isNotNull);
    properties = viewModelInstance!.properties;
    expect(properties.length, 1);
    expect(properties[0].type, rive.DataType.image);
    expect(properties[0].name, 'bound_image');
  });

  test('databinding lists test', () async {
    final bytes = loadFile('assets/databinding_lists.riv');
    final riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter)
            as rive.File;
    final viewModel = riveFile.viewModelByName('DevRel');
    expect(viewModel, isNotNull);
    var properties = viewModel!.properties;
    expect(properties.length, 1);
    expect(properties[0].type, rive.DataType.list);
    final viewModelInstance = viewModel.createDefaultInstance();

    int requestAdvanceCount = 0;
    void requestAdvanceCallback() {
      requestAdvanceCount++;
    }

    viewModelInstance!.addAdvanceRequestListener(requestAdvanceCallback);

    expect(viewModelInstance, isNotNull);
    final list = viewModelInstance.list('team');
    expect(list, isNotNull);
    expect(list!.length, 5);
    var instance0 = list.instanceAt(0);
    var instance1 = list.instanceAt(1);
    var instance2 = list.instanceAt(2);
    var instance3 = list.instanceAt(3);
    var instance4 = list.instanceAt(4);
    expect(instance0.string('name')!.value, 'Gordon');
    expect(instance1.string('name')!.value, 'David');
    expect(instance2.string('name')!.value, 'Tod');
    expect(instance3.string('name')!.value, 'Erik');
    expect(instance4.string('name')!.value, 'Adam');

    // add instance
    final viewModelPerson = riveFile.viewModelByName('Person');
    final hernanPerson = viewModelPerson!.createInstance();
    hernanPerson!.string('name')!.value = 'Hernan';
    list.add(hernanPerson);
    expect(requestAdvanceCount, 1);
    expect(list.length, 6);
    final instance5 = list.instanceAt(5);
    expect(instance5.string('name')!.value, 'Hernan');

    // remove instance
    list.remove(instance0);
    expect(requestAdvanceCount, 2);
    expect(list.length, 5);

    list.removeAt(3);
    expect(requestAdvanceCount, 3);
    expect(list.length, 4);
    instance3 = list.instanceAt(3);
    expect(instance3.string('name')!.value, 'Hernan');

    // swap instances
    expect(() => list.swap(-1, 1), throwsRangeError,
        reason: "negative index should throw");
    expect(requestAdvanceCount, 3, reason: "should not increment");
    expect(() => list.swap(1, -5), throwsRangeError,
        reason: "negative index should throw");
    expect(requestAdvanceCount, 3, reason: "should not increment");
    list.swap(0, 1);
    expect(requestAdvanceCount, 4);
    expect(list.instanceAt(0).string('name')!.value, 'Tod');
    expect(list.instanceAt(1).string('name')!.value, 'David');
    list.swap(0, 1);
    expect(requestAdvanceCount, 5);
    expect(list.instanceAt(0).string('name')!.value, 'David');
    expect(list.instanceAt(1).string('name')!.value, 'Tod');

    // swap instances with invalid indices
    expect(() => list.swap(0, 100), throwsRangeError,
        reason: "out of range index should throw");
    expect(requestAdvanceCount, 5, reason: "should not increment");
    expect(list.instanceAt(0).string('name')!.value, 'David');
    expect(list.instanceAt(1).string('name')!.value, 'Tod');

    final lancePerson = viewModelPerson.createInstance();
    lancePerson!.string('name')!.value = 'Lance';

    // add instance at valid index
    var result = list.insert(2, lancePerson);
    expect(requestAdvanceCount, 6);
    expect(result, true);
    expect(list.length, 5);
    expect(list.instanceAt(2).string('name')!.value, 'Lance');

    final philPerson = viewModelPerson.createInstance();
    philPerson!.string('name')!.value = 'Phil';

    // add instance at valid index
    list[3] = philPerson;
    expect(requestAdvanceCount, 7);
    expect(list[3].string('name')!.value, 'Phil');

    // instanceAt negative
    expect(() => list.instanceAt(-1), throwsRangeError,
        reason: "negative index should throw");

    // instanceAt out of range
    expect(() => list.instanceAt(100), throwsRangeError,
        reason: "out of range index should throw");

    // removeAt negative
    expect(() => list.removeAt(-1), throwsRangeError,
        reason: "negative index should throw");
    expect(requestAdvanceCount, 7, reason: "should not increment");

    // removeAt out of range
    expect(() => list.removeAt(100), throwsRangeError,
        reason: "out of range index should throw");
    expect(requestAdvanceCount, 7, reason: "should not increment");

    // insert negative
    expect(() => list.insert(-1, lancePerson), throwsRangeError,
        reason: "negative index should throw");
    expect(requestAdvanceCount, 7, reason: "should not increment");

    // insert out of range
    expect(() => list.insert(100, lancePerson), throwsRangeError,
        reason: "out of range index should throw");
    expect(requestAdvanceCount, 7, reason: "should not increment");

    viewModelInstance.removeAdvanceRequestListener(requestAdvanceCallback);
  });

  test('databinding artboard test', () async {
    final bytes = loadFile('assets/artboard_db_test.riv');
    final riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter)
            as rive.File;
    final artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);
    final vmi =
        riveFile.defaultArtboardViewModel(artboard!)!.createDefaultInstance();
    expect(vmi, isNotNull);
    expect(vmi!.properties.length, 2);
    expect(vmi.properties[0].type, rive.DataType.artboard);
    expect(vmi.properties[0].name, 'artboard_1');
    expect(vmi.properties[1].type, rive.DataType.artboard);
    expect(vmi.properties[1].name, 'artboard_2');
  });

  test('view model instance value stream - number property', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var numberProperty = viewModelInstance!.number('age');
    expect(numberProperty, isNotNull);

    final stream = numberProperty!.valueStream;
    final values = <double>[];
    Completer<void> numberCompleter = Completer();

    final subscription = stream.listen((value) {
      values.add(value);
      if (!numberCompleter.isCompleted) {
        numberCompleter.complete();
      }
    });

    // Initial value should be emitted immediately on first subscription
    await numberCompleter.future;
    expect(values, [30]); // Gordon's age is 30

    // Change the value
    numberCompleter = Completer();
    numberProperty.value = 50;
    viewModelInstance.handleCallbacks();
    await numberCompleter.future;

    expect(values, [30, 50]);

    // Change again
    numberCompleter = Completer();
    numberProperty.value = 75;
    viewModelInstance.handleCallbacks();
    await numberCompleter.future;

    expect(values, [30, 50, 75]);

    // Cancel subscription
    await subscription.cancel();

    // Change value after cancellation - should not be received
    numberProperty.value = 100;
    viewModelInstance.handleCallbacks();

    expect(values, [30, 50, 75]); // No new value added after cancellation

    viewModelInstance.dispose();
  });

  test('view model instance value stream - string property', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var stringProperty = viewModelInstance!.string('name');
    expect(stringProperty, isNotNull);

    final stream = stringProperty!.valueStream;
    final values = <String>[];
    Completer<void> stringCompleter = Completer();

    final subscription = stream.listen((value) {
      values.add(value);
      if (!stringCompleter.isCompleted) {
        stringCompleter.complete();
      }
    });

    // Initial value should be emitted immediately
    await stringCompleter.future;
    expect(values, ["Gordon"]);

    // Change the value
    stringCompleter = Completer();
    stringProperty.value = "Alice";
    viewModelInstance.handleCallbacks();
    await stringCompleter.future;

    expect(values, ["Gordon", "Alice"]);

    stringCompleter = Completer();
    stringProperty.value = "Bob";
    viewModelInstance.handleCallbacks();
    await stringCompleter.future;

    expect(values, ["Gordon", "Alice", "Bob"]);

    await subscription.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - boolean property', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var booleanProperty = viewModelInstance!.boolean('likes_popcorn');
    expect(booleanProperty, isNotNull);

    final stream = booleanProperty!.valueStream;
    final values = <bool>[];
    Completer<void> booleanCompleter = Completer();

    final subscription = stream.listen((value) {
      values.add(value);
      if (!booleanCompleter.isCompleted) {
        booleanCompleter.complete();
      }
    });

    // Initial value should be emitted immediately
    await booleanCompleter.future;
    expect(values, [false]); // Gordon's likes_popcorn is false

    // Change the value
    booleanCompleter = Completer();
    booleanProperty.value = true;
    viewModelInstance.handleCallbacks();
    await booleanCompleter.future;

    expect(values, [false, true]);

    booleanCompleter = Completer();
    booleanProperty.value = false;
    viewModelInstance.handleCallbacks();
    await booleanCompleter.future;

    expect(values, [false, true, false]);

    await subscription.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - color property', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var colorProperty = viewModelInstance!.color('favourite_color');
    expect(colorProperty, isNotNull);

    final stream = colorProperty!.valueStream;
    final values = <Color>[];
    Completer<void> colorCompleter = Completer();

    final subscription = stream.listen((value) {
      values.add(value);
      if (!colorCompleter.isCompleted) {
        colorCompleter.complete();
      }
    });

    // Initial value should be emitted immediately (Gordon's favourite_color is red)
    await colorCompleter.future;
    expect(values.length, 1);
    expect(values[0].red, 255);

    // Change the value
    colorCompleter = Completer();
    colorProperty.value = const Color.fromARGB(255, 0, 255, 0);
    viewModelInstance.handleCallbacks();
    await colorCompleter.future;

    expect(values.length, 2);
    expect(values[1].green, 255);

    colorCompleter = Completer();
    colorProperty.value = const Color.fromARGB(255, 0, 0, 255);
    viewModelInstance.handleCallbacks();
    await colorCompleter.future;

    expect(values.length, 3);
    expect(values[2].blue, 255);

    await subscription.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - enum property', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var enumProperty = viewModelInstance!.enumerator('favourite_pet');
    expect(enumProperty, isNotNull);

    final stream = enumProperty!.valueStream;
    final values = <String>[];
    Completer<void> enumCompleter = Completer();

    final subscription = stream.listen((value) {
      values.add(value);
      if (!enumCompleter.isCompleted) {
        enumCompleter.complete();
      }
    });

    // Initial value should be emitted immediately (Gordon's favourite_pet is "dog")
    await enumCompleter.future;
    expect(values, ["dog"]);

    // Change the value
    enumCompleter = Completer();
    enumProperty.value = "cat";
    viewModelInstance.handleCallbacks();
    await enumCompleter.future;

    expect(values, ["dog", "cat"]);

    enumCompleter = Completer();
    enumProperty.value = "owl";
    viewModelInstance.handleCallbacks();
    await enumCompleter.future;

    expect(values, ["dog", "cat", "owl"]);

    await subscription.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - multiple subscriptions', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var numberProperty = viewModelInstance!.number('age');
    expect(numberProperty, isNotNull);

    final stream = numberProperty!.valueStream;
    final values1 = <double>[];
    final values2 = <double>[];
    Completer<void> completer1 = Completer();
    Completer<void> completer2 = Completer();

    // First subscription receives initial value (30)
    final subscription1 = stream.listen((value) {
      values1.add(value);
      if (!completer1.isCompleted) {
        completer1.complete();
      }
    });

    await completer1.future;
    expect(values1, [30]); // Initial value emitted to first subscriber

    // Second subscription does NOT receive initial value (onListen only called once)
    final subscription2 = stream.listen((value) {
      values2.add(value);
      if (!completer2.isCompleted) {
        completer2.complete();
      }
    });

    // Change the value - both subscriptions should receive it
    completer1 = Completer();
    numberProperty.value = 42;
    viewModelInstance.handleCallbacks();
    await Future.wait([completer1.future, completer2.future]);

    expect(values1, [30, 42]);
    expect(values2, [42]); // Second subscriber only gets changes

    completer1 = Completer();
    completer2 = Completer();
    numberProperty.value = 84;
    viewModelInstance.handleCallbacks();
    await Future.wait([completer1.future, completer2.future]);

    expect(values1, [30, 42, 84]);
    expect(values2, [42, 84]);

    // Cancel one subscription
    await subscription1.cancel();

    // Change value - only second subscription should receive it
    completer2 = Completer();
    numberProperty.value = 100;
    viewModelInstance.handleCallbacks();
    await completer2.future;

    expect(values1, [30, 42, 84]);
    expect(values2, [42, 84, 100]);

    await subscription2.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - late initialization', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var numberProperty = viewModelInstance!.number('age');
    expect(numberProperty, isNotNull);

    // Stream should be created lazily when first accessed
    final stream1 = numberProperty!.valueStream;
    final stream2 = numberProperty.valueStream;

    // Both streams should be backed by the same controller (they receive the same values)
    final values1 = <double>[];
    final values2 = <double>[];
    Completer<void> completer1 = Completer();
    Completer<void> completer2 = Completer();

    // First subscription receives initial value
    final subscription1 = stream1.listen((value) {
      values1.add(value);
      if (!completer1.isCompleted) {
        completer1.complete();
      }
    });

    await completer1.future;
    expect(values1, [30]); // Initial value

    // Second subscription does not receive initial value
    final subscription2 = stream2.listen((value) {
      values2.add(value);
      if (!completer2.isCompleted) {
        completer2.complete();
      }
    });

    // Both subscriptions should receive changes
    completer1 = Completer();
    numberProperty.value = 99;
    viewModelInstance.handleCallbacks();
    await Future.wait([completer1.future, completer2.future]);

    expect(values1, [30, 99]);
    expect(values2, [99]);

    await subscription1.cancel();
    await subscription2.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - cleanup with clearListeners',
      () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var numberProperty = viewModelInstance!.number('age');
    expect(numberProperty, isNotNull);

    final stream = numberProperty!.valueStream;
    final values = <double>[];
    Completer<void> completer = Completer();
    stream.listen((value) {
      values.add(value);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // Initial value emitted
    await completer.future;
    expect(values, [30]);

    completer = Completer();
    numberProperty.value = 10;
    viewModelInstance.handleCallbacks();
    await completer.future;
    expect(values, [30, 10]);

    // Clear listeners should close the stream controller
    numberProperty.clearListeners();

    // After clearListeners, the stream should be closed
    // Attempting to listen again should create a new stream
    final stream2 = numberProperty.valueStream;
    expect(stream2, isNot(same(stream)));

    final values2 = <double>[];
    completer = Completer();
    final subscription2 = stream2.listen((value) {
      values2.add(value);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // Initial value emitted again (10, since we changed it)
    await completer.future;
    expect(values2, [10]);

    completer = Completer();
    numberProperty.value = 20;
    viewModelInstance.handleCallbacks();
    await completer.future;
    expect(values2, [10, 20]);

    // Original subscription should not receive new values
    expect(values, [30, 10]);

    await subscription2.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - works with callbacks simultaneously',
      () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var numberProperty = viewModelInstance!.number('age');
    expect(numberProperty, isNotNull);

    final stream = numberProperty!.valueStream;
    final streamValues = <double>[];
    final callbackValues = <double>[];
    Completer<void> streamCompleter = Completer();
    Completer<void> callbackCompleter = Completer();

    // Stream subscription gets initial value
    final subscription = stream.listen((value) {
      streamValues.add(value);
      if (!streamCompleter.isCompleted) {
        streamCompleter.complete();
      }
    });

    await streamCompleter.future;
    expect(streamValues, [30]); // Initial value

    void callback(double value) {
      callbackValues.add(value);
      if (!callbackCompleter.isCompleted) {
        callbackCompleter.complete();
      }
    }

    // Callback does NOT receive initial value (only changes)
    numberProperty.addListener(callback);

    // Change value - both stream and callback should receive it
    streamCompleter = Completer();
    numberProperty.value = 50;
    viewModelInstance.handleCallbacks();
    await Future.wait([streamCompleter.future, callbackCompleter.future]);

    expect(streamValues, [30, 50]);
    expect(callbackValues, [50]);

    streamCompleter = Completer();
    callbackCompleter = Completer();
    numberProperty.value = 60;
    viewModelInstance.handleCallbacks();
    await Future.wait([streamCompleter.future, callbackCompleter.future]);

    expect(streamValues, [30, 50, 60]);
    expect(callbackValues, [50, 60]);

    numberProperty.removeListener(callback);
    await subscription.cancel();
    viewModelInstance.dispose();
  });

  test('view model instance value stream - nested property', () async {
    var viewModel = riveFile.viewModelByName('Person');
    expect(viewModel, isNotNull);
    var viewModelInstance = viewModel!.createInstanceByName('Gordon');
    expect(viewModelInstance, isNotNull);

    var nestedStringProperty = viewModelInstance!.string('pet/name');
    expect(nestedStringProperty, isNotNull);

    final stream = nestedStringProperty!.valueStream;
    final values = <String>[];
    Completer<void> completer = Completer();
    final subscription = stream.listen((value) {
      values.add(value);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // Initial value emitted (pet's name is "Jameson")
    await completer.future;
    expect(values, ["Jameson"]);

    completer = Completer();
    nestedStringProperty.value = "Fluffy";
    viewModelInstance.handleCallbacks();
    await completer.future;

    expect(values, ["Jameson", "Fluffy"]);

    completer = Completer();
    nestedStringProperty.value = "Whiskers";
    viewModelInstance.handleCallbacks();
    await completer.future;

    expect(values, ["Jameson", "Fluffy", "Whiskers"]);

    await subscription.cancel();
    viewModelInstance.dispose();
  });

  test('artboardToBind with ViewModelInstance', () async {
    final bytes = loadFile('assets/artboard_db_vmi_test.riv');
    final riveFile =
        await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
    expect(riveFile, isNotNull,
        reason: 'Expected to decode test/assets/artboard_db_vmi_test.riv');

    // Get the ControlledViewModel and create an instance
    final controlledViewModel =
        riveFile!.viewModelByName('ControlledViewModel');
    expect(controlledViewModel, isNotNull,
        reason: 'ControlledViewModel should exist in test file');

    final controlledInstance = controlledViewModel!.createInstance();
    expect(controlledInstance, isNotNull,
        reason: 'Expected to create ControlledViewModel instance');

    // Create a bindable artboard without a VMI
    const artboardName = 'ArtboardBlue';
    final bindableArtboard = riveFile.artboardToBind(artboardName);
    expect(bindableArtboard, isNotNull,
        reason: 'BindableArtboard should exist');

    // Create a bindable artboard with a VMI
    final bindableArtboardWithVmi = riveFile.artboardToBind(
      artboardName,
      viewModelInstance: controlledInstance,
    );
    expect(bindableArtboardWithVmi, isNotNull,
        reason: 'BindableArtboard with VMI should exist');

    // Verify both are distinct instances
    expect(
      identical(bindableArtboard, bindableArtboardWithVmi),
      isFalse,
      reason: 'Different calls should return different instances',
    );

    // Get the default artboard and its VMI to set artboard properties
    final artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);

    final vmi =
        riveFile.defaultArtboardViewModel(artboard!)!.createDefaultInstance();
    expect(vmi, isNotNull);

    // Set the artboard property with the VMI-bound bindable artboard
    final artboardProperty = vmi!.artboard('artboard_1');
    expect(artboardProperty, isNotNull,
        reason: 'artboard_1 property should exist');
    artboardProperty!.value = bindableArtboardWithVmi!;

    // Set a regular bindable artboard on the other property
    final artboardProperty2 = vmi.artboard('artboard_2');
    expect(artboardProperty2, isNotNull,
        reason: 'artboard_2 property should exist');
    artboardProperty2!.value = bindableArtboard!;

    // Clean up
    controlledInstance!.dispose();
    bindableArtboard.dispose();
    bindableArtboardWithVmi.dispose();
    vmi.dispose();
    artboard.dispose();
    controlledViewModel.dispose();
    riveFile.dispose();
  });
}
