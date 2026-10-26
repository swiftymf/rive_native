@TestOn('!browser')
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/headless_support.dart';
import 'src/utils.dart';

/// End-to-end widget tests for `Factory.rive` on the VM, backed by the
/// headless Metal render texture: pump the real high-level widget
/// ([rive.RiveArtboardWidget] rendering `rewards.riv`) and assert the
/// *actual* allocations the pipeline performs, plus pixel readback through
/// `toImage()`.
///
/// Covers only what `allocation_contract_test.dart`'s case table can't
/// express (FittedBox measurement, reallocation behavior, pixel readback);
/// the per-policy allocation matrix lives there.
///
/// Skipped when the native lib lacks the headless symbols (only
/// `./build.sh shared` without `flutter_runtime` exports them, macOS only).
void main() {
  rive.RenderTexture textureOf(WidgetTester tester) =>
      (tester.renderObject(find.byType(rive.RiveArtboardWidget))
              as rive.RiveNativeRenderBox)
          .renderTexture;

  void setDpr(WidgetTester tester, double dpr) {
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Same tree shape as the target-size probe tests: a fixed-size box,
  /// optionally under an ancestor transform.
  Widget host(
    Widget child, {
    Matrix4? transform,
    double width = 100,
    double height = 80,
  }) =>
      Center(
        child: Transform(
          transform: transform ?? Matrix4.identity(),
          alignment: Alignment.center,
          child: SizedBox(width: width, height: height, child: child),
        ),
      );

  group('headless Factory.rive widget', () {
    late rive.File file;

    setUpAll(() async {
      expect(await rive.RiveNative.init(), isTrue);
      final decoded = await rive.File.decode(
        loadFile('assets/rewards.riv'),
        riveFactory: rive.Factory.rive,
      );
      expect(decoded, isNotNull);
      file = decoded!;
    });

    tearDownAll(() => file.dispose());

    Widget riveWidget({
      rive.RenderResolution resolution = rive.RenderResolution.defaultValue,
    }) =>
        rive.RiveArtboardWidget(
          artboard: file.defaultArtboard()!,
          painter: rive.StateMachinePainter(fit: rive.Fit.fill),
          renderResolution: resolution,
        );

    testWidgets(
        'display: FittedBox upscale allocates the display footprint, '
        'not the layout size', (tester) async {
      setDpr(tester, 2.0);

      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 400,
            height: 320,
            child: FittedBox(
              child: SizedBox(
                width: 100,
                height: 80,
                child: riveWidget(),
              ),
            ),
          ),
        ),
      );
      // First paint measures the ancestor scale and schedules a relayout.
      await tester.pump();

      final texture = textureOf(tester);
      expect(texture.actualWidth, 800);
      expect(texture.actualHeight, 640);
    });

    testWidgets(
        'fixed: exact physical size, unaffected by DPR/transform/layout',
        (tester) async {
      setDpr(tester, 2.0);

      await tester.pumpWidget(host(
        riveWidget(resolution: const rive.RenderResolution.fixed(64, 32)),
        transform: Matrix4.diagonal3Values(3.0, 3.0, 1.0),
      ));
      await tester.pump();

      final texture = textureOf(tester);
      expect(texture.actualWidth, 64);
      expect(texture.actualHeight, 32);

      // A layout size change must not reallocate a fixed texture.
      await tester.pumpWidget(host(
        riveWidget(resolution: const rive.RenderResolution.fixed(64, 32)),
        transform: Matrix4.diagonal3Values(3.0, 3.0, 1.0),
        width: 250,
        height: 200,
      ));
      await tester.pump();

      expect(texture.actualWidth, 64);
      expect(texture.actualHeight, 32);
    });

    testWidgets('toImage: artboard content lands in the backing store',
        (tester) async {
      setDpr(tester, 2.0);

      await tester.pumpWidget(host(riveWidget()));
      // Let the post-creation markNeedsPaint frame draw into the texture.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final texture = textureOf(tester);
      // Headless invariant: never composited, so the id stays -1.
      expect(texture.textureId, -1);
      expect(texture.isReady, isTrue);
      expect(texture.actualWidth, 200);
      expect(texture.actualHeight, 160);

      final pixels = await tester.runAsync(() async {
        final image = await texture.toImage();
        expect(image.width, 200);
        expect(image.height, 160);
        final data =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        return data!.buffer.asUint8List();
      });

      List<int> rgbaAt(int x, int y) {
        final i = (y * 200 + x) * 4;
        return [pixels![i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
      }

      // The rewards scene's background gradient, pinned by pixel probe —
      // real artboard content at deterministic positions (atomic mode keeps
      // rasterization identical across runs).
      expect(rgbaAt(8, 8), [50, 34, 50, 255]);
      expect(rgbaAt(100, 80), [76, 58, 78, 255]);
      expect(rgbaAt(100, 150), [36, 19, 35, 255]);
    });
  }, skip: headlessRendererSupported ? false : headlessSkipReason);
}
