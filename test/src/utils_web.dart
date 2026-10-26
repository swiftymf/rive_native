import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'batch_rivs_manifest.dart';

/// Where the test assets are served from when running `flutter test
/// --platform chrome`. The server must serve the package root (so that
/// `test/assets/...` resolves) with CORS enabled, e.g.:
///
/// ```sh
/// cd packages/rive_native && npx http-server . -p 8283 --cors
/// ```
const _assetHost = String.fromEnvironment(
  'RIVE_TEST_ASSET_HOST',
  defaultValue: 'http://localhost:8283',
);

/// Loads a Rive file from the assets sub-folder.
///
/// Uses a synchronous XHR so the signature matches the `dart:io`
/// implementation that the rest of the test suite is written against.
/// Synchronous XHR is deprecated in browsers but still supported, and only
/// ever runs in the test harness.
Uint8List loadFile(String filename) {
  final request = web.XMLHttpRequest();
  request.open('GET', '$_assetHost/test/$filename', false);
  // Sync XHR forbids responseType 'arraybuffer'; use the x-user-defined
  // charset trick to smuggle bytes through responseText.
  request.overrideMimeType('text/plain; charset=x-user-defined');
  request.send();
  if (request.status != 200) {
    throw Exception(
        'Rive file does not exist at path: $filename (HTTP ${request.status} '
        'from $_assetHost — is the asset server running?)');
  }
  final text = request.responseText;
  final bytes = Uint8List(text.length);
  for (var i = 0; i < text.length; i++) {
    bytes[i] = text.codeUnitAt(i) & 0xff;
  }
  return bytes;
}

/// Directory listing is not available in the browser, so the batch files
/// come from a checked-in manifest (kept honest by `batch_manifest_test.dart`
/// on the VM).
List<FileTesterWrapper> batchRiveFilesToTest() => batchRivManifest
    .map((name) => FileTesterWrapper(
          bytes: loadFile('assets/batch_rivs/$name'),
          fileName: name,
        ))
    .toList();

class FileTesterWrapper {
  final Uint8List bytes;
  final String fileName;

  FileTesterWrapper({
    required this.bytes,
    required this.fileName,
  });
}
