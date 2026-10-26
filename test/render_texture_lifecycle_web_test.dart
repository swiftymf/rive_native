@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/render_texture_probe.dart';
import 'src/utils.dart';
import 'src/web_context_probe.dart';

/// Regression lock for the web WebGL context lifecycle.
///
/// Browsers cap live WebGL contexts (~16 per process); when the cap is hit
/// the browser evicts the least-recently-used context or fails creation
/// outright. Before the bounded pool, `dispose()` pooled every canvas
/// forever, so live contexts accumulated to the suite/app high-water mark
/// and context-heavy runs died mid-way with "failed to create a WebGL2
/// context".
void main() {
  final poolCap = debugWebRenderTexturePoolCap;
  // The shared offscreen feature-probe context the glue keeps.
  const offscreenContexts = 1;

  test('mass dispose keeps at most the pool cap of live contexts', () {
    // Warm up the offscreen probe so the baseline below is stable.
    final warmup = rive.RiveNative.instance.makeRenderTexture();
    warmup.dispose();

    final baseline = liveGLContextCount();
    expect(baseline, lessThanOrEqualTo(offscreenContexts + poolCap),
        reason: 'earlier activity must not leak past the pool bound');

    final churn = poolCap * 2 + 2;
    final textures = List.generate(
        churn, (_) => rive.RiveNative.instance.makeRenderTexture());
    // All alive at once: every texture owns a live context.
    expect(liveGLContextCount(), greaterThanOrEqualTo(churn),
        reason: 'live textures each hold a WebGL context');

    for (final texture in textures) {
      texture.dispose();
    }
    expect(liveGLContextCount(), lessThanOrEqualTo(offscreenContexts + poolCap),
        reason: 'dispose must genuinely release contexts beyond the pool cap');
  });

  test('releaseRenderResources drains pooled contexts to zero', () {
    // Populate the pool.
    final textures = List.generate(
        poolCap, (_) => rive.RiveNative.instance.makeRenderTexture());
    for (final texture in textures) {
      texture.dispose();
    }
    expect(liveGLContextCount(), greaterThan(0));

    rive.RiveNative.instance.releaseRenderResources();
    expect(liveGLContextCount(), 0,
        reason: 'an idle page must be able to drop every WebGL context');

    // Everything is recreated on demand: offscreen probe + fresh canvas.
    final fresh = rive.RiveNative.instance.makeRenderTexture();
    expect(liveGLContextCount(), offscreenContexts + 1);
    expect(fresh.isDisposed, isFalse);
    fresh.dispose();
  });

  test('a texture whose context was evicted is not pooled on dispose', () {
    rive.RiveNative.instance.releaseRenderResources();

    final texture = rive.RiveNative.instance.makeRenderTexture();
    // Offscreen probe + this texture.
    expect(liveGLContextCount(), offscreenContexts + 1);
    expect(texture.isReady, isTrue);

    debugLoseWebGLContext(texture);
    expect(texture.isReady, isFalse,
        reason: 'a lost context cannot be painted');

    texture.dispose();
    expect(liveGLContextCount(), offscreenContexts,
        reason: 'a dead texture must be released, not pooled');
    expect(texture.isDisposed, isTrue);
  });

  test('a pooled texture whose context was evicted is purged on reuse', () {
    rive.RiveNative.instance.releaseRenderResources();

    final texture = rive.RiveNative.instance.makeRenderTexture();
    texture.dispose(); // Healthy: goes to the pool.
    expect(liveGLContextCount(), offscreenContexts + 1);

    // The browser evicts the context while the texture sits in the pool.
    debugLoseWebGLContext(texture);

    final fresh = rive.RiveNative.instance.makeRenderTexture();
    expect(identical(fresh, texture), isFalse,
        reason: 'a dead pooled texture must never be handed back out');
    expect(texture.isDisposed, isTrue);
    expect(fresh.isReady, isTrue);
    expect(liveGLContextCount(), offscreenContexts + 1,
        reason: 'purged the dead context, created one fresh');
    fresh.dispose();
  });

  // Draws real content, so flushing needs the ubershader — which the
  // GPU-less publishing CI runner cannot compile (see the webgl_content
  // exclusion there). The flush cannot be skipped: ~RenderContext asserts
  // on an unflushed frame. Runs everywhere else.
  test('image teardown survives its upload context being released', () async {
    rive.RiveNative.instance.releaseRenderResources();

    final imageBytes = loadFile('assets/images/referenced-image-2929282.png');
    final image = await rive.Factory.rive.decodeImage(imageBytes);
    expect(image, isNotNull);
    // decodeImage returns before the browser-side DOM decode lands; the
    // upload can only happen on a draw after width/height arrive.
    while (image!.width == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    // Drawing uploads the image's GPU texture into this texture's WebGL
    // context (synchronously, in the draw call's prep step).
    final texture = rive.RiveNative.instance.makeRenderTexture();
    texture.clear(const Color(0xFF000000));
    texture.renderer.drawImage(image, BlendMode.srcOver, 1);
    texture.flush(1);

    // Kill the upload context: dispose pools the texture, the drain
    // releases it (and the offscreen probe).
    texture.dispose();
    rive.RiveNative.instance.releaseRenderResources();
    expect(liveGLContextCount(), 0);

    // The GPU texture died with its context. Disposing the image must
    // tear down through the dead context handle without touching a live
    // (or undefined) GL context — Emscripten's glDelete* dereference the
    // *current* context, so an unregistered handle here used to crash with
    // "Cannot read properties of undefined (reading 'deleteTexture')".
    image.dispose();

    // And the world still works afterwards.
    final fresh = rive.RiveNative.instance.makeRenderTexture();
    expect(fresh.isReady, isTrue);
    fresh.dispose();
  }, tags: ['webgl_content']);

  testWidgets('a fresh texture still renders after mass dispose',
      (tester) async {
    final (texture, painter) = makeProbe();

    await pumpSettled(tester, host(texture.widget(painter: painter)));

    // The wasm clear must have sized the canvas backing store — a dead
    // (released or never re-linked) renderer would leave the 1×1 fallback.
    expect(texture.actualWidth, greaterThan(1),
        reason: 'expected the wasm clear to have sized the canvas backing');
    expect(texture.actualHeight, greaterThan(1));
  });
}
