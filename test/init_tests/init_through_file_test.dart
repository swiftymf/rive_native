@TestOn('!browser')
library; // asserts lazy init; the web harness pre-initializes in flutter_test_config

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../src/utils.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('Test initialization through file', () async {
    expect(rive.RiveNative.isInitialized, false);
    final riveBytes = loadFile('assets/runtime_nested_inputs.riv');
    final riveFile =
        await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
            as rive.File;
    expect(riveFile, isNotNull);
    expect(rive.RiveNative.isInitialized, true,
        reason: 'RiveNative should be initialized automatically');
  });
}
