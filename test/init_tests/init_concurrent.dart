import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../src/utils.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('Test dual initialization through file and manual', () async {
    expect(rive.RiveNative.isInitialized, false);
    unawaited(rive.RiveNative.init()); // do not await
    final riveBytes = loadFile('assets/runtime_nested_inputs.riv');
    // await the file load which also awaits the initialization already in
    // progress
    final riveFile =
        await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
            as rive.File;
    expect(riveFile, isNotNull);
    expect(rive.RiveNative.isInitialized, true);
  });
}
