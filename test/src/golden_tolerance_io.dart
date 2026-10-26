import 'package:flutter_test/flutter_test.dart';

import '../goldens/src/golden_comparator_io.dart';

/// Wraps the active [goldenFileComparator] with [AppFileComparator] so the
/// same diff tolerance used on the VM applies when this code runs inside the
/// host-side golden comparator process that `flutter test --platform chrome`
/// spawns (it loads `flutter_test_config.dart` around its compare loop).
///
/// Harmless for regular VM suites: `expectGoldenMatches` replaces the
/// comparator per call anyway.
void applyGoldenTolerance() {
  final current = goldenFileComparator;
  if (current is LocalFileComparator && current is! AppFileComparator) {
    goldenFileComparator = AppFileComparator(
      current.basedir.resolve('placeholder_test.dart').toString(),
    );
  }
}
