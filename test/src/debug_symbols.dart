/// Debug-build-only native symbols used by tests to assert object lifecycles
/// (leak checks) and build flavor.
///
/// These functions only exist in debug builds of the native library / wasm
/// module (`#ifdef DEBUG` in native/src/rive_binding.cpp), so tests using
/// them must run against `./build.sh shared` (VM) or the debug wasm
/// (`./build.sh wasm single-threaded flutter-runtime`, host `.../debug/`).
library;

export 'debug_symbols_io.dart'
    if (dart.library.js_interop) 'debug_symbols_web.dart';
