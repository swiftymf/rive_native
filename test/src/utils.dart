/// Platform-conditional test utilities.
///
/// On the VM (`flutter test`) files are read straight from disk; in the
/// browser (`flutter test --platform chrome`) they are fetched from a local
/// static server. See `utils_web.dart` for the server setup.
library;

export 'utils_io.dart' if (dart.library.js_interop) 'utils_web.dart';
