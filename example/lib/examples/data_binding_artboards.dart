import 'package:example/app.dart';
import 'package:flutter/material.dart';
import 'package:rive_native/rive_native.dart' as rive;

class ExampleDataBindingArtboards extends StatefulWidget {
  const ExampleDataBindingArtboards({super.key});

  @override
  State<ExampleDataBindingArtboards> createState() => _ExampleBasicState();
}

class _ExampleBasicState extends State<ExampleDataBindingArtboards> {
  late rive.StateMachinePainter stateMachinePainter = rive.StateMachinePainter(
    fit: rive.Fit.layout,
    withStateMachine: (stateMachine) {
      stateMachine.bindViewModelInstance(viewModelInstance);
    },
  )..layoutScaleFactor = 1;
  rive.File? riveFile;
  rive.Artboard? mainArtboard;
  rive.BindableArtboard? artboardRed;
  rive.BindableArtboard? artboardBlue;
  rive.BindableArtboard? artboardGreen;
  late rive.ViewModelInstance viewModelInstance;
  late rive.ViewModelInstanceArtboard artboard1Property;
  late rive.ViewModelInstanceArtboard artboard2Property;

  // Other file and artboard
  rive.File? externalFile;
  rive.BindableArtboard? externalArtboardToBind;

  // Dropdown selection state
  String? selectedArtboard1;
  String? selectedArtboard2;

  // Available artboard options
  final List<MapEntry<String, String>> artboardOptions = [
    const MapEntry('red', 'Red'),
    const MapEntry('blue', 'Blue'),
    const MapEntry('green', 'Green'),
    const MapEntry('external', 'External'),
  ];

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    super.dispose();
    stateMachinePainter.dispose();
    artboard1Property.dispose();
    artboard2Property.dispose();
    viewModelInstance.dispose();
    mainArtboard?.dispose();
    artboardRed?.dispose();
    artboardBlue?.dispose();
    artboardGreen?.dispose();
    riveFile?.dispose();
  }

  Future<void> init() async {
    riveFile = await rive.File.asset(
      "assets/artboard_db_test.riv",
      riveFactory: RiveExampleApp.getCurrentFactory,
    );
    mainArtboard = riveFile?.artboard("Main");
    artboardRed = riveFile?.artboardToBind("ArtboardRed");
    artboardBlue = riveFile?.artboardToBind("ArtboardBlue");
    artboardGreen = riveFile?.artboardToBind("ArtboardGreen");
    final vm = riveFile?.defaultArtboardViewModel(mainArtboard!)!;
    viewModelInstance = (vm?.createDefaultInstance())!;
    artboard1Property = viewModelInstance.artboard("artboard_1")!;
    artboard2Property = viewModelInstance.artboard("artboard_2")!;

    // Set default selections
    selectedArtboard1 = 'green';
    selectedArtboard2 = 'red';

    // Set initial artboard bindings
    updateArtboardBindings();

    // Set up external artboard (from a different file) to bind
    externalFile = (await rive.File.asset(
      "assets/little_machine.riv",
      riveFactory: RiveExampleApp.getCurrentFactory,
    ));
    externalArtboardToBind = (externalFile?.artboardToBind("New Artboard"))!;
  }

  void updateArtboardBindings() {
    // Update artboard 1 binding
    switch (selectedArtboard1) {
      case 'red':
        artboard1Property.value = artboardRed!;
        break;
      case 'blue':
        artboard1Property.value = artboardBlue!;
        break;
      case 'green':
        artboard1Property.value = artboardGreen!;
        break;
      case 'external':
        artboard1Property.value = externalArtboardToBind!;
        break;
    }

    // Update artboard 2 binding
    switch (selectedArtboard2) {
      case 'red':
        artboard2Property.value = artboardRed!;
        break;
      case 'blue':
        artboard2Property.value = artboardBlue!;
        break;
      case 'green':
        artboard2Property.value = artboardGreen!;
        break;
      case 'external':
        artboard2Property.value = externalArtboardToBind!;
        break;
    }
    setState(() {});
    stateMachinePainter.scheduleRepaint();
  }

  @override
  Widget build(BuildContext context) {
    if (mainArtboard == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Artboard 1:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: selectedArtboard1,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: artboardOptions.map((option) {
                        return DropdownMenuItem<String>(
                          value: option.key,
                          child: Text(option.value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        selectedArtboard1 = newValue;
                        updateArtboardBindings();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Artboard 2:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: selectedArtboard2,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: artboardOptions.map((option) {
                        return DropdownMenuItem<String>(
                          value: option.key,
                          child: Text(option.value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        selectedArtboard2 = newValue;
                        updateArtboardBindings();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Rive widget
        Expanded(
          child: rive.RiveArtboardWidget(
            artboard: mainArtboard!,
            painter: stateMachinePainter,
          ),
        ),
      ],
    );
  }
}
