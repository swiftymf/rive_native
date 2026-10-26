import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';

import 'package:rive_native/src/rive_native_web.dart' show RiveWasm;

js.JSFunction _fn(String name) {
  final module = RiveWasm.module;
  if (module == null) {
    throw StateError(
        'Rive wasm module is not linked; await RiveNative.init() first.');
  }
  final fn = module.getProperty(name.toJS);
  if (fn.isUndefinedOrNull) {
    throw StateError(
        '$name is not exported by the wasm module. Debug symbols only exist '
        'in debug builds — point RIVE_NATIVE_WASM_HOST at a debug wasm '
        '(./build.sh wasm single-threaded flutter-runtime).');
  }
  return fn as js.JSFunction;
}

// Raw `_name` exports are plain wasm functions: i32 return values arrive as
// JS numbers (a C `bool` comes back as 0/1, not a JS boolean).
int _callInt(String name) =>
    (_fn(name).callAsFunction(null) as js.JSNumber).toDartInt;

bool builtWithRiveTools() => _callInt('_builtWithRiveTools') != 0;

int debugFileCount() => _callInt('_debugFileCount');
int debugArtboardCount() => _callInt('_debugArtboardCount');
int debugStateMachineCount() => _callInt('_debugStateMachineCount');
int debugAnimationCount() => _callInt('_debugAnimationCount');
int debugViewModelRuntimeCount() => _callInt('_debugViewModelRuntimeCount');
int debugViewModelInstanceRuntimeCount() =>
    _callInt('_debugViewModelInstanceRuntimeCount');
int debugViewModelInstanceValueRuntimeCount() =>
    _callInt('_debugViewModelInstanceValueRuntimeCount');
int debugYogaNodeCount() => _callInt('_debugYogaNodeCount');
int debugBindableArtboardCount() => _callInt('_debugBindableArtboardCount');
