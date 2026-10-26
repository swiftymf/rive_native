import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart'
    show reportTestException, tearDownAll;
import 'package:rive_native/rive_native.dart' as rive;

import 'src/golden_tolerance_io.dart'
    if (dart.library.js_interop) 'src/golden_tolerance_web.dart';
import 'src/web_context_probe.dart' show awaitWebGLHeadroom;

/// Runs around every test suite in this package (a flutter_test convention).
///
/// On the web the wasm module must be loaded and linked before anything
/// touches `Factory.flutter`/`Factory.rive` — unlike FFI, where symbols
/// resolve lazily — so initialize once up front.
///
/// On the VM this also runs inside the host-side golden comparator process
/// that `flutter test --platform chrome` spawns for `matchesGoldenFile`;
/// [applyGoldenTolerance] gives those comparisons the same diff tolerance the
/// suite uses locally. It preserves the lazy-init behavior that `init_tests`
/// assert on (no RiveNative.init on the VM).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (kIsWeb) {
    final initialized = await rive.RiveNative.init();
    if (!initialized) {
      throw StateError(
          'Failed to initialize Rive Native for web tests. Is the wasm server '
          'running? (see RIVE_NATIVE_WASM_HOST / LOCAL_RIVE_NATIVE)');
    }
    // Each suite runs in its own iframe but shares the browser's
    // process-wide WebGL context budget with every other suite in the run.
    // Before this suite allocates anything, wait for the browser to credit
    // back the slots earlier suites freed — their drains are synchronous but
    // reclamation is not, and the previous iframe's own contexts are only
    // reclaimed around its teardown, after any wait IT could have run (see
    // [awaitWebGLHeadroom]).
    await awaitWebGLHeadroom();

    // Contexts that outlive the suite (pooled render textures, the offscreen
    // probe) accumulate until context creation fails mid-run — drain them
    // when the suite ends.
    tearDownAll(rive.RiveNative.instance.releaseRenderResources);

    // In the browser, widget-test exceptions are only dumped to the browser
    // console, which `flutter test --platform chrome` does not surface —
    // mirror them to the terminal via print so failures are debuggable.
    final base = reportTestException;
    reportTestException = (details, testDescription) {
      // ignore: avoid_print
      print('═══ Exception in "$testDescription" ═══\n$details');
      base(details, testDescription);
    };
  } else {
    applyGoldenTolerance();
  }
  await testMain();
}
