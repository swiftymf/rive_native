@TestOn('!browser')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../src/batch_rivs_manifest.dart';

void main() {
  test('batch_rivs_manifest.dart matches test/assets/batch_rivs contents', () {
    final onDisk = Directory('test/assets/batch_rivs')
        .listSync()
        .whereType<File>()
        .map((f) => path.basename(f.path))
        .where((name) => path.extension(name) == '.riv')
        .toList()
      ..sort();

    expect(
      List.of(batchRivManifest)..sort(),
      onDisk,
      reason: 'test/src/batch_rivs_manifest.dart is out of date — update it '
          'to match test/assets/batch_rivs so the web tests cover the same '
          'files.',
    );
  });
}
