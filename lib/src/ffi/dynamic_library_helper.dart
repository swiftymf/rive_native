import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rive_native/platform.dart' as rive;

// ignore: avoid_classes_with_only_static_members
abstract class DynamicLibraryHelper {
  static final DynamicLibrary nativeLib = open();

  static void _printTestFailedMessage(String path, String platform) {
    const red = '\x1B[31m';
    const yellow = '\x1B[33m';
    const cyan = '\x1B[36m';
    const bold = '\x1B[1m';
    const reset = '\x1B[0m';

    String message = '''
═════════════════════════════════════════════════════════════════════════════════════════
$red$bold  Rive Native: Failed to open dynamic library$reset
$yellow  Library: $path$reset      

  To fix this issue, run the following command:     
$cyan$bold    dart run rive_native:setup --verbose --clean --platform $platform$reset           
  
  See the troubleshooting section in the docs for more information:
$cyan$bold    https://rive.app/docs/runtimes/flutter/rive-native#troubleshooting$reset
═════════════════════════════════════════════════════════════════════════════════════════
''';
    debugPrint(message);
  }

  static DynamicLibrary open() {
    if (rive.Platform.instance.isTesting) {
      var rootPaths = [
        '',
        '../',
        '../../packages/rive_native/',
        'build/rive_native/', // rive_native package consumption tests
      ];
      if (Platform.isMacOS) {
        for (final path in rootPaths) {
          try {
            return DynamicLibrary.open(
              '${path}native/build/macosx/bin/debug_shared/librive_native.dylib',
            );

            // ignore: avoid_catching_errors
          } on ArgumentError catch (_) {}
        }
        _printTestFailedMessage('librive_native.dylib', 'macos');
      } else if (Platform.isLinux) {
        var libPaths = [
          'linux/bin/lib/debug_shared/librive_native.so',
          'native/build/linux/bin/lib/debug_shared/librive_native.so',
        ];
        for (final root in rootPaths) {
          for (final libPath in libPaths) {
            try {
              return DynamicLibrary.open('$root$libPath');
              // ignore: avoid_catching_errors
            } on ArgumentError catch (_) {}
          }
        }
        _printTestFailedMessage('librive_native.so', 'linux');
      } else if (Platform.isWindows) {
        var libPaths = [
          'windows/bin/lib/debug/rive_native.dll',
          'native/build/windows/bin/lib/debug/rive_native.dll',
        ];
        for (final root in rootPaths) {
          for (final libPath in libPaths) {
            try {
              return DynamicLibrary.open('$root$libPath');
              // ignore: avoid_catching_errors
            } on ArgumentError catch (_) {}
          }
        }
        _printTestFailedMessage('rive_native.dll', 'windows');
      }
    }

    if (Platform.isAndroid) {
      try {
        return _openAndroidDynamicLibraryWithFallback();
      } on ArgumentError catch (_) {
        _printTestFailedMessage('librive_native.so', 'android');
        rethrow;
      }
    } else if (Platform.isWindows) {
      try {
        return DynamicLibrary.open('rive_native.dll');
      } on ArgumentError catch (_) {
        _printTestFailedMessage('rive_native.dll', 'windows');
        rethrow;
      }
    } else if (Platform.isLinux) {
      try {
        return DynamicLibrary.open('librive_native_plugin.so');
      } on ArgumentError catch (_) {
        _printTestFailedMessage('librive_native_plugin.so', 'linux');
        rethrow;
      }
    }
    return DynamicLibrary.process();
  }

  static DynamicLibrary _openAndroidDynamicLibraryWithFallback() {
    try {
      return DynamicLibrary.open('librive_native.so');
      // ignore: avoid_catching_errors
    } on ArgumentError {
      // On some (especially old) Android devices, we somehow can't dlopen
      // libraries shipped with the apk. We need to find the full path of the
      // library (/data/data/<id>/lib/librive_text.so) and open that one.
      // For details, see https://github.com/simolus3/sqlite3.dart/issues/29
      final appIdAsBytes = File('/proc/self/cmdline').readAsBytesSync();

      // app id ends with the first \0 character in here.
      final endOfAppId = max(appIdAsBytes.indexOf(0), 0);
      final appId = String.fromCharCodes(appIdAsBytes.sublist(0, endOfAppId));
      return DynamicLibrary.open('/data/data/$appId/lib/librive_native.so');
    }
  }
}
