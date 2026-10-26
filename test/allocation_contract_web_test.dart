@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/allocation_contract.dart';
import 'src/render_texture_probe.dart';

/// Chrome half of the cross-platform allocation contract (see
/// `src/allocation_contract.dart`): the same cases as
/// `allocation_contract_test.dart`, asserted against the real WebGL canvas
/// backing. In this harness the canvas client size is the document body (the
/// platform view is never adopted into its slot), so every expectation is a
/// ratio against a measured display-identity baseline — the DPR term cancels
/// out of the ratio.
void main() {
  // texture.widget() is a Stack (HtmlElementView + view) and needs an
  // ambient Directionality.
  Widget host(Widget child, {double scaleX = 1, double scaleY = 1}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Transform(
            transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
            alignment: Alignment.center,
            child: SizedBox(width: 100, height: 80, child: child),
          ),
        ),
      );

  testWidgets('allocation contract (chrome, real WebGL backing)',
      (tester) async {
    // Baseline: display policy, identity tree → base extent × DPR. Measured
    // once; probes are disposed per phase so the pooled canvas/WebGL context
    // is recycled instead of accumulating one live context per case.
    final base = rive.RiveNative.instance.makeRenderTexture();
    final basePainter = NoopTexturePainter();
    await pumpSettled(tester, host(base.widget(painter: basePainter)));

    // Guard against a vacuous pass: the resize must actually have run.
    // (A disconnected/zero-width canvas falls back to 1×1.)
    expect(base.actualWidth, greaterThan(1),
        reason: 'expected the backing to have been sized');
    expect(base.actualHeight, greaterThan(1));
    final baseWidth = base.actualWidth.toDouble();
    final baseHeight = base.actualHeight.toDouble();
    await tester.pumpWidget(const SizedBox());
    base.dispose();
    basePainter.dispose();

    for (final contractCase in allocationContractCases) {
      final texture = rive.RiveNative.instance.makeRenderTexture();
      final painter = NoopTexturePainter();
      await pumpSettled(
        tester,
        host(
          texture.widget(
            painter: painter,
            resolution: contractCase.resolution,
          ),
          scaleX: contractCase.ancestorScaleX,
          scaleY: contractCase.ancestorScaleY,
        ),
      );

      // The DPR term is already inside the measured baseline; pass 1.
      final expected = expectedBacking(
        contractCase,
        baseWidth: baseWidth,
        baseHeight: baseHeight,
        dpr: 1,
      );
      if (expected.exact) {
        expect(texture.actualWidth, expected.width.toInt(),
            reason: contractCase.name);
        expect(texture.actualHeight, expected.height.toInt(),
            reason: contractCase.name);
      } else {
        // ±2 absorbs the independent rounding of the backing computations.
        expect(texture.actualWidth.toDouble(), closeTo(expected.width, 2),
            reason: contractCase.name);
        expect(texture.actualHeight.toDouble(), closeTo(expected.height, 2),
            reason: contractCase.name);
      }

      await tester.pumpWidget(const SizedBox());
      texture.dispose();
      painter.dispose();
    }
  });
}
