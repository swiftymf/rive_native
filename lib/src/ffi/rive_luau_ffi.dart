import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rive_native/rive_luau.dart';
import 'package:rive_native/rive_native.dart';
import 'package:rive_native/src/console_reader.dart';
import 'package:rive_native/src/ffi/dynamic_library_helper.dart';
import 'package:rive_native/src/ffi/rive_audio_ffi.dart';
import 'package:rive_native/src/ffi/rive_ffi.dart';
import 'package:rive_native/src/ffi/rive_ffi_reference.dart';
import 'package:rive_native/src/ffi/rive_renderer_ffi.dart' as rive_renderer;
import 'package:rive_native/src/ffi/rive_text_ffi.dart' as rive_text;
import 'package:rive_native/utilities.dart';

final DynamicLibrary _nativeLib = DynamicLibraryHelper.nativeLib;

typedef LuaCFunction = Int32 Function(Pointer<Void>);
typedef LuaContinuation = Int32 Function(Pointer<Void>, Int32);

// ============================================================================
// New ScriptingVM-based API
// ============================================================================

// Creates a ScriptingVM that owns both the lua_State and context.
final Pointer<Void> Function(
  Pointer<Void>,
  Pointer<NativeFunction<Void Function()>>,
) _riveVMCreate = _nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<NativeFunction<Void Function()>>,
            )>>('riveVMCreate')
    .asFunction();

// Destroys a ScriptingVM, cleaning up both state and context.
final void Function(Pointer<Void>) _riveVMDestroy = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('riveVMDestroy')
    .asFunction();

// Gets the lua_State* from a ScriptingVM.
final Pointer<Void> Function(Pointer<Void>) _riveVMGetState = _nativeLib
    .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
        'riveVMGetState')
    .asFunction();

// Adopts a ScriptingVM, replacing its context with DartExposedScriptingContext.
final void Function(
        Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<Void Function()>>)
    _riveVMAdopt = _nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                  Pointer<Void>,
                  Pointer<NativeFunction<Void Function()>>,
                )>>('riveVMAdopt')
        .asFunction();

final Pointer<Void> Function(Pointer<Void> renderContext)
    _riveInitGPUScripting = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'riveInitGPUScripting')
        .asFunction();

/// Backend-agnostic ore::Context init. The native side delegates to
/// `RenderContextImpl::makeOreContext()`, so no per-platform handles are
/// needed. Returns the ore::Context pointer — pass to
/// [scriptingWorkspaceSetOreContext] before calling [requestVM].
Pointer<Void> initGPUScripting(Pointer<Void> renderContext) {
  return _riveInitGPUScripting(renderContext);
}

final void Function(
  Pointer<Void> state,
  Pointer<Utf8> scriptName,
  Pointer<Uint8> data,
  int size,
  int env,
) _riveLuaLoad = _nativeLib
    .lookup<
        NativeFunction<
            Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Size,
                Int32)>>('luau_load')
    .asFunction();
final void Function(Pointer<Void> state, int objindex) _riveLuaSetMetaTable =
    _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
          'lua_setmetatable',
        )
        .asFunction();
final int Function(Pointer<Void> state, int index1, int index2) _riveLuaEqual =
    _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32, Int32)>>(
          'lua_equal',
        )
        .asFunction();
final int Function(Pointer<Void> state, int index1, int index2)
    _riveLuaLessThan = _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32, Int32)>>(
          'lua_lessthan',
        )
        .asFunction();
final void Function(Pointer<Void> state, int level) _riveLuaWhere = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>('luaL_where')
    .asFunction();
final void Function(Pointer<Void> state, int narray, int nrec)
    _riveLuaCreateTable = _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Int32, Int32)>>(
          'lua_createtable',
        )
        .asFunction();
final void Function(Pointer<Void> state, Pointer<Utf8> name)
    _riveLuaCreateMetaTable = _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Utf8>)>>(
          'riveLuaCreateMetaTable',
        )
        .asFunction();
final int Function(
  Pointer<Void> state,
  Pointer<Void> file,
  Pointer<Utf8> viewModelName,
) _riveLuaCreateViewModelInstance = _nativeLib
    .lookup<
        NativeFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>,
                Pointer<Utf8>)>>('riveLuaCreateViewModelInstance')
    .asFunction();
final int Function(
  Pointer<Void> state,
  Pointer<Void> file,
  Pointer<Utf8> viewModelName,
  Pointer<Utf8> viewModelInstanceName,
) _riveLuaCreateViewModelInstanceFromInstance = _nativeLib
    .lookup<
        NativeFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>,
                Pointer<Utf8>)>>('riveLuaCreateViewModelInstanceFromInstance')
    .asFunction();
final void Function(Pointer<Void> state, int idx) _riveLuaRemove = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>('lua_remove')
    .asFunction();
final bool Function(
  Pointer<Void> state,
  Pointer<Utf8> scriptName,
  Pointer<Uint8> data,
  int size,
) _riveLuaRegisterModule = _nativeLib
    .lookup<
        NativeFunction<
            Bool Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>,
                Size)>>('riveLuaRegisterModule')
    .asFunction();

final bool Function(Pointer<Void> state, Pointer<Utf8> scriptName)
    _riveLuaUnregisterModule = _nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Utf8>)>>(
          'riveLuaUnregisterModule',
        )
        .asFunction();

final bool Function(
  Pointer<Void> state,
  Pointer<Utf8> scriptName,
  Pointer<Uint8> data,
  int size,
) _riveLuaRegisterScript = _nativeLib
    .lookup<
        NativeFunction<
            Bool Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>,
                Size)>>('riveLuaRegisterScript')
    .asFunction();

final void Function(Pointer<Void> state, int idx, Pointer<Utf8> name)
    _riveLuaSetField = _nativeLib
        .lookup<
            NativeFunction<Void Function(Pointer<Void>, Int32, Pointer<Utf8>)>>(
          'lua_setfield',
        )
        .asFunction();

final int Function(Pointer<Void> state, int idx, int name) _riveLuaGC =
    _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32, Int32)>>(
          'lua_gc',
        )
        .asFunction();

final int Function(Pointer<Void> state, int idx, Pointer<Utf8> name)
    _riveLuaGetField = _nativeLib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<Void>, Int32, Pointer<Utf8>)>>('lua_getfield')
        .asFunction();

final int Function(Pointer<Void> state, int idx, Pointer<Utf8> name)
    _riveLuaRawGetField = _nativeLib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<Void>, Int32, Pointer<Utf8>)>>('lua_rawgetfield')
        .asFunction();

final double Function(Pointer<Void> state, int idx, Pointer<Int32> isnum)
    _riveLuaToNumber = _nativeLib
        .lookup<
            NativeFunction<
                Double Function(
                    Pointer<Void>, Int32, Pointer<Int32>)>>('lua_tonumberx')
        .asFunction();

final Pointer<Float> Function(Pointer<Void> state, int idx) _riveLuaToVector =
    _nativeLib
        .lookup<NativeFunction<Pointer<Float> Function(Pointer<Void>, Int32)>>(
          'lua_tovector',
        )
        .asFunction();

final int Function(Pointer<Void> state, int idx, Pointer<Int32> isnum)
    _riveLuaToInteger = _nativeLib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<Void>, Int32, Pointer<Int32>)>>('lua_tointegerx')
        .asFunction();

final int Function(Pointer<Void> state, int idx) _riveLuaToBoolean = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32)>>(
      'lua_toboolean',
    )
    .asFunction();

final int Function(Pointer<Void> state, int idx) _riveLuaType = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32)>>('lua_type')
    .asFunction();

final int Function(Pointer<Void> state, int idx, Pointer<Int32> isnum)
    _riveLuaToUnsigned = _nativeLib
        .lookup<
            NativeFunction<
                Uint32 Function(
                    Pointer<Void>, Int32, Pointer<Int32>)>>('lua_tounsignedx')
        .asFunction();

final Pointer<Utf8> Function(Pointer<Void> state, int idx, int length)
    _riveLuaToString = _nativeLib
        .lookup<
            NativeFunction<Pointer<Utf8> Function(Pointer<Void>, Int32, Size)>>(
          'lua_tolstring',
        )
        .asFunction();

final void Function(Pointer<Void> state, double value) _riveLuaPushNumber =
    _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Double)>>(
          'lua_pushnumber',
        )
        .asFunction();
final void Function(Pointer<Void> state, double x, double y)
    _riveLuaPushVector = _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float, Float)>>(
          'lua_pushvector2',
        )
        .asFunction();
final void Function(
  Pointer<Void> state,
  double x1,
  double x2,
  double y1,
  double y2,
  double tx,
  double ty,
) _riveLuaPushMatrix = _nativeLib
    .lookup<
        NativeFunction<
            Void Function(Pointer<Void>, Float, Float, Float, Float, Float,
                Float)>>('riveLuaPushFullMatrix')
    .asFunction();

final void Function(Pointer<Void> state, int index) _riveLuaPushValue =
    _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
          'lua_pushvalue',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, Pointer<Void> renderer)
    _riveLuaPushRenderer = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>, Pointer<Void>)>>('riveLuaPushRenderer')
        .asFunction();
final void Function(
        Pointer<Void> state, Pointer<Void> renderer, Pointer<Void> dataContext)
    _riveLuaPushArtboard = _nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>>(
          'riveLuaPushArtboard',
        )
        .asFunction();

final Pointer<Void> Function(
  Pointer<Void> state,
  Pointer<Void> viewModelInstanceValue,
) _riveLuaPushViewModelInstanceValue = _nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(Pointer<Void>,
                Pointer<Void>)>>('riveLuaPushViewModelInstanceValue')
    .asFunction();

final void Function(Pointer<Void> scriptedRenderer)
    _riveLuaScriptedRendererEnd = _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'riveLuaScriptedRendererEnd',
        )
        .asFunction();

final Pointer<Utf8> Function(Pointer<Void> scriptedRenderer)
    _riveLuaScriptedDataValueType = _nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
          'riveLuaScriptedDataValueType',
        )
        .asFunction();

final double Function(Pointer<Void> state)
    _riveLuaScriptedDataValueNumberValue = nativeLib
        .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
          'riveLuaScriptedDataValueNumberValue',
        )
        .asFunction();

final Pointer<Utf8> Function(Pointer<Void> state)
    _riveLuaScriptedDataValueStringValue = nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
          'riveLuaScriptedDataValueStringValue',
        )
        .asFunction();

final bool Function(Pointer<Void> imageAsset)
    _riveLuaScriptedDataValueBooleanValue = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
          'riveLuaScriptedDataValueBooleanValue',
        )
        .asFunction();

final int Function(Pointer<Void> value) _riveLuaScriptedDataValueColorValue =
    nativeLib
        .lookup<NativeFunction<Int Function(Pointer<Void>)>>(
          'riveLuaScriptedDataValueColorValue',
        )
        .asFunction();

final void Function(Pointer<Void> state, int value) _riveLuaSetTop = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>('lua_settop')
    .asFunction();

final void Function(Pointer<Void> state, int value) _riveLuaReplace = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>('lua_replace')
    .asFunction();

final int Function(Pointer<Void> state) _riveLuaGetTop = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('lua_gettop')
    .asFunction();

final void Function(Pointer<Void> state, int value) _riveLuaInsert = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>('lua_insert')
    .asFunction();

final void Function(Pointer<Void> state) _riveLuaPushNil = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('lua_pushnil')
    .asFunction();

final void Function(Pointer<Void> state, int value) _riveLuaPushUnsigned =
    _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
          'lua_pushunsigned',
        )
        .asFunction();

final void Function(Pointer<Void> state, int value) _riveLuaPushInteger =
    _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
          'lua_pushinteger',
        )
        .asFunction();

final void Function(Pointer<Void> state, Pointer<Utf8>) _riveLuaPushString =
    _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Utf8>)>>(
          'lua_pushstring',
        )
        .asFunction();

final void Function(Pointer<Void> state, bool value) _riveLuaPushBoolean =
    _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
          'lua_pushboolean',
        )
        .asFunction();

final void Function(
  Pointer<Void> stat,
  Pointer<Void> factory,
  Pointer<Void> path,
) _riveLuaPushPath = _nativeLib
    .lookup<
        NativeFunction<
            Void Function(Pointer<Void>, Pointer<Void>,
                Pointer<Void>)>>('riveLuaPushPath')
    .asFunction();

final void Function(
  Pointer<Void> state,
  Pointer<NativeFunction<LuaCFunction>>,
  Pointer<Utf8>,
  int,
  Pointer<NativeFunction<LuaContinuation>>,
) _riveLuaPushClosure = _nativeLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<Void>,
              Pointer<NativeFunction<LuaCFunction>>,
              Pointer<Utf8>,
              Int32,
              Pointer<NativeFunction<LuaContinuation>>,
            )>>('lua_pushcclosurek')
    .asFunction();

final void Function(Pointer<Void>, int, int) _riveLuaCall = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32, Int32)>>(
      'riveLuaCall',
    )
    .asFunction();

final int Function(Pointer<Void>, int, int) _riveLuaPCall = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32, Int32)>>(
      'riveLuaPCall',
    )
    .asFunction();

final int Function(Pointer<Void> state) _riveStackDump = _nativeLib
    .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>('riveStackDump')
    .asFunction();

final int Function(Pointer<Void> state, int idx) _riveLuaRef = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32)>>('lua_ref')
    .asFunction();

final void Function(Pointer<Void> state, int idx) _riveLuaUnref = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>('lua_unref')
    .asFunction();

final int Function(Pointer<Void> state, int idx, int n) _riveLuaRawGeti =
    _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32, Int32)>>(
          'lua_rawgeti',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, double)
    _riveLuaPushDataValueNumber = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Float)>>(
          'riveLuaPushDataValueNumber',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, Pointer<Utf8>)
    _riveLuaPushDataValueString = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>,
                    Pointer<Utf8>)>>('riveLuaPushDataValueString')
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, bool)
    _riveLuaPushDataValueBoolean = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Bool)>>(
          'riveLuaPushDataValueBoolean',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int)
    _riveLuaPushDataValueColor = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Int)>>(
          'riveLuaPushDataValueColor',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int id, double x, double y)
    _riveLuaPushPointerEvent = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Uint8, Float,
                    Float)>>('riveLuaPushPointerEvent')
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int id, double x, double y,
        double prevX, double prevY, int hitType, double timeStamp)
    _riveLuaPushPointerListenerInvocation = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>,
                    Uint8,
                    Float,
                    Float,
                    Float,
                    Float,
                    Int32,
                    Float)>>('riveLuaPushPointerListenerInvocation')
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int key, int modifiers,
        int isPressed, int isRepeat) _riveLuaPushKeyboardListenerInvocation =
    _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Uint32, Uint8, Uint8,
                    Uint8)>>('riveLuaPushKeyboardListenerInvocation')
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int key, int modifiers,
        int isPressed, int isRepeat) _riveLuaPushScriptedKeyboardInvocation =
    _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Uint32, Uint8, Uint8,
                    Uint8)>>('riveLuaPushScriptedKeyboardInvocation')
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, Pointer<Utf8> text)
    _riveLuaPushTextInputListenerInvocation = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)>>(
          'riveLuaPushTextInputListenerInvocation',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, Pointer<Utf8> text)
    _riveLuaPushScriptedTextInputInvocation = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)>>(
          'riveLuaPushScriptedTextInputInvocation',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int isFocus)
    _riveLuaPushFocusListenerInvocation = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Uint8)>>(
          'riveLuaPushFocusListenerInvocation',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, double delaySeconds)
    _riveLuaPushReportedEventListenerInvocation = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Float)>>(
          'riveLuaPushReportedEventListenerInvocation',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state)
    _riveLuaPushViewModelChangeListenerInvocation = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
          'riveLuaPushViewModelChangeListenerInvocation',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state)
    _riveLuaPushNoneListenerInvocation = _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
          'riveLuaPushNoneListenerInvocation',
        )
        .asFunction();

final Pointer<Void> Function(
  Pointer<Void> state,
  int kind,
  int deviceId,
  int buttonMask,
  Pointer<Float> buttonValues,
  int buttonCount,
  Pointer<Float> axes,
  int axisCount,
  int mapping,
  int changeKind,
  int changeIndex,
  double changeValue,
) _riveLuaPushGamepadListenerInvocation = _nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Uint8,
              Int32,
              Uint64,
              Pointer<Float>,
              IntPtr,
              Pointer<Float>,
              IntPtr,
              Uint8,
              Uint8,
              Uint8,
              Float,
            )>>(
      'riveLuaPushGamepadListenerInvocation',
    )
    .asFunction();

final Pointer<Void> Function(
  Pointer<Void> state,
  int kind,
  int deviceId,
  int buttonMask,
  Pointer<Float> buttonValues,
  int buttonCount,
  Pointer<Float> axes,
  int axisCount,
  int mapping,
  int changeKind,
  int changeIndex,
  double changeValue,
) _riveLuaPushScriptedGamepadInvocation = _nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Uint8,
              Int32,
              Uint64,
              Pointer<Float>,
              IntPtr,
              Pointer<Float>,
              IntPtr,
              Uint8,
              Uint8,
              Uint8,
              Float,
            )>>(
      'riveLuaPushScriptedGamepadInvocation',
    )
    .asFunction();

final int Function(Pointer<Void> state) _riveLuaPointerEventHitResult =
    _nativeLib
        .lookup<NativeFunction<Uint8 Function(Pointer<Void>)>>(
          'riveLuaPointerEventHitResult',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int idx) _riveLuaToDataValue =
    _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Int32)>>(
          'riveLuaDataValue',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, int idx) _riveLuaToPath =
    _nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Int32)>>(
          'riveLuaPath',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> state, Pointer<Void> scriptedPath)
    _riveLuaRenderPath = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>, Pointer<Void>)>>('riveLuaRenderPath')
        .asFunction();

final void Function(Pointer<Void>) _riveLuaClearStateWithFile = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('clearScriptingVM')
    .asFunction();

final int Function(Pointer<Void> state, Pointer<Void> dataContext)
    _riveLuaPushDataContextViewModel = _nativeLib
        .lookup<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Void>)>>(
          'riveLuaPushDataContextViewModel',
        )
        .asFunction();

final int Function(Pointer<Void> state, Pointer<Void> dataContext)
    _riveLuaPushDataContext = _nativeLib
        .lookup<NativeFunction<Uint8 Function(Pointer<Void>, Pointer<Void>)>>(
          'riveLuaPushDataContext',
        )
        .asFunction();

final void Function(Pointer<Void> state, int timeoutMs)
    _riveLuaSetExecutionTimeout = _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
          'riveLuaSetExecutionTimeout',
        )
        .asFunction();

final int Function(Pointer<Void> state) _riveLuaGetExecutionTimeout = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
      'riveLuaGetExecutionTimeout',
    )
    .asFunction();

final void Function(Pointer<Void> state, int assetId, int ref)
    _riveLuaSetGeneratorRef = _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32, Int32)>>(
          'riveLuaSetGeneratorRef',
        )
        .asFunction();

final int Function(Pointer<Void> state, int assetId) _riveLuaGetGeneratorRef =
    _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32)>>(
          'riveLuaGetGeneratorRef',
        )
        .asFunction();

final void Function(Pointer<Void> state) _riveLuaClearGeneratorRefs = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'riveLuaClearGeneratorRefs',
    )
    .asFunction();

// Update a File's scripting state to point to a new ScriptingVM.
// This is the preferred API for FFI - takes ScriptingVM*.
final void Function(Pointer<Void> file, Pointer<Void> vm)
    riveFileSetScriptingVM = _nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
          'riveFileSetScriptingVM',
        )
        .asFunction();

// Push a RenderImage onto the Lua stack as a ScriptedImage userdata.
// Returns 1 if successful, 0 if the image is null.
final int Function(Pointer<Void> state, Pointer<Void> renderImage)
    _riveLuaPushImage = _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>)>>(
          'riveLuaPushImage',
        )
        .asFunction();

// Push a Font onto the Lua stack as a ScriptedFont userdata.
// Returns 1 if successful, 0 if the font is null.
final int Function(Pointer<Void> state, Pointer<Void> font) _riveLuaPushFont =
    _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>)>>(
          'riveLuaPushFont',
        )
        .asFunction();

// Creates a (non-GPU) Canvas and pushes it onto the Lua stack.
// Returns 1 on success (pushes handle or nil).
final int Function(Pointer<Void> state, int width, int height)
    _riveLuaPushCanvas = _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32, Uint32)>>(
          'riveLuaPushCanvas',
        )
        .asFunction();

// Creates a GPUCanvas and pushes it onto the Lua stack.
// Returns 1 on success (pushes handle or nil).
final int Function(Pointer<Void> state, int width, int height)
    _riveLuaPushGPUCanvas = _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32, Uint32)>>(
          'riveLuaPushGPUCanvas',
        )
        .asFunction();

// Begins / ends a GPU frame for scripted GPU canvas draw calls.
final void Function(Pointer<Void>) _riveGPUBeginFrame = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('riveGPUBeginFrame')
    .asFunction();

final void Function(Pointer<Void>) _riveGPUEndFrame = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('riveGPUEndFrame')
    .asFunction();

final void Function(
        Pointer<Void> state, Pointer<Utf8> name, Pointer<Uint8> data, int size)
    _riveLuaPushBlob = _nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                  Pointer<Utf8>,
                  Pointer<Uint8>,
                  Size,
                )>>('riveLuaPushBlob')
        .asFunction();

final int Function(Pointer<Void> state, Pointer<Void> audioSource)
    _riveLuaPushAudioSource = _nativeLib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<Void>,
                  Pointer<Void>,
                )>>('riveLuaPushAudioSource')
        .asFunction();

final void Function(Pointer<Void> state) _riveLuaEnableDrawCanvasPhase =
    _nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                )>>('riveLuaEnableDrawCanvasPhase')
        .asFunction();

final void Function(Pointer<Void> state) _riveLuaDisableDrawCanvasPhase =
    _nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                )>>('riveLuaDisableDrawCanvasPhase')
        .asFunction();

final void Function(Pointer<Void> state) _riveLuaAdvanceDetachedViewModels =
    _nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                )>>('riveLuaAdvanceDetachedViewModels')
        .asFunction();

// Compiles a shader from the in-memory RSTB registry and pushes it as a
// ScriptedShader userdata. Returns 1 on success, 0 if not found.
final int Function(Pointer<Void> state, Pointer<Utf8> name) _riveLuaPushShader =
    _nativeLib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>)>>(
          'riveLuaPushShader',
        )
        .asFunction();

// Pushes a GPU features table onto the Lua stack. Queries the ORE context
// when available, otherwise returns conservative defaults. Always returns 1.
final int Function(Pointer<Void> state) _riveLuaPushGPUFeatures = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
      'riveLuaPushGPUFeatures',
    )
    .asFunction();

// Forwards to context_decodeImage_impl. Reads the buffer from Lua stack
// position 2 and returns a Promise. Returns 1 (promise pushed) or 0.
final int Function(Pointer<Void> state) _riveLuaDecodeImage = _nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
      'riveLuaDecodeImage',
    )
    .asFunction();

// Poll for completed async tasks (image decodes, etc.) and invoke callbacks.
final int Function(Pointer<Void> state, int maxCallbacks)
    _riveLuaPollAsyncWork = _nativeLib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>, Uint32)>>(
            'riveLuaPollAsyncWork')
        .asFunction();

// Check if there are any pending async tasks.
final bool Function(Pointer<Void> state) _riveLuaHasPendingAsyncWork =
    _nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
          'riveLuaHasPendingAsyncWork',
        )
        .asFunction();

final void Function(Pointer<Void> state) _riveLuaStopPlayback = _nativeLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<Void>,
            )>>('riveLuaStopPlayback')
    .asFunction();

final void Function(Pointer<Void> state) _riveLuaStartPlayback = _nativeLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<Void>,
            )>>('riveLuaStartPlayback')
    .asFunction();

class LuauStateFFI extends LuauState implements RiveFFIReference {
  /// Pointer to ScriptingVM* (owns both lua_State and ScriptingContext)
  Pointer<Void> _vmPtr;

  /// Cached lua_State* pointer for Lua operations
  Pointer<Void>? _cachedStatePtr;

  final List<NativeCallable> _nativeCallables = [];

  /// Gets the lua_State* pointer for raw Lua operations.
  /// Caches the result since the state pointer doesn't change.
  Pointer<Void> get _statePtr {
    // If _cachedStatePtr is already set (e.g., from callback constructor),
    // use it directly.
    if (_cachedStatePtr != null) {
      return _cachedStatePtr!;
    }
    // Otherwise, we need _vmPtr to get the state pointer.
    if (_vmPtr.address == 0) {
      throw StateError(
        'Attempted to access disposed LuauState (vmPtr was 0, no cached state)',
      );
    }
    _cachedStatePtr = _riveVMGetState(_vmPtr);
    return _cachedStatePtr!;
  }

  /// Creates a wrapper around an existing lua_State* pointer.
  /// DEPRECATED: Use LuauStateFFI.fromFactory or LuauStateFFI.adoptVM instead.
  @Deprecated('Use LuauStateFFI.fromFactory or LuauStateFFI.adoptVM instead')
  LuauStateFFI(Pointer<Void> statePtr)
      : _vmPtr = Pointer.fromAddress(0),
        _cachedStatePtr = statePtr;

  /// Adopt a ScriptingVM created by ScriptingWorkspace.
  /// Replaces the CPPRuntimeScriptingContext with a DartExposedScriptingContext.
  LuauStateFFI.adoptVM(
    Pointer<Void> vmPointer,
    Factory riveFactory,
  ) : _vmPtr = vmPointer {
    // Must be .listener (async). Sync .isolateLocal here crashes Dart GC
    // because the native callback fires from inside lua_pcall's setjmp.
    final consoleHasDataCallback = NativeCallable<Void Function()>.listener(
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      consoleHasData.notifyListeners,
    );
    _nativeCallables.add(consoleHasDataCallback);

    _riveVMAdopt(
      vmPointer,
      (riveFactory as FFIFactory).pointer,
      consoleHasDataCallback.nativeFunction,
    );
  }

  @override
  Pointer<Void> get pointer => _vmPtr;

  @override
  int get nativeAddress => _vmPtr.address;

  @override
  bool get isDisposed =>
      _vmPtr.address == 0 && (_cachedStatePtr?.address ?? 0) == 0;

  /// For backward compatibility, also expose nativePtr
  @Deprecated('Use pointer instead')
  Pointer<Void> get nativePtr => _statePtr;

  LuauStateFFI.fromFactory(Factory riveFactory)
      : _vmPtr = Pointer.fromAddress(0) {
    // Must be .listener (async). Sync .isolateLocal here crashes Dart GC
    // because the native callback fires from inside lua_pcall's setjmp.
    final consoleHasDataCallback = NativeCallable<Void Function()>.listener(
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      consoleHasData.notifyListeners,
    );
    _nativeCallables.add(consoleHasDataCallback);

    _vmPtr = _riveVMCreate(
      (riveFactory as FFIFactory).pointer,
      consoleHasDataCallback.nativeFunction,
    );
  }

  @override
  int pushViewModel(InternalDataContext dataContext) {
    final ffiDataContex = dataContext as FFIRiveInternalDataContext;
    final ptr = ffiDataContex.pointer;
    return _riveLuaPushDataContextViewModel(_statePtr, ptr);
  }

  @override
  int pushDataContext(InternalDataContext dataContext) {
    final ffiDataContex = dataContext as FFIRiveInternalDataContext;
    final ptr = ffiDataContex.pointer;
    return _riveLuaPushDataContext(_statePtr, ptr);
  }

  @override
  void dispose() {
    _riveVMDestroy(_vmPtr);
    _vmPtr = Pointer.fromAddress(0);
    _cachedStatePtr = null;
    for (final callable in _nativeCallables) {
      callable.close();
    }
    _nativeCallables.clear();
    calloc.free(_bytecodeBytes);
    _bytecodeBytes = nullptr;
  }

  @override
  void call(int numArgs, int numResults) {
    _riveLuaCall(_statePtr, numArgs, numResults);
  }

  Pointer<Uint8> _bytecodeBytes = calloc.allocate(4096);
  int _bytecodeBytesSize = 4096;

  @override
  void load(String name, Uint8List bytecode, {int env = 0}) {
    if (_bytecodeBytesSize < bytecode.length) {
      calloc.free(_bytecodeBytes);
      _bytecodeBytes = calloc.allocate(bytecode.length);
      _bytecodeBytesSize = bytecode.length;
    }
    _bytecodeBytes
        .asTypedList(bytecode.length)
        .setRange(0, bytecode.length, bytecode);

    _riveLuaLoad(
      _statePtr,
      toNativeString(name),
      _bytecodeBytes,
      bytecode.length,
      env,
    );
  }

  @override
  void unregisterModule(String name) =>
      _riveLuaUnregisterModule(_statePtr, toNativeString(name));

  @override
  bool registerModule(String name, Uint8List bytecode) {
    if (_bytecodeBytesSize < bytecode.length) {
      calloc.free(_bytecodeBytes);
      _bytecodeBytes = calloc.allocate(bytecode.length);
      _bytecodeBytesSize = bytecode.length;
    }
    _bytecodeBytes
        .asTypedList(bytecode.length)
        .setRange(0, bytecode.length, bytecode);

    return _riveLuaRegisterModule(
      _statePtr,
      toNativeString(name),
      _bytecodeBytes,
      bytecode.length,
    );
  }

  @override
  bool registerScript(String name, Uint8List bytecode) {
    if (_bytecodeBytesSize < bytecode.length) {
      calloc.free(_bytecodeBytes);
      _bytecodeBytes = calloc.allocate(bytecode.length);
      _bytecodeBytesSize = bytecode.length;
    }
    _bytecodeBytes
        .asTypedList(bytecode.length)
        .setRange(0, bytecode.length, bytecode);

    return _riveLuaRegisterScript(
      _statePtr,
      toNativeString(name),
      _bytecodeBytes,
      bytecode.length,
    );
  }

  @override
  void clearStateWithFile(File file) {
    _riveLuaClearStateWithFile((file as RiveFFIReference).pointer);
  }

  @override
  LuauStatus pcall(int numArgs, int numResults) {
    return LuauStatus.fromNative(_riveLuaPCall(_statePtr, numArgs, numResults));
  }

  @override
  void pushFunction(LuauFunction t, {String debugName = 'unknown'}) {
    // Capture the receiving wrapper so every Lua→Dart dispatch reuses it
    // instead of minting a fresh `LuauStateFFI(pointer)` per call. The
    // original implementation allocated a new wrapper (plus its empty
    // `_nativeCallables` list and closure cell) on every callback; under hot
    // script-update loops that turns into multi-MB/sec of Dart heap pressure,
    // which the VM-side GC reclaims but the OS doesn't claw back, producing
    // a one-way RSS climb. The lua_State* Luau passes to the trampoline is
    // the calling thread's state; for non-coroutine callbacks (the only kind
    // currently invoked through this path) it equals `_statePtr`, so reusing
    // `this` is correct. If a coroutine ever calls back, the captured
    // wrapper would still operate on the registry-shared state and the
    // semantic stack would be wrong — that's not a path we exercise today.
    final self = this;
    final ff = NativeCallable<LuaCFunction>.isolateLocal(
      (Pointer<Void> _) => t.call(self),
      exceptionalReturn: 0,
    );
    _nativeCallables.add(ff);
    _riveLuaPushClosure(
      _statePtr,
      ff.nativeFunction,
      toNativeString(debugName),
      0,
      nullptr,
    );
  }

  @override
  void pushInteger(int value) => _riveLuaPushInteger(_statePtr, value);

  @override
  void pushNil() => _riveLuaPushNil(_statePtr);

  @override
  void pushNumber(double value) => _riveLuaPushNumber(_statePtr, value);

  @override
  void pushString(String value) =>
      _riveLuaPushString(_statePtr, toNativeString(value));

  @override
  void pushUnsigned(int value) {
    assert(value >= 0);
    _riveLuaPushUnsigned(_statePtr, value);
  }

  @override
  void pushBoolean(bool value) => _riveLuaPushBoolean(_statePtr, value);

  @override
  void setField(int index, String name) =>
      _riveLuaSetField(_statePtr, index, toNativeString(name));

  @override
  LuauType getField(int index, String name) {
    return LuauType.fromNative(
        _riveLuaGetField(_statePtr, index, toNativeString(name)));
  }

  @override
  LuauType rawGetField(int index, String name) {
    return LuauType.fromNative(
        _riveLuaRawGetField(_statePtr, index, toNativeString(name)));
  }

  @override
  void setTop(int index) => _riveLuaSetTop(_statePtr, index);

  @override
  void replace(int index) => _riveLuaReplace(_statePtr, index);

  @override
  int getTop() => _riveLuaGetTop(_statePtr);

  @override
  void insert(int index) => _riveLuaInsert(_statePtr, index);

  @override
  int integerAt(int index) => _riveLuaToInteger(_statePtr, index, nullptr);

  @override
  bool booleanAt(int index) => _riveLuaToBoolean(_statePtr, index) != 0;

  @override
  LuauType typeAt(int index) {
    // LuauType.fromNative folds LUA_TNONE (-1) to LuauType.nil.
    return LuauType.fromNative(_riveLuaType(_statePtr, index));
  }

  @override
  String stringAt(int index) =>
      _riveLuaToString(_statePtr, index, 0).toDartString();

  @override
  double numberAt(int index) => _riveLuaToNumber(_statePtr, index, nullptr);

  @override
  int unsignedAt(int index) => _riveLuaToUnsigned(_statePtr, index, nullptr);

  @override
  void dumpStack() {
    _riveStackDump(_statePtr);
  }

  @override
  void pushValue(int index) {
    _riveLuaPushValue(_statePtr, index);
  }

  @override
  ScriptedRenderer? pushRenderer(Renderer renderer) {
    final rendererPtr = (renderer as RiveFFIReference).pointer;
    if (rendererPtr.address == 0) {
      return null;
    }
    final result = _riveLuaPushRenderer(_statePtr, rendererPtr);
    return FFIScriptedRenderer(result);
  }

  @override
  void pushArtboard(Artboard artboard, InternalDataContext? dataContext) {
    Pointer<Void> dataContextPointer = (dataContext is InternalDataContext)
        ? (dataContext as FFIRiveInternalDataContext).pointer
        : nullptr;

    _riveLuaPushArtboard(
        _statePtr, (artboard as RiveFFIReference).pointer, dataContextPointer);
  }

  @override
  void pushViewModelInstanceValue(InternalViewModelInstanceValue value) {
    _riveLuaPushViewModelInstanceValue(
      _statePtr,
      (value as RiveFFIReference).pointer,
    );
  }

  final List<ConsoleEntry> _bufferedEntries = [];

  bool _readConsole(List<ConsoleEntry> entries) {
    final result = _riveLuaConsole(_statePtr);
    final added = readConsoleEntries(result.reader, entries);
    _riveLuaConsoleClear(_statePtr);
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
  int gc(GarbageCollection what, [int data = 0]) =>
      _riveLuaGC(_statePtr, what.value, data);

  @override
  LuauType rawGeti(int idx, int n) {
    return LuauType.fromNative(_riveLuaRawGeti(_statePtr, idx, n));
  }

  @override
  int ref(int idx) => _riveLuaRef(_statePtr, idx);

  @override
  void unref(int id) => _riveLuaUnref(_statePtr, id);

  @override
  ScriptedDataValue pushDataValueNumber(double value) {
    final nativeDataValueNumber = _riveLuaPushDataValueNumber(_statePtr, value);
    return FFIScriptedDataValue(nativeDataValueNumber);
  }

  @override
  ScriptedDataValue pushDataValueString(String value) {
    final nativeDataValueString = _riveLuaPushDataValueString(
      _statePtr,
      toNativeString(value),
    );
    return FFIScriptedDataValue(nativeDataValueString);
  }

  @override
  ScriptedDataValue pushDataValueBoolean(bool value) {
    final nativeDataValueNumber = _riveLuaPushDataValueBoolean(
      _statePtr,
      value,
    );
    return FFIScriptedDataValue(nativeDataValueNumber);
  }

  @override
  ScriptedDataValue pushDataValueColor(int value) {
    final nativeDataValueColor = _riveLuaPushDataValueColor(_statePtr, value);
    return FFIScriptedDataValue(nativeDataValueColor);
  }

  @override
  ScriptedDataValue dataValueAt(int index) =>
      FFIScriptedDataValue(_riveLuaToDataValue(_statePtr, index));

  @override
  ScriptedPath pathAt(int index) =>
      FFIScriptedPath(_riveLuaToPath(_statePtr, index));

  @override
  Vec2D vectorAt(int index) {
    final pointer = _riveLuaToVector(_statePtr, index);
    final x = pointer.value;
    final y = (pointer + 1).value;
    return Vec2D.fromValues(x, y);
  }

  @override
  void pushVector(Vec2D value) =>
      _riveLuaPushVector(_statePtr, value.x, value.y);

  @override
  void pushMatrix(Mat2D value) => _riveLuaPushMatrix(
        _statePtr,
        value[0],
        value[1],
        value[2],
        value[3],
        value[4],
        value[5],
      );

  @override
  PointerEvent pushPointerEvent(int id, Vec2D position) => FFIPointerEvent(
        _riveLuaPushPointerEvent(_statePtr, id, position.x, position.y),
      );

  @override
  void pushPointerListenerInvocation(int id, Vec2D position,
      Vec2D previousPosition, int listenerType, double timeStamp) {
    _riveLuaPushPointerListenerInvocation(
      _statePtr,
      id,
      position.x,
      position.y,
      previousPosition.x,
      previousPosition.y,
      listenerType,
      timeStamp,
    );
  }

  @override
  void pushKeyboardListenerInvocation(
      int key, int modifiers, bool isPressed, bool isRepeat) {
    _riveLuaPushKeyboardListenerInvocation(
      _statePtr,
      key,
      modifiers,
      isPressed ? 1 : 0,
      isRepeat ? 1 : 0,
    );
  }

  @override
  void pushScriptedKeyboardInvocation(
      int key, int modifiers, bool isPressed, bool isRepeat) {
    _riveLuaPushScriptedKeyboardInvocation(
      _statePtr,
      key,
      modifiers,
      isPressed ? 1 : 0,
      isRepeat ? 1 : 0,
    );
  }

  @override
  void pushTextInputListenerInvocation(String text) {
    _riveLuaPushTextInputListenerInvocation(_statePtr, toNativeString(text));
  }

  @override
  void pushScriptedTextInputInvocation(String text) {
    _riveLuaPushScriptedTextInputInvocation(_statePtr, toNativeString(text));
  }

  @override
  void pushFocusListenerInvocation(bool isFocus) {
    _riveLuaPushFocusListenerInvocation(_statePtr, isFocus ? 1 : 0);
  }

  @override
  void pushReportedEventListenerInvocation(double delaySeconds) {
    _riveLuaPushReportedEventListenerInvocation(_statePtr, delaySeconds);
  }

  @override
  void pushViewModelChangeListenerInvocation() {
    _riveLuaPushViewModelChangeListenerInvocation(_statePtr);
  }

  @override
  void pushNoneListenerInvocation() {
    _riveLuaPushNoneListenerInvocation(_statePtr);
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
    final bN = buttonValues.length;
    final aN = axes.length;
    final buttonPtr =
        bN == 0 ? Pointer<Float>.fromAddress(0) : calloc<Float>(bN);
    final axesPtr = aN == 0 ? Pointer<Float>.fromAddress(0) : calloc<Float>(aN);
    try {
      for (var i = 0; i < bN; i++) {
        buttonPtr[i] = buttonValues[i];
      }
      for (var i = 0; i < aN; i++) {
        axesPtr[i] = axes[i];
      }
      _riveLuaPushGamepadListenerInvocation(
        _statePtr,
        kind,
        deviceId,
        buttonMask,
        buttonPtr,
        bN,
        axesPtr,
        aN,
        mapping,
        changeKind,
        changeIndex,
        changeValue,
      );
    } finally {
      if (bN != 0) calloc.free(buttonPtr);
      if (aN != 0) calloc.free(axesPtr);
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
    final bN = buttonValues.length;
    final aN = axes.length;
    final buttonPtr =
        bN == 0 ? Pointer<Float>.fromAddress(0) : calloc<Float>(bN);
    final axesPtr = aN == 0 ? Pointer<Float>.fromAddress(0) : calloc<Float>(aN);
    try {
      for (var i = 0; i < bN; i++) {
        buttonPtr[i] = buttonValues[i];
      }
      for (var i = 0; i < aN; i++) {
        axesPtr[i] = axes[i];
      }
      _riveLuaPushScriptedGamepadInvocation(
        _statePtr,
        kind,
        deviceId,
        buttonMask,
        buttonPtr,
        bN,
        axesPtr,
        aN,
        mapping,
        changeKind,
        changeIndex,
        changeValue,
      );
    } finally {
      if (bN != 0) calloc.free(buttonPtr);
      if (aN != 0) calloc.free(axesPtr);
    }
  }

  @override
  void createTable({int arraySize = 0, int recordCount = 0}) =>
      _riveLuaCreateTable(_statePtr, arraySize, recordCount);

  @override
  void createMetaTable(String name) =>
      _riveLuaCreateMetaTable(_statePtr, toNativeString(name));

  @override
  int createViewModelInstance(File file, String name) =>
      _riveLuaCreateViewModelInstance(
        _statePtr,
        (file as RiveFFIReference).pointer,
        toNativeString(name),
      );

  @override
  int createViewModelInstanceFromInstance(
      File file, String name, String instanceName) {
    // toNativeString uses a single shared buffer; calling it twice would
    // overwrite the first with the second, so both native args would be the
    // same pointer. Use a separate allocation for the second string.
    final namePtr = toNativeString(name);
    final instanceUnits = utf8.encode(instanceName);
    final instanceNamePtr = calloc<Uint8>(instanceUnits.length + 1);
    instanceNamePtr
        .asTypedList(instanceUnits.length + 1)
        .setAll(0, instanceUnits);
    instanceNamePtr[instanceUnits.length] = 0;
    try {
      return _riveLuaCreateViewModelInstanceFromInstance(
        _statePtr,
        (file as RiveFFIReference).pointer,
        namePtr,
        instanceNamePtr.cast<Utf8>(),
      );
    } finally {
      calloc.free(instanceNamePtr);
    }
  }

  @override
  void remove(int index) => _riveLuaRemove(_statePtr, index);

  @override
  void setMetaTable(int index) => _riveLuaSetMetaTable(_statePtr, index);

  @override
  bool equal(int index1, int index2) =>
      _riveLuaEqual(_statePtr, index1, index2) != 0;

  @override
  bool lessThan(int index1, int index2) =>
      _riveLuaLessThan(_statePtr, index1, index2) != 0;

  @override
  void where(int level) => _riveLuaWhere(_statePtr, level);

  @override
  void pushPath(RenderPath path) {
    final ffiRenderPath = path as rive_renderer.FFIRenderPath;
    _riveLuaPushPath(
      _statePtr,
      ffiRenderPath.riveFactory.pointer,
      ffiRenderPath.pointer,
    );
  }

  @override
  int pushImage(RenderImage image) {
    final ffiRenderImage = image as rive_renderer.FFIRenderImage;
    return _riveLuaPushImage(_statePtr, ffiRenderImage.pointer);
  }

  @override
  int pushFont(Font font) {
    return _riveLuaPushFont(_statePtr, (font as rive_text.FontFFI).fontPtr);
  }

  @override
  int pushCanvas(int width, int height) {
    return _riveLuaPushCanvas(_statePtr, width, height);
  }

  @override
  int pushGPUCanvas(int width, int height) {
    return _riveLuaPushGPUCanvas(_statePtr, width, height);
  }

  @override
  void gpuBeginFrame() => _riveGPUBeginFrame(_statePtr);

  @override
  void gpuEndFrame() => _riveGPUEndFrame(_statePtr);

  @override
  RenderPath? renderPath(ScriptedPath scriptedPath, RenderPath path) {
    final riveFactory = (path as rive_renderer.FFIRenderPath).riveFactory;
    final renderPathPointer = _riveLuaRenderPath(
      _statePtr,
      (scriptedPath as FFIScriptedPath).pointer,
    );
    final ffRenderPath = rive_renderer.FFIRenderPath.fromPointer(
      riveFactory,
      renderPathPointer,
    );
    return ffRenderPath;
  }

  @override
  void setExecutionTimeout(int timeoutMs) =>
      _riveLuaSetExecutionTimeout(_statePtr, timeoutMs);

  @override
  int getExecutionTimeout() => _riveLuaGetExecutionTimeout(_statePtr);

  @override
  void setGeneratorRef(int assetId, int ref) =>
      _riveLuaSetGeneratorRef(_statePtr, assetId, ref);

  @override
  int getGeneratorRef(int assetId) =>
      _riveLuaGetGeneratorRef(_statePtr, assetId);

  @override
  void clearGeneratorRefs() => _riveLuaClearGeneratorRefs(_statePtr);

  @override
  void pushBlob(String name, Uint8List data) {
    final nativeName = toNativeString(name);
    final nativeData = calloc.allocate<Uint8>(data.length);
    nativeData.asTypedList(data.length).setAll(0, data);
    _riveLuaPushBlob(_statePtr, nativeName, nativeData, data.length);
    calloc.free(nativeData);
  }

  @override
  int pushAudio(AudioSource audioSource) {
    return _riveLuaPushAudioSource(
        _statePtr, (audioSource as AudioSourceFFI).nativePtr);
  }

  @override
  void enableDrawCanvasPhase() {
    _riveLuaEnableDrawCanvasPhase(_statePtr);
  }

  @override
  void disableDrawCanvasPhase() {
    _riveLuaDisableDrawCanvasPhase(_statePtr);
  }

  @override
  void advanceDetachedViewModels() {
    _riveLuaAdvanceDetachedViewModels(_statePtr);
  }

  @override
  int pushShader(String name) {
    final nativeName = toNativeString(name);
    return _riveLuaPushShader(_statePtr, nativeName);
  }

  @override
  int pushGPUFeatures() {
    return _riveLuaPushGPUFeatures(_statePtr);
  }

  @override
  int decodeImage() {
    return _riveLuaDecodeImage(_statePtr);
  }

  @override
  int pollAsyncWork({int maxCallbacks = 16}) {
    return _riveLuaPollAsyncWork(_statePtr, maxCallbacks);
  }

  @override
  bool get hasPendingAsyncWork => _riveLuaHasPendingAsyncWork(_statePtr);

  @override
  void stopPlayback() {
    _riveLuaStopPlayback(_statePtr);
  }

  @override
  void startPlayback() {
    _riveLuaStartPlayback(_statePtr);
  }
}

final class BufferResponse extends Struct {
  external Pointer<Uint8> data;

  @Size()
  external int size;

  BinaryReader get reader => BinaryReader.fromList(data.asTypedList(size));
}

BufferResponse Function(Pointer<Void> state) _riveLuaConsole = _nativeLib
    .lookup<NativeFunction<BufferResponse Function(Pointer<Void> state)>>(
      'riveLuaConsole',
    )
    .asFunction();

void Function(Pointer<Void> state) _riveLuaConsoleClear = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void> state)>>(
      'riveLuaConsoleClear',
    )
    .asFunction();

class FFIScriptedRenderer extends ScriptedRenderer {
  Pointer<Void> pointer;
  FFIScriptedRenderer(this.pointer);
  @override
  void end() {
    _riveLuaScriptedRendererEnd(pointer);
    pointer = nullptr;
  }
}

class FFIPointerEvent extends PointerEvent {
  final Pointer<Void> pointer;
  FFIPointerEvent(this.pointer);

  @override
  HitResult get hitResult =>
      HitResult.values[_riveLuaPointerEventHitResult(pointer)];
}

class FFIScriptedDataValue extends ScriptedDataValue {
  final Pointer<Void> pointer;
  FFIScriptedDataValue(this.pointer);
  @override
  String get type {
    return safeString(_riveLuaScriptedDataValueType(pointer));
  }

  @override
  double numberValue() {
    final val = _riveLuaScriptedDataValueNumberValue(pointer);
    return val;
  }

  @override
  String stringValue() {
    final val = _riveLuaScriptedDataValueStringValue(pointer);
    return safeString(val);
  }

  @override
  bool booleanValue() {
    final val = _riveLuaScriptedDataValueBooleanValue(pointer);
    return val;
  }

  @override
  int colorValue() {
    final val = _riveLuaScriptedDataValueColorValue(pointer);
    return val;
  }
}

class FFIScriptedPath extends ScriptedPath {
  final Pointer<Void> pointer;
  FFIScriptedPath(this.pointer);
}

LuauState makeLuauState(Factory riveFactory) =>
    LuauStateFFI.fromFactory(riveFactory);

/// Adopts a ScriptingVM created by ScriptingWorkspace.
/// [renderTexture] is unused on FFI (native GL context is process-global).
LuauState adoptLuauState(
  int vmPointer,
  Factory riveFactory, {
  RenderTexture? renderTexture,
}) =>
    LuauStateFFI.adoptVM(
      Pointer<Void>.fromAddress(vmPointer),
      riveFactory,
    );
