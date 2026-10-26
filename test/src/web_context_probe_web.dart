import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'package:rive_native/src/rive_native_web.dart'
    show RiveWasm, debugWebRenderTexturePoolCap;

export 'package:rive_native/src/rive_native_web.dart'
    show debugLoseWebGLContext, debugWebRenderTexturePoolCap;

/// Live WebGL2 contexts created by the wasm glue (canvas renderers plus the
/// offscreen feature-probe), maintained in `native/platform/wasm/init.js`.
int liveGLContextCount() {
  final module = RiveWasm.module;
  if (module == null) {
    throw StateError(
        'Rive wasm module is not linked; await RiveNative.init() first.');
  }
  final fn = module.getProperty('liveGLContextCount'.toJS);
  if (fn.isUndefinedOrNull) {
    throw StateError(
        'liveGLContextCount is not exported by the wasm module — the loaded '
        'wasm predates the context-lifecycle glue; rebuild it '
        '(cd native && ./build.sh wasm single-threaded flutter-runtime).');
  }
  return ((fn as js.JSFunction).callAsFunction(null) as js.JSNumber).toDartInt;
}

/// Waits until the browser will hand out enough fresh WebGL2 contexts for a
/// whole suite's burst of allocations.
///
/// A suite's drain ([RiveNative.releaseRenderResources]) is synchronous — the
/// glue's bookkeeping hits zero immediately — but the browser credits the
/// freed slots back asynchronously after `loseContext`, and contexts the
/// drain can't see (each suite iframe's own renderer surface) are reclaimed
/// only around iframe teardown. The context budget is process-wide across
/// suite iframes, so on slow machines (CI software WebGL especially) a suite
/// can race into a still-full cap and fail context creation. Probing actual
/// context creations (and releasing them right away) is the only observable
/// signal that capacity is really back — and a single free slot has proven
/// insufficient in CI (a suite passed its first test, then died allocating
/// its second texture), so demand a suite's worst case at once: a pool's
/// worth of render textures plus the glue's offscreen probe plus the iframe's
/// renderer surface.
Future<void> awaitWebGLHeadroom() async {
  const timeout = Duration(seconds: 10);
  final slots = debugWebRenderTexturePoolCap + 2;
  final deadline = DateTime.now().add(timeout);
  final held = <web.WebGL2RenderingContext>[];
  void releaseHeld() {
    // Hand the probes' slots straight back.
    for (final ctx in held) {
      (ctx.getExtension('WEBGL_lose_context') as web.WEBGL_lose_context?)
          ?.loseContext();
    }
    held.clear();
  }

  while (true) {
    // Keep earlier acquisitions while polling for the rest — progress toward
    // the target must be simultaneous slots, not slots seen one at a time.
    while (held.length < slots) {
      final canvas = web.HTMLCanvasElement()
        ..width = 1
        ..height = 1;
      final ctx = canvas.getContext('webgl2') as web.WebGL2RenderingContext?;
      if (ctx == null) break;
      held.add(ctx);
    }
    if (held.length >= slots) {
      releaseHeld();
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      // Best effort — waiting is insurance, not a new failure mode.
      final free = held.length;
      releaseHeld();
      // ignore: avoid_print
      print('web_context_probe: only $free of $slots WebGL slots free after '
          '$timeout; this suite may hit the context cap.');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
