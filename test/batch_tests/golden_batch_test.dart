@Tags(['requires_newer_flutter'])
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../goldens/src/golden_comparator.dart';
import '../src/utils.dart';

/// The batch art is hairline-dense (1px arcs, tiny text), so cross-renderer
/// anti-aliasing differences between the web and the desktop baselines exceed
/// any tolerance that would still catch real regressions. On the web every
/// batch file is still decoded, pumped, and rendered (crash coverage); only
/// the pixel comparisons are skipped.
const _skipGoldens = kIsWeb;

void main() {
  /// Tests all rivs in the `test/assets/batch_rive` directory
  group('Golden - Batch tests riv files', () {
    List<FileTesterWrapper> riveFiles = [];

    setUpAll(() {
      // Read all files in the batch directory to be tested.
      riveFiles = batchRiveFilesToTest();
    });

    testWidgets('Animation default state machine render as expected',
        (WidgetTester tester) async {
      for (final file in riveFiles) {
        final fileName = file.fileName;
        final riveFile = await rive.File.decode(file.bytes,
            riveFactory: rive.Factory.flutter);
        if (riveFile == null) {
          throw Exception(
              'Could not decode file to load Rive file from $fileName');
        }

        final artboard = riveFile.defaultArtboard();

        if (artboard == null) {
          throw Exception('Failed to load artboard from file: $fileName');
        }

        final stateMachinePainter = rive.StateMachinePainter();

        await tester.pumpWidget(
          rive.RiveArtboardWidget(
            artboard: artboard,
            painter: stateMachinePainter,
          ),
        );

        // Render first frame of animation
        await tester.pump();
        if (!_skipGoldens) {
          await expectGoldenMatches(
            find.byType(rive.RiveArtboardWidget),
            '$fileName-01.png',
            reason:
                'Animation with filename: $fileName should render correctly',
          );
        }

        // Advance animation by a three quarters of a second
        await tester.pump(const Duration(milliseconds: 750));
        if (!_skipGoldens) {
          await expectGoldenMatches(
            find.byType(rive.RiveArtboardWidget),
            '$fileName-02.png',
            reason:
                'Animation with filename: $fileName should render correctly',
          );
        }

        // Advance animation by a two seconds
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        if (!_skipGoldens) {
          await expectGoldenMatches(
            find.byType(rive.RiveArtboardWidget),
            '$fileName-03.png',
            reason:
                'Animation with filename: $fileName should render correctly',
          );
        }
      }
    });
  });
}
