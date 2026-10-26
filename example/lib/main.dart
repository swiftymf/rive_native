import 'package:example/demos/hero_demo.dart';
import 'package:example/demos/hunter_x.dart';
import 'package:example/examples/data_binding_images.dart';
import 'package:example/semantic/flutter/debugger.dart';
import 'package:example/semantic/flutter/dropdown_list.dart';
import 'package:example/semantic/flutter/lists.dart';
import 'package:example/semantic/flutter/simpsons.dart';
import 'package:example/semantic/rive/databinding_lists.dart';
import 'package:example/semantic/rive/playground.dart';
import 'package:example/semantic/rive/simpsons.dart';
import 'package:flutter/material.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'examples/examples.dart';
import 'app.dart';

const _appBarColor = Color(0xFF323232);
const _backgroundColor = Color(0xFF1D1D1D);
const _primaryColor = Color(0xFF57A5E0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await rive.RiveNative.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseDarkTheme = ThemeData.dark();
    return MaterialApp(
      title: 'Flutter Demo',
      // showPerformanceOverlay: true,
      debugShowCheckedModeBanner: false,
      darkTheme: baseDarkTheme.copyWith(
        scaffoldBackgroundColor: _backgroundColor,
        appBarTheme: const AppBarTheme(backgroundColor: _appBarColor),
        // Keep a true dark color scheme so text/icons stay readable.
        colorScheme: baseDarkTheme.colorScheme.copyWith(
          primary: _primaryColor,
          surface: _backgroundColor,
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}

class Demo {
  final Widget widget;
  final String text;

  Demo(this.widget, this.text);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Demo> widgets = [
    Demo(const HeroDemo(), "GDC Hero"),
    Demo(const HunterXDemo(), "Hunter X Demo"),
    Demo(const SemanticDebuggerDemo(), "Semantic Debugger"),
    Demo(const SemanticDemoRivePlayground(), "Semantic Rive Playground"),
    Demo(const SemanticDemoRiveSimpsons(), "Semantic Rive Simpsons"),
    Demo(const SemanticDemoFlutterSimpsons(), "Semantic Flutter Simpsons"),
    Demo(const SemanticDemoFlutterLists(), "Semantic Flutter Lists"),
    Demo(const SemanticDemoFlutterDropDownLists(),
        "Semantic Flutter Dropdown List"),
    Demo(const SemanticDemoRiveDatabindingLists(),
        "Semantic Rive Databinding Lists"),
    Demo(const ExampleBasic(), "Basic"),
    Demo(const StabilityTest(), "Stability Test"),
    Demo(const ExampleDataBinding(), "Data Binding - Basics"),
    Demo(const ExampleDataBindingArtboards(), "Data Binding - Artboards"),
    Demo(const ExampleDataBindingImages(), "Data Binding - Images"),
    Demo(const ExampleEvents(), "Events"),
    Demo(const ExampleTextRuns(), "Updating Text Runs"),
    Demo(const ExampleTextRunsNested(), "Updating Nested Text Runs"),
    Demo(const StateMachineNestedInputsExample(), "Nested Inputs"),
    Demo(const ExampleTickerMode(), "Ticker Mode"),
    Demo(const ExampleResponsiveLayout(), "Responsive Layout"),
    Demo(const ExampleOutOfBandAssets(), "Out of band assets"),
    Demo(const ExampleTickerMode(), "Ticker Mode"),
    Demo(const ExampleTimeDilation(), "Time Dilation"),
    Demo(const ExampleHitTestBehaviour(), "Hit test behaviour"),
    Demo(const ExampleArtboardDoesNotExists(), "Artboard does not exists"),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Rive Native Examples"),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widgets.length,
              itemBuilder: (context, index) {
                return _button(
                  widgets[index].text,
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) {
                          return BasePage(child: widgets[index].widget);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
              padding: const EdgeInsets.all(8.0),
              child: RiveExampleApp.isRiveRender
                  ? const Text("Active Renderer: Rive")
                  : const Text("Active Renderer: Flutter (Skia or Impeller)")),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      RiveExampleApp.isRiveRender = true;
                    });
                  },
                  child: const Text("Rive Renderer"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      RiveExampleApp.isRiveRender = false;
                    });
                  },
                  child: const Text("Flutter Renderer"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _button(String title, VoidCallback onPressed) {
    return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(
            child: ElevatedButton(onPressed: onPressed, child: Text(title))));
  }
}

class BasePage extends StatelessWidget {
  const BasePage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(),
      body: Center(
        child: Center(child: child),
      ),
    );
  }
}
