@TestOn('browser')
// Draws real artboard content through WebGL — the publishing CI runner's
// virtualized GPU cannot compile the Rive ubershader (wasm abort in
// async_pipeline_manager tryGetPipeline), so that job excludes this tag
// until the renderer degrades gracefully there. Runs everywhere else.
@Tags(['webgl_content'])
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

/// Web pixels-on-screen smoke for the Rive Renderer: decode a single `.riv`
/// with `Factory.rive`, render it through the real WebGL pipeline, and read
/// the canvas backing store back via `toImage()` (canvas `toBlob`). Proves
/// this runtime's integration renders on web; renderer fidelity per backend
/// is the C++ golden suite's concern.
void main() {
  testWidgets('Factory.rive renders a .riv into the WebGL backing',
      (tester) async {
    // On chrome, per-exception dumps only reach the browser console; the
    // terminal sees just the aggregated "Multiple exceptions" banner. Mirror
    // every FlutterError to the terminal via print so CI logs are usable.
    final mirrored = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      mirrored.add(details);
      previousOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = previousOnError;
      for (final details in mirrored) {
        // ignore: avoid_print
        print('═══ web smoke exception ═══\n'
            '${details.exceptionAsString()}\n${details.stack}');
      }
    });

    final file = await tester.runAsync(() => rive.File.decode(
          loadFile('assets/rewards.riv'),
          riveFactory: rive.Factory.rive,
        ));
    expect(file, isNotNull);
    addTearDown(file!.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 80,
            child: rive.RiveArtboardWidget(
              artboard: file.defaultArtboard()!,
              painter: rive.StateMachinePainter(fit: rive.Fit.fill),
            ),
          ),
        ),
      ),
    );
    // Settle the layout → backing-resize → paint round trip.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // On web `texture.widget()` is a Stack (HtmlElementView + view), so the
    // render box can't be reached through find.byType(RiveArtboardWidget);
    // there is exactly one RiveNativeRenderBox in the tree (allRenderObjects
    // reports it once per wrapping element — dedupe).
    final texture = tester.allRenderObjects
        .whereType<rive.RiveNativeRenderBox>()
        .toSet()
        .single
        .renderTexture;
    // In this harness the canvas sizes to the document body, not the widget;
    // only relative positions are meaningful.
    expect(texture.actualWidth, greaterThan(1),
        reason: 'expected the backing to have been sized');
    expect(texture.actualHeight, greaterThan(1));

    final (pixels, width, height) = (await tester.runAsync(() async {
      final image = await texture.toImage();
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      return (data!.buffer.asUint8List(), image.width, image.height);
    }))!;

    List<int> rgbaAt(double fx, double fy) {
      final i = ((fy * height).floor() * width + (fx * width).floor()) * 4;
      return [pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
    }

    void expectNear(List<int> actual, List<int> expected) {
      for (var i = 0; i < 4; i++) {
        expect(actual[i], closeTo(expected[i], 4),
            reason: 'channel $i of $actual vs $expected');
      }
    }

    // The rewards background gradient, pinned by pixel probe on WebGL; the
    // small per-channel tolerance absorbs backend precision differences.
    expectNear(rgbaAt(0.05, 0.05), const [50, 34, 50, 255]);
    expectNear(rgbaAt(0.5, 0.5), const [75, 58, 78, 255]);
    expectNear(rgbaAt(0.5, 0.94), const [37, 20, 36, 255]);
  });
}
