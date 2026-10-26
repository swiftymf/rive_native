@TestOn('!browser')
library; // asserts lazy init; the web harness pre-initializes in flutter_test_config

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('Test manual initialization', () async {
    expect(rive.RiveNative.isInitialized, false);
    await rive.RiveNative.init();
    expect(rive.RiveNative.isInitialized, true);
  });
}
