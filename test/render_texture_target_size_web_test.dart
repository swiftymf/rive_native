@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/render_texture_probe.dart';

/// Web counterpart to `render_texture_target_size_test.dart`.
///
/// The canvas backing store is sized in the wasm glue on every clear (see
/// `native/platform/wasm/init.js`) from the policy the render object pushes:
/// under the default [rive.RenderResolution.display] the element's layout ×
/// `window.devicePixelRatio` × the measured ancestor paint scale — the same
/// policy as native — while [rive.RenderResolution.layout] keeps ancestor
/// transforms composite-only and [rive.RenderResolution.fixed] pins an exact
/// physical size.
void main() {
  testWidgets(
      'display (default) measures the ancestor paint scale, like native',
      (tester) async {
    final (texture, painter) = makeProbe();

    const probeKey = ValueKey('rive-web-probe');
    await pumpSettled(
      tester,
      host(
        texture.widget(painter: painter, key: probeKey),
        transform: Matrix4.diagonal3Values(3.0, 3.0, 1.0),
      ),
    );

    final renderBox =
        tester.renderObject(find.byKey(probeKey)) as rive.RiveNativeRenderBox;
    expect(renderBox.desiredTransformWidthScale, 3.0);
    expect(renderBox.desiredTransformHeightScale, 3.0);
  });

  testWidgets(
      'display: canvas backing store follows the on-screen footprint '
      '(layout × DPR × ancestor scale), per axis', (tester) async {
    // Baseline: identical layout, no transform.
    final (flat, flatPainter) = makeProbe();

    await pumpSettled(tester, host(flat.widget(painter: flatPainter)));
    final flatWidth = flat.actualWidth;
    final flatHeight = flat.actualHeight;

    // Guard against a vacuous pass: the glue's resize must actually have run.
    // (A disconnected/zero-width canvas falls back to 1×1.)
    expect(flatWidth, greaterThan(1),
        reason: 'expected the wasm clear to have sized the canvas backing');
    expect(flatHeight, greaterThan(1));

    // Same layout under a non-uniform (1.25×, 1.5×) ancestor scale. The
    // scales are deliberately modest: in this harness the platform view
    // canvas is never adopted into the widget's slot, so its client size is
    // the document body — large enough that bigger multipliers would trip
    // the maxTextureLogicalSize clamp and break the simple ratio math here.
    final (scaled, scaledPainter) = makeProbe();

    await pumpSettled(
      tester,
      host(
        scaled.widget(painter: scaledPainter),
        transform: Matrix4.diagonal3Values(1.25, 1.5, 1.0),
      ),
    );

    // ±2 absorbs the independent rounding of the two backing computations.
    expect(scaled.actualWidth.toDouble(), closeTo(flatWidth * 1.25, 2));
    expect(scaled.actualHeight.toDouble(), closeTo(flatHeight * 1.5, 2));
  });

  testWidgets(
      'layout: backing store is independent of ancestor transforms '
      '(display scale stays composite-only)', (tester) async {
    final (flat, flatPainter) = makeProbe();

    await pumpSettled(
      tester,
      host(flat.widget(
        painter: flatPainter,
        resolution: const rive.RenderResolution.layout(),
      )),
    );
    final flatWidth = flat.actualWidth;
    final flatHeight = flat.actualHeight;
    expect(flatWidth, greaterThan(1));

    final (scaled, scaledPainter) = makeProbe();

    await pumpSettled(
      tester,
      host(
        scaled.widget(
          painter: scaledPainter,
          resolution: const rive.RenderResolution.layout(),
        ),
        transform: Matrix4.diagonal3Values(3.0, 3.0, 1.0),
      ),
    );

    expect(scaled.actualWidth, flatWidth);
    expect(scaled.actualHeight, flatHeight);
  });

  testWidgets('RenderResolution.layout(scale) scales the canvas backing store',
      (tester) async {
    final (full, fullPainter) = makeProbe();

    await pumpSettled(tester, host(full.widget(painter: fullPainter)));
    final fullWidth = full.actualWidth;
    final fullHeight = full.actualHeight;
    expect(fullWidth, greaterThan(1));

    final (half, halfPainter) = makeProbe();

    await pumpSettled(
      tester,
      host(half.widget(
        painter: halfPainter,
        resolution: const rive.RenderResolution.layout(scale: 0.5),
      )),
    );

    expect(half.actualWidth, (fullWidth / 2).round());
    expect(half.actualHeight, (fullHeight / 2).round());
  });

  testWidgets(
      'RenderResolution.fixed sets the exact backing size, transforms ignored',
      (tester) async {
    final (texture, painter) = makeProbe();

    await pumpSettled(
      tester,
      host(
        texture.widget(
          painter: painter,
          resolution: const rive.RenderResolution.fixed(64, 32),
        ),
        transform: Matrix4.diagonal3Values(3.0, 3.0, 1.0),
      ),
    );

    expect(texture.actualWidth, 64);
    expect(texture.actualHeight, 32);
  });
}
