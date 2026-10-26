@TestOn('!browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/allocation_contract.dart';
import 'src/headless_support.dart';
import 'src/utils.dart';

/// VM half of the cross-platform allocation contract (see
/// `src/allocation_contract.dart`): every case is asserted against the *real*
/// backing allocated by the headless Metal texture through the full
/// high-level pipeline ([rive.RiveArtboardWidget] rendering `rewards.riv`).
/// The chrome twin is `allocation_contract_web_test.dart`.
void main() {
  const dpr = 2.0;
  const layout = Size(100, 80);

  group('allocation contract (VM, real headless allocations)', () {
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

    for (final contractCase in allocationContractCases) {
      testWidgets(contractCase.name, (tester) async {
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          Center(
            child: Transform(
              transform: Matrix4.diagonal3Values(
                contractCase.ancestorScaleX,
                contractCase.ancestorScaleY,
                1,
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: layout.width,
                height: layout.height,
                child: rive.RiveArtboardWidget(
                  artboard: file.defaultArtboard()!,
                  painter: rive.StateMachinePainter(),
                  renderResolution: contractCase.resolution,
                ),
              ),
            ),
          ),
        );
        // Settle the ancestor-scale measure → relayout round trip.
        await tester.pump();

        final texture =
            (tester.renderObject(find.byType(rive.RiveArtboardWidget))
                    as rive.RiveNativeRenderBox)
                .renderTexture;
        final expected = expectedBacking(
          contractCase,
          baseWidth: layout.width,
          baseHeight: layout.height,
          dpr: dpr,
        );
        expect(texture.actualWidth, expected.width.round());
        expect(texture.actualHeight, expected.height.round());
      });
    }
  }, skip: headlessRendererSupported ? false : headlessSkipReason);
}
