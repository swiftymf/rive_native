import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';

/// Loads a Rive file from the assets sub-folder
Uint8List loadFile(String filename) {
  final file = File(
      './${Directory.current.path.endsWith('/test') ? '' : 'test/'}$filename');
  if (!file.existsSync()) {
    throw Exception('Rive file does not exist at path: $filename');
  }
  return file.readAsBytesSync();
}

/// Loads in all the files in the batch_rivs directory ('test/assets/batch_rivs')
List<FileTesterWrapper> batchRiveFilesToTest() {
  final directory = Directory('test/assets/batch_rivs');

  return directory
      .listSync()
      .whereType<File>()
      .map((file) => basename(file.path))
      .where((name) => extension(name) == '.riv')
      .map((name) => FileTesterWrapper(
            bytes: loadFile('assets/batch_rivs/$name'),
            fileName: name,
          ))
      .toList();
}

class FileTesterWrapper {
  final Uint8List bytes;
  final String fileName;

  FileTesterWrapper({
    required this.bytes,
    required this.fileName,
  });
}
