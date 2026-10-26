@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

/// Web counterpart to `init_test.dart`/`init_through_file_test.dart`, which
/// assert *lazy* initialization and are VM-only: on the web the test harness
/// pre-initializes in `flutter_test_config.dart` (the wasm module must be
/// linked before `Factory.flutter` is touched), so laziness cannot be
/// observed here. What we can assert is that init succeeded against the
/// served wasm and stays stable.
void main() {
  test('wasm module is initialized by the test harness', () {
    expect(rive.RiveNative.isInitialized, true);
  });

  test('init is idempotent once initialized', () async {
    expect(await rive.RiveNative.init(), true);
    expect(rive.RiveNative.isInitialized, true);
  });
}
