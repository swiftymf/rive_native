import 'dart:collection';
import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:rive_native/rive_luau.dart';
import 'package:rive_native/rive_native.dart';
import 'package:rive_native/src/console_reader.dart';
import 'package:rive_native/src/rive_native_web.dart';
import 'package:rive_native/src/web/rive_audio_web.dart';
import 'package:rive_native/src/web/rive_renderer_web.dart';
import 'package:rive_native/src/web/rive_text_web.dart' show FontWasm;
import 'package:rive_native/src/web/rive_web.dart';
import 'package:rive_native/utilities.dart';

late js.JSFunction _riveVMCreate;
late js.JSFunction _riveVMDestroy;
late js.JSFunction _riveVMGetState;
late js.JSFunction _riveVMAdopt;
late js.JSFunction _riveLuaLoad;
late js.JSFunction _riveLuaRegisterModule;
late js.JSFunction _riveLuaUnregisterModule;
late js.JSFunction _riveLuaRegisterScript;
late js.JSFunction _riveLuaSetField;
late js.JSFunction _riveLuaGetField;
late js.JSFunction _riveLuaRawGetField;
late js.JSFunction _riveLuaToNumber;
late js.JSFunction _riveLuaToInteger;
late js.JSFunction _riveLuaToBoolean;
late js.JSFunction _riveLuaType;
late js.JSFunction _riveLuaToUnsigned;
late js.JSFunction _riveLuaToString;
late js.JSFunction _riveLuaPushNumber;
late js.JSFunction _riveLuaPushValue;
late js.JSFunction _riveLuaPushRenderer;
late js.JSFunction _riveLuaPushArtboard;
late js.JSFunction _riveLuaPushViewModelInstanceValue;
late js.JSFunction _riveLuaScriptedRendererEnd;
late js.JSFunction _riveLuaSetTop;
late js.JSFunction _riveLuaReplace;
late js.JSFunction _riveLuaGetTop;
late js.JSFunction _riveLuaInsert;
late js.JSFunction _riveLuaPushNil;
late js.JSFunction _riveLuaPushUnsigned;
late js.JSFunction _riveLuaPushInteger;
late js.JSFunction _riveLuaPushString;
late js.JSFunction _riveLuaPushBoolean;
late js.JSFunction _riveLuaPushClosure;
late js.JSFunction _riveLuaPushDataContext;
late js.JSFunction _riveLuaPushDataContextViewModel;
late js.JSFunction _riveLuaCreateMetaTable;
late js.JSFunction _riveLuaCreateViewModelInstance;
late js.JSFunction _riveLuaCreateViewModelInstanceFromInstance;
late js.JSFunction _riveLuaCall;
late js.JSFunction _riveLuaPCall;
late js.JSFunction _riveStackDump;
late js.JSFunction _riveLuaRef;
late js.JSFunction _riveLuaUnref;
late js.JSFunction _riveLuaRawGeti;
late js.JSFunction _riveLuaConsole;
late js.JSFunction _riveLuaConsoleClear;
late js.JSFunction _riveLuaGC;
late js.JSFunction _riveLuaScriptedDataValueType;
late js.JSFunction _riveLuaScriptedDataValueNumberValue;
late js.JSFunction _riveLuaScriptedDataValueStringValue;
late js.JSFunction _riveLuaScriptedDataValueBooleanValue;
late js.JSFunction _riveLuaScriptedDataValueColorValue;
late js.JSFunction _riveLuaPushDataValueNumber;
late js.JSFunction _riveLuaPushDataValueString;
late js.JSFunction _riveLuaPushDataValueBoolean;
late js.JSFunction _riveLuaPushDataValueColor;
late js.JSFunction _riveLuaToDataValue;
late js.JSFunction _riveLuaToPath;
late js.JSFunction _riveLuaPushPath;
late js.JSFunction _riveLuaPushImage;
late js.JSFunction _riveLuaPushFont;
late js.JSFunction _riveLuaRenderPath;
late js.JSFunction _riveLuaClearStateWithFile;
late js.JSFunction _riveLuaPushVector;
late js.JSFunction _riveLuaPushMatrix;
late js.JSFunction _riveLuaPushMatrixX;
late js.JSFunction _riveLuaPushMatrixY;
late js.JSFunction _riveLuaToVector;
late js.JSFunction _riveLuaPushPointerEvent;
late js.JSFunction _riveLuaPushPointerListenerInvocation;
late js.JSFunction _riveLuaPushKeyboardListenerInvocation;
late js.JSFunction _riveLuaPushScriptedKeyboardInvocation;
late js.JSFunction _riveLuaPushTextInputListenerInvocation;
late js.JSFunction _riveLuaPushScriptedTextInputInvocation;
late js.JSFunction _riveLuaPushFocusListenerInvocation;
late js.JSFunction _riveLuaPushReportedEventListenerInvocation;
late js.JSFunction _riveLuaPushViewModelChangeListenerInvocation;
late js.JSFunction _riveLuaPushNoneListenerInvocation;
late js.JSFunction _riveLuaPushGamepadListenerInvocation;
late js.JSFunction _riveLuaPushScriptedGamepadInvocation;
late js.JSFunction _riveLuaPointerEventHitResult;
late js.JSFunction _riveLuaCreateTable;
late js.JSFunction _riveLuaRemove;
late js.JSFunction _riveLuaSetMetaTable;
late js.JSFunction _riveLuaEqual;
late js.JSFunction _riveLuaLessThan;
late js.JSFunction _riveLuaWhere;
late js.JSFunction _riveLuaSetExecutionTimeout;
late js.JSFunction _riveLuaGetExecutionTimeout;
late js.JSFunction _riveLuaSetGeneratorRef;
late js.JSFunction _riveLuaGetGeneratorRef;
late js.JSFunction _riveLuaClearGeneratorRefs;
late js.JSFunction _riveLuaPushBlob;
late js.JSFunction _riveLuaPushAudioSource;
late js.JSFunction _riveLuaEnableDrawCanvasPhase;
late js.JSFunction _riveLuaDisableDrawCanvasPhase;
late js.JSFunction _riveLuaAdvanceDetachedViewModels;
late js.JSFunction _riveLuaPushShader;
late js.JSFunction _riveLuaPushGPUFeatures;
late js.JSFunction _riveLuaPushCanvas;
late js.JSFunction _riveLuaPushGPUCanvas;
late js.JSFunction _riveGPUBeginFrame;
late js.JSFunction _riveGPUEndFrame;
late js.JSFunction _riveLuaStopPlayback;
late js.JSFunction _riveLuaStartPlayback;
late js.JSFunction _riveLuaDecodeImage;
late js.JSFunction _riveLuaPollAsyncWork;
late js.JSFunction _riveLuaHasPendingAsyncWork;

bool _wasmBool(js.JSAny? value) => (value as js.JSNumber).toDartInt == 1;

class LuauStateWasm extends LuauState {
  static void link(js.JSObject module) {
    // These use EMSCRIPTEN_BINDINGS (no underscore) because they take
    // emscripten::val callbacks which require proper JS<->C++ marshaling
    _riveVMCreate = module['riveVMCreate'] as js.JSFunction;
    _riveVMDestroy = module['riveVMDestroy'] as js.JSFunction;
    _riveVMGetState = module['riveVMGetState'] as js.JSFunction;
    _riveVMAdopt = module['riveVMAdopt'] as js.JSFunction;
    _riveLuaLoad = module['_luau_load'] as js.JSFunction;
    _riveLuaRegisterModule = module['_riveLuaRegisterModule'] as js.JSFunction;
    _riveLuaUnregisterModule =
        module['_riveLuaUnregisterModule'] as js.JSFunction;
    _riveLuaRegisterScript = module['_riveLuaRegisterScript'] as js.JSFunction;
    _riveLuaSetField = module['_lua_setfield'] as js.JSFunction;
    _riveLuaGetField = module['_lua_getfield'] as js.JSFunction;
    _riveLuaRawGetField = module['_lua_rawgetfield'] as js.JSFunction;
    _riveLuaToNumber = module['_lua_tonumberx'] as js.JSFunction;
    _riveLuaToInteger = module['_lua_tointegerx'] as js.JSFunction;
    _riveLuaToBoolean = module['_lua_toboolean'] as js.JSFunction;
    _riveLuaType = module['_lua_type'] as js.JSFunction;
    _riveLuaToUnsigned = module['_lua_tounsignedx'] as js.JSFunction;
    _riveLuaToString = module['_lua_tolstring'] as js.JSFunction;
    _riveLuaPushNumber = module['_lua_pushnumber'] as js.JSFunction;
    _riveLuaPushValue = module['_lua_pushvalue'] as js.JSFunction;
    _riveLuaPushRenderer = module['_riveLuaPushRenderer'] as js.JSFunction;
    _riveLuaPushArtboard = module['_riveLuaPushArtboard'] as js.JSFunction;
    _riveLuaPushViewModelInstanceValue =
        module['_riveLuaPushViewModelInstanceValue'] as js.JSFunction;
    _riveLuaScriptedRendererEnd =
        module['_riveLuaScriptedRendererEnd'] as js.JSFunction;
    _riveLuaSetTop = module['_lua_settop'] as js.JSFunction;
    _riveLuaReplace = module['_lua_replace'] as js.JSFunction;
    _riveLuaGetTop = module['_lua_gettop'] as js.JSFunction;
    _riveLuaInsert = module['_lua_insert'] as js.JSFunction;
    _riveLuaPushNil = module['_lua_pushnil'] as js.JSFunction;
    _riveLuaPushUnsigned = module['_lua_pushunsigned'] as js.JSFunction;
    _riveLuaPushInteger = module['_lua_pushinteger'] as js.JSFunction;
    _riveLuaPushString = module['_lua_pushstring'] as js.JSFunction;
    _riveLuaPushBoolean = module['_lua_pushboolean'] as js.JSFunction;
    _riveLuaPushClosure = module['riveLuaPushClosure'] as js.JSFunction;
    _riveLuaPushDataContext =
        module['_riveLuaPushDataContext'] as js.JSFunction;
    _riveLuaPushDataContextViewModel =
        module['_riveLuaPushDataContextViewModel'] as js.JSFunction;
    _riveLuaCreateMetaTable =
        module['_riveLuaCreateMetaTable'] as js.JSFunction;
    _riveLuaCreateViewModelInstance =
        module['_riveLuaCreateViewModelInstance'] as js.JSFunction;
    _riveLuaCreateViewModelInstanceFromInstance =
        module['_riveLuaCreateViewModelInstanceFromInstance'] as js.JSFunction;
    _riveLuaCall = module['_riveLuaCall'] as js.JSFunction;
    _riveLuaPCall = module['_riveLuaPCall'] as js.JSFunction;
    _riveStackDump = module['_riveStackDump'] as js.JSFunction;
    _riveLuaRef = module['_lua_ref'] as js.JSFunction;
    _riveLuaUnref = module['_lua_unref'] as js.JSFunction;
    _riveLuaRawGeti = module['_lua_rawgeti'] as js.JSFunction;
    _riveLuaConsole = module['riveLuaConsole'] as js.JSFunction;
    _riveLuaConsoleClear = module['_riveLuaConsoleClear'] as js.JSFunction;
    _riveLuaGC = module['_lua_gc'] as js.JSFunction;
    _riveLuaScriptedDataValueType =
        module['_riveLuaScriptedDataValueType'] as js.JSFunction;
    _riveLuaScriptedDataValueNumberValue =
        module['_riveLuaScriptedDataValueNumberValue'] as js.JSFunction;
    _riveLuaScriptedDataValueStringValue =
        module['_riveLuaScriptedDataValueStringValue'] as js.JSFunction;
    _riveLuaScriptedDataValueBooleanValue =
        module['_riveLuaScriptedDataValueBooleanValue'] as js.JSFunction;
    _riveLuaScriptedDataValueColorValue =
        module['_riveLuaScriptedDataValueColorValue'] as js.JSFunction;
    _riveLuaPushDataValueNumber =
        module['_riveLuaPushDataValueNumber'] as js.JSFunction;
    _riveLuaPushDataValueString =
        module['_riveLuaPushDataValueString'] as js.JSFunction;
    _riveLuaPushDataValueBoolean =
        module['_riveLuaPushDataValueBoolean'] as js.JSFunction;
    _riveLuaPushDataValueColor =
        module['_riveLuaPushDataValueColor'] as js.JSFunction;
    _riveLuaToDataValue = module['_riveLuaDataValue'] as js.JSFunction;
    _riveLuaToPath = module['_riveLuaPath'] as js.JSFunction;
    _riveLuaPushPath = module['_riveLuaPushPath'] as js.JSFunction;
    _riveLuaPushImage = module['riveLuaPushImage'] as js.JSFunction;
    _riveLuaPushFont = module['riveLuaPushFont'] as js.JSFunction;
    _riveLuaRenderPath = module['_riveLuaRenderPath'] as js.JSFunction;
    _riveLuaClearStateWithFile = module['_clearScriptingVM'] as js.JSFunction;
    _riveLuaPushVector = module['_lua_pushvector2'] as js.JSFunction;
    _riveLuaPushMatrix = module['_riveLuaPushMatrix'] as js.JSFunction;
    _riveLuaPushMatrixX = module['_riveLuaPushMatrixX'] as js.JSFunction;
    _riveLuaPushMatrixY = module['_riveLuaPushMatrixY'] as js.JSFunction;
    _riveLuaToVector = module['_lua_tovector'] as js.JSFunction;
    _riveLuaPushPointerEvent =
        module['_riveLuaPushPointerEvent'] as js.JSFunction;
    _riveLuaPushPointerListenerInvocation =
        module['_riveLuaPushPointerListenerInvocation'] as js.JSFunction;
    _riveLuaPushKeyboardListenerInvocation =
        module['_riveLuaPushKeyboardListenerInvocation'] as js.JSFunction;
    _riveLuaPushScriptedKeyboardInvocation =
        module['_riveLuaPushScriptedKeyboardInvocation'] as js.JSFunction;
    _riveLuaPushTextInputListenerInvocation =
        module['_riveLuaPushTextInputListenerInvocation'] as js.JSFunction;
    _riveLuaPushScriptedTextInputInvocation =
        module['_riveLuaPushScriptedTextInputInvocation'] as js.JSFunction;
    _riveLuaPushFocusListenerInvocation =
        module['_riveLuaPushFocusListenerInvocation'] as js.JSFunction;
    _riveLuaPushReportedEventListenerInvocation =
        module['_riveLuaPushReportedEventListenerInvocation'] as js.JSFunction;
    _riveLuaPushViewModelChangeListenerInvocation =
        module['_riveLuaPushViewModelChangeListenerInvocation']
            as js.JSFunction;
    _riveLuaPushNoneListenerInvocation =
        module['_riveLuaPushNoneListenerInvocation'] as js.JSFunction;
    _riveLuaPushGamepadListenerInvocation =
        module['_riveLuaPushGamepadListenerInvocation'] as js.JSFunction;
    _riveLuaPushScriptedGamepadInvocation =
        module['_riveLuaPushScriptedGamepadInvocation'] as js.JSFunction;
    _riveLuaPointerEventHitResult =
        module['_riveLuaPointerEventHitResult'] as js.JSFunction;
    _riveLuaCreateTable = module['_lua_createtable'] as js.JSFunction;
    _riveLuaRemove = module['_lua_remove'] as js.JSFunction;
    _riveLuaSetMetaTable = module['_lua_setmetatable'] as js.JSFunction;
    _riveLuaEqual = module['_lua_equal'] as js.JSFunction;
    _riveLuaLessThan = module['_lua_lessthan'] as js.JSFunction;
    _riveLuaWhere = module['_luaL_where'] as js.JSFunction;
    _riveLuaSetExecutionTimeout =
        module['_riveLuaSetExecutionTimeout'] as js.JSFunction;
    _riveLuaGetExecutionTimeout =
        module['_riveLuaGetExecutionTimeout'] as js.JSFunction;
    _riveLuaSetGeneratorRef =
        module['_riveLuaSetGeneratorRef'] as js.JSFunction;
    _riveLuaGetGeneratorRef =
        module['_riveLuaGetGeneratorRef'] as js.JSFunction;
    _riveLuaClearGeneratorRefs =
        module['_riveLuaClearGeneratorRefs'] as js.JSFunction;
    _riveLuaPushBlob = module['_riveLuaPushBlob'] as js.JSFunction;
    _riveLuaPushAudioSource =
        module['_riveLuaPushAudioSource'] as js.JSFunction;
    _riveLuaEnableDrawCanvasPhase =
        module['_riveLuaEnableDrawCanvasPhase'] as js.JSFunction;
    _riveLuaDisableDrawCanvasPhase =
        module['_riveLuaDisableDrawCanvasPhase'] as js.JSFunction;
    _riveLuaAdvanceDetachedViewModels =
        module['_riveLuaAdvanceDetachedViewModels'] as js.JSFunction;
    _riveLuaPushShader = module['_riveLuaPushShader'] as js.JSFunction;
    _riveLuaPushGPUFeatures =
        module['_riveLuaPushGPUFeatures'] as js.JSFunction;
    _riveLuaPushCanvas = module['riveLuaPushCanvas'] as js.JSFunction;
    _riveLuaPushGPUCanvas = module['riveLuaPushGPUCanvas'] as js.JSFunction;
    _riveGPUBeginFrame = module['riveGPUBeginFrame'] as js.JSFunction;
    _riveGPUEndFrame = module['riveGPUEndFrame'] as js.JSFunction;
    _riveLuaStopPlayback = module['_riveLuaStopPlayback'] as js.JSFunction;
    _riveLuaStartPlayback = module['_riveLuaStartPlayback'] as js.JSFunction;
    _riveLuaDecodeImage = module['_riveLuaDecodeImage'] as js.JSFunction;
    _riveLuaPollAsyncWork = module['_riveLuaPollAsyncWork'] as js.JSFunction;
    _riveLuaHasPendingAsyncWork =
        module['_riveLuaHasPendingAsyncWork'] as js.JSFunction;
  }

  /// The ScriptingVM pointer (used for VM lifecycle and File association).
  js.JSAny _vmPtr = 0.toJS;
  int get _vmIntegerPointer => (_vmPtr as js.JSNumber).toDartInt;

  /// The lua_State pointer (used for Lua operations).
  js.JSAny _nativePtr = 0.toJS;
  int get _nativeIntegerPointer => (_nativePtr as js.JSNumber).toDartInt;

  /// Exposes the VM pointer for use by setScriptingState.
  int get vmPtr => _vmIntegerPointer;

  /// Exposes the lua_State pointer for use by other web FFI functions.
  int get nativePtr => _nativeIntegerPointer;

  @js.JSExport()
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  void notifyConsoleHasData() => consoleHasData.notifyListeners();

  LuauStateWasm(WebFactory riveFactory) {
    // Create a ScriptingVM that owns both the lua_State and context.
    _vmPtr = _riveVMCreate.callAsFunction(
      null,
      riveFactory.pointer,
      notifyConsoleHasData.toJS,
    ) as js.JSAny;
    // Get the lua_State pointer for Lua operations.
    _nativePtr = _riveVMGetState.callAsFunction(null, _vmPtr) as js.JSAny;
    _states[_nativeIntegerPointer] = this;
  }

  /// Adopt a ScriptingVM created by ScriptingWorkspace.
  /// Replaces the CPPRuntimeScriptingContext with a DartExposedScriptingContext.
  /// [renderTexture] provides the WebGL context handle for this VM's renderer.
  LuauStateWasm.adoptVM(
    int vmPointer,
    WebFactory riveFactory, {
    RenderTexture? renderTexture,
  }) {
    _vmPtr = vmPointer.toJS;
    final glHandle = webGLHandleFromRenderTexture(renderTexture);
    // Replace the context with a DartExposedScriptingContext.
    _riveVMAdopt.callAsFunction(
      null,
      _vmPtr,
      riveFactory.pointer,
      notifyConsoleHasData.toJS,
      glHandle.toJS,
    );
    // Get the lua_State pointer for Lua operations.
    _nativePtr = _riveVMGetState.callAsFunction(null, _vmPtr) as js.JSAny;
    _states[_nativeIntegerPointer] = this;
  }

  int get pointer => _nativeIntegerPointer;

  @override
  int get nativeAddress => _nativeIntegerPointer;

  @override
  bool get isDisposed => _vmIntegerPointer == 0;

  @override
  void dispose() {
    _states.remove(_nativeIntegerPointer);
    // Release our reference to the VM. The VM will be destroyed when
    // all references (including those held by ScriptedObjects) are released.
    _riveVMDestroy.callAsFunction(null, _vmPtr);
    _vmPtr = 0.toJS;
    _nativePtr = 0.toJS;
  }

  final List<ConsoleEntry> _bufferedEntries = [];

  bool _readConsole(List<ConsoleEntry> entries) {
    final result = _riveLuaConsole.callAsFunction(null, _nativePtr);
    if (result == null) {
      return false;
    }

    final byteData = (result as js.JSDataView).toDart;

    final added = readConsoleEntries(BinaryReader(byteData), entries);
    _riveLuaConsoleClear.callAsFunction(null, _nativePtr);
    return added;
  }

  @override
  bool readConsole(List<ConsoleEntry> entries) {
    bool read = _bufferedEntries.isNotEmpty;
    if (read) {
      entries.addAll(_bufferedEntries);
      _bufferedEntries.clear();
    }
    return _readConsole(entries) || read;
  }

  @override
  void writeConsole(ConsoleEntry entry) {
    _readConsole(_bufferedEntries);
    _bufferedEntries.add(entry);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    consoleHasData.notifyListeners();
  }

  @override
  bool booleanAt(int index) =>
      _wasmBool(_riveLuaToBoolean.callAsFunction(null, _nativePtr, index.toJS));

  @override
  void call(int numArgs, int numResults) => _riveLuaCall.callAsFunction(
        null,
        _nativePtr,
        numArgs.toJS,
        numResults.toJS,
      );

  @override
  void dumpStack() => _riveStackDump.callAsFunction(null, _nativePtr);

  @override
  LuauType getField(int index, String name) =>
      RiveWasm.toNativeString(name, (namePointer) {
        final type = (_riveLuaGetField.callAsFunction(
          null,
          _nativePtr,
          index.toJS,
          namePointer,
        ) as js.JSNumber)
            .toDartInt;
        return LuauType.fromNative(type);
      });

  @override
  LuauType rawGetField(int index, String name) =>
      RiveWasm.toNativeString(name, (namePointer) {
        final type = (_riveLuaRawGetField.callAsFunction(
          null,
          _nativePtr,
          index.toJS,
          namePointer,
        ) as js.JSNumber)
            .toDartInt;
        return LuauType.fromNative(type);
      });

  @override
  int getTop() =>
      (_riveLuaGetTop.callAsFunction(null, _nativePtr) as js.JSNumber)
          .toDartInt;

  @override
  void insert(int index) =>
      _riveLuaInsert.callAsFunction(null, _nativePtr, index.toJS);

  @override
  int integerAt(int index) =>
      (_riveLuaToInteger.callAsFunction(null, _nativePtr, index.toJS, 0.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  void load(String name, Uint8List bytecode, {int env = 0}) =>
      RiveWasm.toNativeString(name, (namePointer) {
        final bytecodeBuffer = WasmBuffer.fromBytes(bytecode);
        _riveLuaLoad.callAsFunctionEx(
          null,
          _nativePtr,
          namePointer,
          bytecodeBuffer.pointer,
          bytecode.length.toJS,
          env.toJS,
        );
        bytecodeBuffer.dispose();
      });

  @override
  bool registerModule(String name, Uint8List bytecode) =>
      RiveWasm.toNativeString(name, (namePointer) {
        final bytecodeBuffer = WasmBuffer.fromBytes(bytecode);
        final result = _wasmBool(
          _riveLuaRegisterModule.callAsFunctionEx(
            null,
            _nativePtr,
            namePointer,
            bytecodeBuffer.pointer,
            bytecode.length.toJS,
          ),
        );
        bytecodeBuffer.dispose();
        return result;
      });

  @override
  void unregisterModule(String name) =>
      RiveWasm.toNativeString(name, (namePointer) {
        _riveLuaUnregisterModule.callAsFunction(null, _nativePtr, namePointer);
      });

  @override
  bool registerScript(String name, Uint8List bytecode) =>
      RiveWasm.toNativeString(name, (namePointer) {
        final bytecodeBuffer = WasmBuffer.fromBytes(bytecode);
        final result = _wasmBool(
          _riveLuaRegisterScript.callAsFunction(
            null,
            _nativePtr,
            namePointer,
            bytecodeBuffer.pointer,
            bytecode.length.toJS,
          ),
        );
        bytecodeBuffer.dispose();
        return result;
      });

  @override
  void clearStateWithFile(covariant WebRiveFile file) {
    _riveLuaClearStateWithFile.callAsFunction(null, file.pointer.toJS);
  }

  @override
  double numberAt(int index) =>
      (_riveLuaToNumber.callAsFunction(null, _nativePtr, index.toJS, 0.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  LuauStatus pcall(int numArgs, int numResults) {
    int code = (_riveLuaPCall.callAsFunction(
      null,
      _nativePtr,
      numArgs.toJS,
      numResults.toJS,
    ) as js.JSNumber)
        .toDartInt;
    return LuauStatus.fromNative(code);
  }

  static js.JSNumber _callback(int luaState, int index) {
    final state = _states[luaState];
    if (state == null) {
      return 0.toJS;
    }
    final callback = state._registeredFunctions[index];
    return callback(state).toJS;
  }

  final List<LuauFunction> _registeredFunctions = [];
  static final HashMap<int, LuauStateWasm> _states =
      HashMap<int, LuauStateWasm>();

  /// Look up an existing LuauStateWasm by its native pointer.
  /// Returns null if no state is registered for the given pointer.
  static LuauStateWasm? fromNativePointer(int ptr) => _states[ptr];

  @override
  int pushViewModel(InternalDataContext dataContext) {
    final ffiDataContex = dataContext as WebRiveDataContext;
    final ptr = ffiDataContex.pointer;
    return (_riveLuaPushDataContextViewModel.callAsFunction(
      null,
      _nativePtr,
      ptr.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }

  @override
  int pushDataContext(InternalDataContext dataContext) {
    final ffiDataContex = dataContext as WebRiveDataContext;
    final ptr = ffiDataContex.pointer;
    return (_riveLuaPushDataContext.callAsFunction(null, _nativePtr, ptr.toJS)
            as js.JSNumber)
        .toDartInt;
  }

  @override
  void createMetaTable(String name) => RiveWasm.toNativeString(
        name,
        (valuePointer) => _riveLuaCreateMetaTable.callAsFunction(
            null, _nativePtr, valuePointer),
      );

  @override
  int createViewModelInstance(File file, String name) =>
      (RiveWasm.toNativeString(
        name,
        (valuePointer) => _riveLuaCreateViewModelInstance.callAsFunction(
          null,
          _nativePtr,
          (file as WebRiveFile).pointer.toJS,
          valuePointer,
        ),
      ) as js.JSNumber)
          .toDartInt;

  @override
  int createViewModelInstanceFromInstance(
      File file, String name, String instanceName) {
    // RiveWasm.toNativeString uses a shared scratch buffer when the string is
    // short; nested calls overwrite it, so both args would point to the same
    // buffer. Use a dedicated WasmBuffer for the instance name.
    final instanceNameBuffer = instanceName.toWasmUtf8();
    try {
      return (RiveWasm.toNativeString(
        name,
        (valuePointer) =>
            (_riveLuaCreateViewModelInstanceFromInstance.callAsFunction(
          null,
          _nativePtr,
          (file as WebRiveFile).pointer.toJS,
          valuePointer,
          instanceNameBuffer.pointer,
        ) as js.JSNumber)
                .toDartInt,
      ));
    } finally {
      instanceNameBuffer.dispose();
    }
  }

  @override
  void pushFunction(LuauFunction t, {String debugName = 'unknown'}) =>
      RiveWasm.toNativeString(debugName, (debugNamePointer) {
        _registeredFunctions.add(t);
        _riveLuaPushClosure.callAsFunctionEx(
          null,
          _nativePtr,
          _callback.toJS,
          debugNamePointer,
        );
      });

  @override
  void pushInteger(int value) =>
      _riveLuaPushInteger.callAsFunction(null, _nativePtr, value.toJS);

  @override
  void pushNil() => _riveLuaPushNil.callAsFunction(null, _nativePtr);

  @override
  void pushNumber(double value) =>
      _riveLuaPushNumber.callAsFunction(null, _nativePtr, value.toJS);

  @override
  ScriptedRenderer? pushRenderer(covariant WebRiveRenderer renderer) {
    final rendererPtr = renderer.jsRendererPtr;
    if (rendererPtr == null) {
      return null;
    }
    return ScriptedRendererWasm(
      _riveLuaPushRenderer.callAsFunction(null, _nativePtr, rendererPtr)
          as js.JSAny,
    );
  }

  @override
  void pushArtboard(
    covariant WebRiveArtboard artboard,
    covariant WebRiveDataContext? dataContext,
  ) {
    final pointer = dataContext == null ? 0.toJS : dataContext.pointer.toJS;
    _riveLuaPushArtboard.callAsFunction(
      null,
      _nativePtr,
      artboard.pointer.toJS,
      pointer,
    );
  }

  @override
  void pushViewModelInstanceValue(
    covariant WebInternalViewModelInstanceValue value,
  ) {
    _riveLuaPushViewModelInstanceValue.callAsFunction(
      null,
      _nativePtr,
      value.pointer.toJS,
    );
  }

  @override
  void pushString(String value) => RiveWasm.toNativeString(
        value,
        (valuePointer) =>
            _riveLuaPushString.callAsFunction(null, _nativePtr, valuePointer),
      );

  @override
  void pushUnsigned(int value) {
    assert(value >= 0);
    _riveLuaPushUnsigned.callAsFunction(null, _nativePtr, value.toJS);
  }

  @override
  void pushBoolean(bool value) =>
      _riveLuaPushBoolean.callAsFunction(null, _nativePtr, value.toJS);

  @override
  void pushValue(int index) =>
      _riveLuaPushValue.callAsFunction(null, _nativePtr, index.toJS);

  @override
  void setField(int index, String name) => RiveWasm.toNativeString(
        name,
        (namePointer) => _riveLuaSetField.callAsFunction(
          null,
          _nativePtr,
          index.toJS,
          namePointer,
        ),
      );

  @override
  void setTop(int index) =>
      _riveLuaSetTop.callAsFunction(null, _nativePtr, index.toJS);

  @override
  void replace(int index) =>
      _riveLuaReplace.callAsFunction(null, _nativePtr, index.toJS);

  @override
  String stringAt(int index) => RiveWasm.toDartString(
        (_riveLuaToString.callAsFunction(null, _nativePtr, index.toJS, 0.toJS)
                as js.JSNumber)
            .toDartInt,
      );

  @override
  LuauType typeAt(int index) {
    final t = (_riveLuaType.callAsFunction(null, _nativePtr, index.toJS)
            as js.JSNumber)
        .toDartInt;
    // LuauType.fromNative folds LUA_TNONE (-1) to LuauType.nil.
    return LuauType.fromNative(t);
  }

  @override
  int unsignedAt(int index) =>
      (_riveLuaToUnsigned.callAsFunction(null, _nativePtr, index.toJS, 0.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  LuauType rawGeti(int idx, int n) {
    final type = (_riveLuaRawGeti.callAsFunction(
            null, _nativePtr, idx.toJS, n.toJS) as js.JSNumber)
        .toDartInt;
    return LuauType.fromNative(type);
  }

  @override
  int ref(int idx) =>
      (_riveLuaRef.callAsFunction(null, _nativePtr, idx.toJS) as js.JSNumber)
          .toDartInt;

  @override
  void unref(int id) => _riveLuaUnref.callAsFunction(null, _nativePtr, id.toJS);

  @override
  int gc(GarbageCollection what, [int data = 0]) =>
      (_riveLuaGC.callAsFunction(null, _nativePtr, what.value.toJS, data.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  ScriptedDataValue pushDataValueNumber(double value) {
    final nativeDataValueNumber = _riveLuaPushDataValueNumber.callAsFunction(
        null, _nativePtr, value.toJS) as js.JSAny;
    return ScriptedDataValueWasm(nativeDataValueNumber);
  }

  @override
  ScriptedDataValue pushDataValueString(String value) {
    return RiveWasm.toNativeString(value, (valuePointer) {
      final nativeDataValueString = _riveLuaPushDataValueString.callAsFunction(
        null,
        _nativePtr,
        valuePointer,
      ) as js.JSAny;
      return ScriptedDataValueWasm(nativeDataValueString);
    });
  }

  @override
  ScriptedDataValue pushDataValueBoolean(bool value) {
    final nativeDataValueNumber = _riveLuaPushDataValueBoolean.callAsFunction(
      null,
      _nativePtr,
      value.toJS,
    ) as js.JSAny;
    return ScriptedDataValueWasm(nativeDataValueNumber);
  }

  @override
  ScriptedDataValue pushDataValueColor(int value) {
    final nativeDataValueColor = _riveLuaPushDataValueColor.callAsFunction(
        null, _nativePtr, value.toJS) as js.JSAny;
    return ScriptedDataValueWasm(nativeDataValueColor);
  }

  @override
  ScriptedDataValue dataValueAt(int index) => ScriptedDataValueWasm(
        _riveLuaToDataValue.callAsFunction(null, _nativePtr, index.toJS)
            as js.JSAny,
      );

  @override
  ScriptedPath pathAt(int index) => ScriptedPathWasm(
        _riveLuaToPath.callAsFunction(null, _nativePtr, index.toJS) as js.JSAny,
      );

  @override
  void pushVector(Vec2D value) => _riveLuaPushVector.callAsFunction(
        null,
        _nativePtr,
        value.x.toJS,
        value.y.toJS,
      );

  @override
  void pushMatrix(Mat2D value) {
    // Split in three calls because callAsFunction supports only a maximum of
    // 5 argumens
    final matrixPointer =
        _riveLuaPushMatrix.callAsFunction(null, _nativePtr) as js.JSAny;

    _riveLuaPushMatrixX.callAsFunction(
      null,
      matrixPointer,
      value[0].toJS,
      value[1].toJS,
      value[4].toJS,
    );
    _riveLuaPushMatrixY.callAsFunction(
      null,
      matrixPointer,
      value[2].toJS,
      value[3].toJS,
      value[5].toJS,
    );
  }

  @override
  Vec2D vectorAt(int index) {
    final pointer = (_riveLuaToVector.callAsFunction(
            null, _nativePtr, index.toJS) as js.JSNumber)
        .toDartInt;
    final content = RiveWasm.heapViewF32(pointer, 2);
    return Vec2D.fromValues(content[0], content[1]);
  }

  @override
  PointerEvent pushPointerEvent(int id, Vec2D position) => PointerEventWeb(
        _riveLuaPushPointerEvent.callAsFunction(
          null,
          _nativePtr,
          id.toJS,
          position.x.toJS,
          position.y.toJS,
        ) as js.JSNumber,
      );

  @override
  void pushPointerListenerInvocation(int id, Vec2D position,
      Vec2D previousPosition, int listenerType, double timeStamp) {
    _riveLuaPushPointerListenerInvocation.callAsFunctionEx(
      null,
      _nativePtr,
      id.toJS,
      position.x.toJS,
      position.y.toJS,
      previousPosition.x.toJS,
      previousPosition.y.toJS,
      listenerType.toJS,
      timeStamp.toJS,
    );
  }

  @override
  void pushKeyboardListenerInvocation(
      int key, int modifiers, bool isPressed, bool isRepeat) {
    _riveLuaPushKeyboardListenerInvocation.callAsFunctionEx(
      null,
      _nativePtr,
      key.toJS,
      modifiers.toJS,
      (isPressed ? 1 : 0).toJS,
      (isRepeat ? 1 : 0).toJS,
    );
  }

  @override
  void pushScriptedKeyboardInvocation(
      int key, int modifiers, bool isPressed, bool isRepeat) {
    _riveLuaPushScriptedKeyboardInvocation.callAsFunctionEx(
      null,
      _nativePtr,
      key.toJS,
      modifiers.toJS,
      (isPressed ? 1 : 0).toJS,
      (isRepeat ? 1 : 0).toJS,
    );
  }

  @override
  void pushTextInputListenerInvocation(String text) {
    RiveWasm.toNativeString(text, (textPointer) {
      _riveLuaPushTextInputListenerInvocation.callAsFunction(
        null,
        _nativePtr,
        textPointer,
      );
    });
  }

  @override
  void pushScriptedTextInputInvocation(String text) {
    RiveWasm.toNativeString(text, (textPointer) {
      _riveLuaPushScriptedTextInputInvocation.callAsFunction(
        null,
        _nativePtr,
        textPointer,
      );
    });
  }

  @override
  void pushFocusListenerInvocation(bool isFocus) {
    _riveLuaPushFocusListenerInvocation.callAsFunction(
      null,
      _nativePtr,
      (isFocus ? 1 : 0).toJS,
    );
  }

  @override
  void pushReportedEventListenerInvocation(double delaySeconds) {
    _riveLuaPushReportedEventListenerInvocation.callAsFunction(
      null,
      _nativePtr,
      delaySeconds.toJS,
    );
  }

  @override
  void pushViewModelChangeListenerInvocation() {
    _riveLuaPushViewModelChangeListenerInvocation.callAsFunction(
      null,
      _nativePtr,
    );
  }

  @override
  void pushNoneListenerInvocation() {
    _riveLuaPushNoneListenerInvocation.callAsFunction(
      null,
      _nativePtr,
    );
  }

  @override
  void pushGamepadListenerInvocation({
    required int kind,
    required int deviceId,
    required int buttonMask,
    required List<double> buttonValues,
    required List<double> axes,
    required int mapping,
    int changeKind = 0,
    int changeIndex = 0,
    double changeValue = 0,
  }) {
    final buttonF32 = Float32List.fromList(buttonValues);
    final axesF32 = Float32List.fromList(axes);
    final buttonBuffer = buttonF32.lengthInBytes == 0
        ? null
        : WasmBuffer.fromBytes(
            buttonF32.buffer
                .asUint8List(buttonF32.offsetInBytes, buttonF32.lengthInBytes),
          );
    final axesBuffer = axesF32.lengthInBytes == 0
        ? null
        : WasmBuffer.fromBytes(
            axesF32.buffer
                .asUint8List(axesF32.offsetInBytes, axesF32.lengthInBytes),
          );
    try {
      _riveLuaPushGamepadListenerInvocation.callAsFunctionEx(
        null,
        _nativePtr,
        kind.toJS,
        deviceId.toJS,
        buttonMask.toJS,
        buttonBuffer?.pointer ?? 0.toJS,
        buttonF32.length.toJS,
        axesBuffer?.pointer ?? 0.toJS,
        axesF32.length.toJS,
        mapping.toJS,
        changeKind.toJS,
        changeIndex.toJS,
        changeValue.toJS,
      );
    } finally {
      buttonBuffer?.dispose();
      axesBuffer?.dispose();
    }
  }

  @override
  void pushScriptedGamepadInvocation({
    required int kind,
    required int deviceId,
    required int buttonMask,
    required List<double> buttonValues,
    required List<double> axes,
    required int mapping,
    int changeKind = 0,
    int changeIndex = 0,
    double changeValue = 0,
  }) {
    final buttonF32 = Float32List.fromList(buttonValues);
    final axesF32 = Float32List.fromList(axes);
    final buttonBuffer = buttonF32.lengthInBytes == 0
        ? null
        : WasmBuffer.fromBytes(
            buttonF32.buffer
                .asUint8List(buttonF32.offsetInBytes, buttonF32.lengthInBytes),
          );
    final axesBuffer = axesF32.lengthInBytes == 0
        ? null
        : WasmBuffer.fromBytes(
            axesF32.buffer
                .asUint8List(axesF32.offsetInBytes, axesF32.lengthInBytes),
          );
    try {
      _riveLuaPushScriptedGamepadInvocation.callAsFunctionEx(
        null,
        _nativePtr,
        kind.toJS,
        deviceId.toJS,
        buttonMask.toJS,
        buttonBuffer?.pointer ?? 0.toJS,
        buttonF32.length.toJS,
        axesBuffer?.pointer ?? 0.toJS,
        axesF32.length.toJS,
        mapping.toJS,
        changeKind.toJS,
        changeIndex.toJS,
        changeValue.toJS,
      );
    } finally {
      buttonBuffer?.dispose();
      axesBuffer?.dispose();
    }
  }

  @override
  void createTable({int arraySize = 0, int recordCount = 0}) =>
      _riveLuaCreateTable.callAsFunction(
        null,
        _nativePtr,
        arraySize.toJS,
        recordCount.toJS,
      );

  @override
  void remove(int index) =>
      _riveLuaRemove.callAsFunction(null, _nativePtr, index.toJS);

  @override
  void setMetaTable(int index) =>
      _riveLuaSetMetaTable.callAsFunction(null, _nativePtr, index.toJS);

  @override
  bool equal(int index1, int index2) => _wasmBool(
        _riveLuaEqual.callAsFunction(
            null, _nativePtr, index1.toJS, index2.toJS),
      );

  @override
  bool lessThan(int index1, int index2) => _wasmBool(
        _riveLuaLessThan.callAsFunction(
            null, _nativePtr, index1.toJS, index2.toJS),
      );

  @override
  void where(int level) =>
      _riveLuaWhere.callAsFunction(null, _nativePtr, level.toJS);

  @override
  void pushPath(RenderPath path) {
    final webRenderPath = path as WebRenderPath;
    _riveLuaPushPath.callAsFunction(
      null,
      _nativePtr,
      webRenderPath.riveFactory.pointer,
      webRenderPath.pointer,
    );
  }

  @override
  int pushImage(RenderImage image) {
    final webRenderImage = image as WebRenderImage;
    return (_riveLuaPushImage.callAsFunction(
      null,
      _nativePtr,
      webRenderImage.pointer,
    ) as js.JSNumber)
        .toDartInt;
  }

  @override
  int pushFont(Font font) {
    return (_riveLuaPushFont.callAsFunction(
      null,
      _nativePtr,
      (font as FontWasm).fontPtr.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }

  @override
  int pushCanvas(int width, int height) {
    return (_riveLuaPushCanvas.callAsFunction(
            null, _nativePtr, width.toJS, height.toJS) as js.JSNumber)
        .toDartInt;
  }

  @override
  int pushGPUCanvas(int width, int height) {
    return (_riveLuaPushGPUCanvas.callAsFunction(
            null, _nativePtr, width.toJS, height.toJS) as js.JSNumber)
        .toDartInt;
  }

  @override
  void gpuBeginFrame() {
    _riveGPUBeginFrame.callAsFunction(null, _nativePtr);
  }

  @override
  void gpuEndFrame() {
    _riveGPUEndFrame.callAsFunction(null, _nativePtr);
  }

  @override
  RenderPath? renderPath(ScriptedPath scriptedPath, RenderPath path) {
    final riveFactory = (path as WebRenderPath).riveFactory;
    final renderPathPointer = (_riveLuaRenderPath.callAsFunction(
      null,
      _nativePtr,
      (scriptedPath as ScriptedPathWasm).pointer,
    ) as js.JSNumber);
    final webRenderPath = WebRenderPath.fromPointer(
      riveFactory,
      renderPathPointer,
    );
    return webRenderPath;
  }

  @override
  void setExecutionTimeout(int timeoutMs) => _riveLuaSetExecutionTimeout
      .callAsFunction(null, _nativePtr, timeoutMs.toJS);

  @override
  int getExecutionTimeout() =>
      (_riveLuaGetExecutionTimeout.callAsFunction(null, _nativePtr)
              as js.JSNumber)
          .toDartInt;

  @override
  void setGeneratorRef(int assetId, int ref) => _riveLuaSetGeneratorRef
      .callAsFunction(null, _nativePtr, assetId.toJS, ref.toJS);

  @override
  int getGeneratorRef(int assetId) =>
      (_riveLuaGetGeneratorRef.callAsFunction(null, _nativePtr, assetId.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  void clearGeneratorRefs() =>
      _riveLuaClearGeneratorRefs.callAsFunction(null, _nativePtr);

  @override
  void pushBlob(String name, Uint8List data) {
    RiveWasm.toNativeString(name, (namePointer) {
      final buffer = WasmBuffer.fromBytes(data);
      _riveLuaPushBlob.callAsFunctionEx(
        null,
        _nativePtr,
        namePointer,
        buffer.pointer,
        data.length.toJS,
      );
      buffer.dispose();
    });
  }

  @override
  int pushAudio(AudioSource audioSource) {
    return (_riveLuaPushAudioSource.callAsFunction(
      null,
      _nativePtr,
      (audioSource as AudioSourceWasm).nativePtr.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }

  @override
  void enableDrawCanvasPhase() {
    _riveLuaEnableDrawCanvasPhase.callAsFunction(null, _nativePtr);
  }

  @override
  void disableDrawCanvasPhase() {
    _riveLuaDisableDrawCanvasPhase.callAsFunction(null, _nativePtr);
  }

  @override
  void advanceDetachedViewModels() {
    _riveLuaAdvanceDetachedViewModels.callAsFunction(null, _nativePtr);
  }

  @override
  int pushShader(String name) {
    return RiveWasm.toNativeString(name, (namePointer) {
      return (_riveLuaPushShader.callAsFunction(null, _nativePtr, namePointer)
              as js.JSNumber)
          .toDartInt;
    });
  }

  @override
  int pushGPUFeatures() {
    return (_riveLuaPushGPUFeatures.callAsFunction(null, _nativePtr)
            as js.JSNumber)
        .toDartInt;
  }

  @override
  int decodeImage() {
    return (_riveLuaDecodeImage.callAsFunction(null, _nativePtr) as js.JSNumber)
        .toDartInt;
  }

  @override
  int pollAsyncWork({int maxCallbacks = 16}) {
    return (_riveLuaPollAsyncWork.callAsFunction(
            null, _nativePtr, maxCallbacks.toJS) as js.JSNumber)
        .toDartInt;
  }

  @override
  bool get hasPendingAsyncWork =>
      _wasmBool(_riveLuaHasPendingAsyncWork.callAsFunction(null, _nativePtr));

  @override
  void stopPlayback() {
    _riveLuaStopPlayback.callAsFunction(null, _nativePtr);
  }

  @override
  void startPlayback() {
    _riveLuaStartPlayback.callAsFunction(null, _nativePtr);
  }
}

class ScriptedRendererWasm extends ScriptedRenderer {
  js.JSAny pointer;
  ScriptedRendererWasm(this.pointer);
  @override
  void end() {
    _riveLuaScriptedRendererEnd.callAsFunction(null, pointer);
    pointer = 0.toJS;
  }
}

LuauState makeLuauState(Factory riveFactory) =>
    LuauStateWasm(riveFactory as WebFactory);

/// Adopts a ScriptingVM created by ScriptingWorkspace.
/// On web, [renderTexture] provides the GL context handle for this VM.
LuauState adoptLuauState(
  int vmPointer,
  Factory riveFactory, {
  RenderTexture? renderTexture,
}) =>
    LuauStateWasm.adoptVM(
      vmPointer,
      riveFactory as WebFactory,
      renderTexture: renderTexture,
    );

class PointerEventWeb extends PointerEvent {
  final js.JSAny pointer;
  PointerEventWeb(this.pointer);
  @override
  HitResult get hitResult =>
      HitResult.values[(_riveLuaPointerEventHitResult.callAsFunction(
        null,
        pointer,
      ) as js.JSNumber)
          .toDartInt];
}

class ScriptedPathWasm extends ScriptedPath {
  final js.JSAny pointer;
  ScriptedPathWasm(this.pointer);
}

class ScriptedDataValueWasm extends ScriptedDataValue {
  final js.JSAny pointer;
  ScriptedDataValueWasm(this.pointer);

  @override
  String get type {
    return RiveWasm.toDartString(
      (_riveLuaScriptedDataValueType.callAsFunction(null, pointer)
              as js.JSNumber)
          .toDartInt,
      deleteNative: true,
    );
  }

  @override
  double numberValue() {
    final val = (_riveLuaScriptedDataValueNumberValue.callAsFunction(
            null, pointer) as js.JSNumber)
        .toDartDouble;
    return val;
  }

  @override
  String stringValue() {
    return RiveWasm.toDartString(
      (_riveLuaScriptedDataValueStringValue.callAsFunction(null, pointer)
              as js.JSNumber)
          .toDartInt,
      deleteNative: true,
    );
  }

  @override
  bool booleanValue() {
    return _wasmBool(
      _riveLuaScriptedDataValueBooleanValue.callAsFunction(null, pointer),
    );
  }

  @override
  int colorValue() {
    return (_riveLuaScriptedDataValueColorValue.callAsFunction(null, pointer)
            as js.JSNumber)
        .toDartInt;
  }
}
