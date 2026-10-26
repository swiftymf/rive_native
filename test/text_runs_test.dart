// ignore_for_file: deprecated_member_use_from_same_package


import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

/// Expected data for a text run
class ExpectedTextRun {
  final String name;
  final String value;
  final String path;

  const ExpectedTextRun({
    required this.name,
    required this.value,
    this.path = '',
  });

  /// Creates a composite key from name and path
  /// Format: `path/name` or just `name` if path is empty
  String get key => path.isEmpty ? name : '$path/$name';
}

void main() {
  test('text run get/set', () async {
    final bytes = loadFile('assets/text_run_test.riv');
    final riveFactory = rive.Factory.flutter;
    final riveFile = await rive.File.decode(
      bytes,
      riveFactory: riveFactory,
    );
    expect(riveFile, isNotNull);

    final artboard = riveFile!.defaultArtboard();
    expect(artboard, isNotNull);

    const runName = 'uniqueName';

    expect(artboard!.setText('doesNotExist', 'New Value'), false);
    expect(artboard.getText(runName), 'Initial Value');
    expect(artboard.setText(runName, 'New Value'), true);
    expect(artboard.getText(runName), 'New Value');
    expect(artboard.setText(runName, 'New Value', path: 'pathDoesNotExist'),
        false);
  });

  test('text run get/set nested', () async {
    final bytes = loadFile('assets/runtime_nested_text_runs.riv');
    final riveFactory = rive.Factory.flutter;
    final riveFile = await rive.File.decode(
      bytes,
      riveFactory: riveFactory,
    );
    expect(riveFile, isNotNull);
    final artboard = riveFile!.defaultArtboard();
    expect(artboard, isNotNull);
    expect(artboard!.setText('doesNotExist', 'New Value', path: 'path'), false);

    _nestedTextRunHelper(artboard, "ArtboardBRun", "ArtboardB-1",
        "Artboard B Run", "ArtboardB-1");
    _nestedTextRunHelper(artboard, "ArtboardBRun", "ArtboardB-2",
        "Artboard B Run", "ArtboardB-2");
    _nestedTextRunHelper(artboard, "ArtboardCRun", "ArtboardB-1/ArtboardC-1",
        "Artboard C Run", "ArtboardB-1/C-1");
    _nestedTextRunHelper(artboard, "ArtboardCRun", "ArtboardB-1/ArtboardC-2",
        "Artboard C Run", "ArtboardB-1/C-2");
    _nestedTextRunHelper(artboard, "ArtboardCRun", "ArtboardB-2/ArtboardC-1",
        "Artboard C Run", "ArtboardB-2/C-1");
    _nestedTextRunHelper(artboard, "ArtboardCRun", "ArtboardB-2/ArtboardC-2",
        "Artboard C Run", "ArtboardB-2/C-2");
  });

  test('get all text runs', () async {
    final bytes = loadFile('assets/get_all_text_runs_test.riv');
    final riveFactory = rive.Factory.flutter;
    final riveFile = await rive.File.decode(
      bytes,
      riveFactory: riveFactory,
    );
    expect(riveFile, isNotNull);

    final artboard = riveFile!.defaultArtboard();
    expect(artboard, isNotNull);

    // Get all text runs
    final textRuns = artboard!.textRuns;

    // Should have 8 text runs
    expect(textRuns.length, 10);

    // Define expected text runs with their values and paths
    // Key is a combination of name and path (name|path format)
    final expectedRunsList = [
      const ExpectedTextRun(
        name: 'Run 1 name',
        value: 'run 1 value',
        path: '',
      ),
      const ExpectedTextRun(
        name: 'Run 2 name',
        value: 'run 2 value',
        path: '',
      ),
      const ExpectedTextRun(
        name: 'Run 3 name',
        value: 'run 3 value',
        path: '',
      ),
      const ExpectedTextRun(
        name: 'Run 4 name',
        value: 'run 4 value',
        path: '',
      ),
      const ExpectedTextRun(
        name: 'Run 5 name',
        value: 'run 5 value',
        path: '',
      ),
      const ExpectedTextRun(
        name: 'Nested1 Run 1',
        value: 'nested1 run 1 value',
        path: 'nested1',
      ),
      const ExpectedTextRun(
        name: 'Nested2 Run 1',
        value: 'nested 2 run 1 value',
        path: 'nested1/nested2-1',
      ),
      const ExpectedTextRun(
        name: 'Nested2 Run 2',
        value: 'nested 2 run 2 value',
        path: 'nested1/nested2-1',
      ),
      const ExpectedTextRun(
        name: 'Nested2 Run 1',
        value: 'nested 2 run 1 value',
        path: 'nested1/nested2-2',
      ),
      const ExpectedTextRun(
        name: 'Nested2 Run 2',
        value: 'nested 2 run 2 value',
        path: 'nested1/nested2-2',
      ),
    ];

    // Build map from list using composite key
    final expectedRuns = <String, ExpectedTextRun>{
      for (final expected in expectedRunsList) expected.key: expected,
    };

    // Verify each expected text run exists with the correct initial value and path
    // Use name + path as unique identifier to find expected value
    final foundKeys = <String>{};
    for (final textRun in textRuns) {
      // Create composite key from text run's path and name
      // Format: `path/name` or just `name` if path is empty
      final key = textRun.path.isEmpty
          ? textRun.name
          : '${textRun.path}/${textRun.name}';

      // Look up expected value using the composite key
      final expected = expectedRuns[key];

      if (expected != null) {
        expect(textRun.text, expected.value);
        expect(textRun.path, expected.path);
        foundKeys.add(key);
      }
    }

    // Verify all expected runs were found
    for (final expected in expectedRunsList) {
      expect(foundKeys, contains(expected.key),
          reason:
              'Expected text run "${expected.name}" with path "${expected.path}" not found');
    }

    // Test setting text values
    for (int i = 1; i <= 5; i++) {
      final name = 'Run $i name';
      final path = '';
      final newValue = 'updated value $i';

      // Create the composite key
      // Format: `path/name` or just `name` if path is empty
      final key = path.isEmpty ? name : '$path/$name';
      final expected = expectedRuns[key]!;

      final textRun = textRuns.firstWhere(
        (tr) => tr.name == name && tr.path == path,
      );
      textRun.text = newValue;
      expect(textRun.text, newValue);

      // Verify path hasn't changed
      expect(textRun.path, expected.path);
    }

    // Verify changes persist through artboard
    final textRunsAgain = artboard.textRuns;
    for (int i = 1; i <= 5; i++) {
      final name = 'Run $i name';
      final path = '';
      final expectedUpdatedValue = 'updated value $i';

      // Create the composite key
      // Format: `path/name` or just `name` if path is empty
      final key = path.isEmpty ? name : '$path/$name';
      final expected = expectedRuns[key]!;

      final textRun = textRunsAgain.firstWhere(
        (tr) => tr.name == name && tr.path == path,
        orElse: () =>
            throw Exception('Text run "$name" with path "$path" not found'),
      );

      expect(textRun.text, expectedUpdatedValue);
      // Path should remain the same
      expect(textRun.path, expected.path);
    }

    // Clean up - dispose all text runs
    for (final textRun in textRuns) {
      textRun.dispose();
    }
    for (final textRun in textRunsAgain) {
      textRun.dispose();
    }
  });

  test('get all text runs - empty artboard', () async {
    final bytes = loadFile('assets/get_all_text_runs_test.riv');
    final riveFactory = rive.Factory.flutter;
    final riveFile = await rive.File.decode(
      bytes,
      riveFactory: riveFactory,
    );
    expect(riveFile, isNotNull);

    final artboard = riveFile!.artboard('Empty');
    final textRuns = artboard!.textRuns;
    expect(textRuns.length, 0);
  });
}

void _nestedTextRunHelper(rive.Artboard artboard, String name, String path,
    String originalValue, String updatedValue) {
  // Assert the original value is correct
  expect(artboard.getText(name, path: path), originalValue);

  // Update the value and confirm it was updated
  expect(artboard.setText(name, updatedValue, path: path), true);
  expect(artboard.getText(name, path: path), updatedValue);
}
