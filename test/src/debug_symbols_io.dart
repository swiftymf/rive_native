import 'dart:ffi';

import 'package:rive_native/src/ffi/dynamic_library_helper.dart';

final DynamicLibrary _nativeLib = DynamicLibraryHelper.nativeLib;

int Function() _counter(String name) =>
    _nativeLib.lookup<NativeFunction<Uint32 Function()>>(name).asFunction();

final bool Function() builtWithRiveTools = _nativeLib
    .lookup<NativeFunction<Bool Function()>>('builtWithRiveTools')
    .asFunction();

final debugFileCount = _counter('debugFileCount');
final debugArtboardCount = _counter('debugArtboardCount');
final debugStateMachineCount = _counter('debugStateMachineCount');
final debugAnimationCount = _counter('debugAnimationCount');
final debugViewModelRuntimeCount = _counter('debugViewModelRuntimeCount');
final debugViewModelInstanceRuntimeCount =
    _counter('debugViewModelInstanceRuntimeCount');
final debugViewModelInstanceValueRuntimeCount =
    _counter('debugViewModelInstanceValueRuntimeCount');
final debugYogaNodeCount = _counter('debugYogaNodeCount');
final debugBindableArtboardCount = _counter('debugBindableArtboardCount');
