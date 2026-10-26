import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:rive_native/focus.dart' as focus;
import 'package:rive_native/math.dart';
import 'package:rive_native/rive_audio.dart';
import 'package:rive_native/rive_luau.dart';
import 'package:rive_native/rive_text.dart';
import 'package:rive_native/src/errors.dart';
import 'package:rive_native/src/ffi/dynamic_library_helper.dart';
import 'package:rive_native/src/ffi/flutter_renderer_ffi.dart';
import 'package:rive_native/src/ffi/rive_audio_ffi.dart';
import 'package:rive_native/src/ffi/rive_data_binding_ffi.dart';
import 'package:rive_native/src/ffi/rive_event_ffi.dart';
import 'package:rive_native/src/ffi/rive_ffi_reference.dart';
import 'package:rive_native/src/ffi/rive_focus_ffi.dart';
import 'package:rive_native/src/ffi/rive_renderer_ffi.dart';
import 'package:rive_native/src/ffi/rive_semantic_ffi.dart';
import 'package:rive_native/src/semantics/semantics_diff.dart';
import 'package:rive_native/src/ffi/rive_luau_ffi.dart'
    show riveFileSetScriptingVM, LuauStateFFI;
import 'package:rive_native/src/ffi/rive_text_ffi.dart';
import 'package:rive_native/src/rive.dart';
import 'package:rive_native/src/rive_renderer.dart';

final DynamicLibrary nativeLib = DynamicLibraryHelper.open();

/// Load a list of bytes from a file on the local filesystem at [path].
Future<Uint8List?> localFileBytes(String path) => io.File(path).readAsBytes();

typedef ViewModelNumberCallback
    = Pointer<NativeFunction<Void Function(Uint64, Float)>>;

typedef ViewModelBooleanCallback
    = Pointer<NativeFunction<Void Function(Uint64, Bool)>>;

typedef ViewModelColorCallback
    = Pointer<NativeFunction<Void Function(Uint64, Uint32)>>;

typedef ViewModelStringCallback
    = Pointer<NativeFunction<Void Function(Uint64, Pointer<Utf8>)>>;

typedef ViewModelTriggerCallback
    = Pointer<NativeFunction<Void Function(Uint64, Int)>>;

typedef ViewModelEnumCallback
    = Pointer<NativeFunction<Void Function(Uint64, Int)>>;

typedef ViewModelSymbolListIndexCallback
    = Pointer<NativeFunction<Void Function(Uint64, Int)>>;

typedef ViewModelAssetCallback
    = Pointer<NativeFunction<Void Function(Uint64, Int)>>;

typedef ViewModelArtboardCallback
    = Pointer<NativeFunction<Void Function(Uint64, Int)>>;

typedef ViewModelListCallback = Pointer<NativeFunction<Void Function(Uint64)>>;

typedef ViewModelViewModelCallback
    = Pointer<NativeFunction<Void Function(Uint64)>>;

typedef _StateMachineInputNative = Pointer<Void> Function(
    Pointer<Void> smi, Pointer<Void> inputName, Pointer<Void> path);

typedef _AssetLoaderCallbackNative = Bool Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Int,
);

typedef _AssetLoaderCallbackPointer
    = Pointer<NativeFunction<_AssetLoaderCallbackNative>>;

typedef _FreeStringNative = Void Function(Pointer<Utf8> str);

typedef _FreeString = void Function(Pointer<Utf8> str);

final freeString =
    nativeLib.lookupFunction<_FreeStringNative, _FreeString>('freeString');

String safeString(Pointer<Utf8> stringPointer, {bool deleteNative = false}) {
  if (stringPointer == nullptr) {
    return '';
  }
  final result = stringPointer.toDartString();
  if (deleteNative) {
    freeString(stringPointer);
  }
  return result;
}

final void Function(
  ViewModelNumberCallback viewModelNumberCallback,
  ViewModelBooleanCallback viewModelBooleanCallback,
  ViewModelColorCallback viewModelColorCallback,
  ViewModelStringCallback viewModelStringCallback,
  ViewModelTriggerCallback viewModelTriggerCallback,
  ViewModelEnumCallback viewModelEnumCallback,
  ViewModelSymbolListIndexCallback viewModelSymbolListIndexCallback,
  ViewModelAssetCallback viewModelAssetCallback,
  ViewModelArtboardCallback viewModelArtboardCallback,
  ViewModelListCallback viewModelListCallback,
  ViewModelViewModelCallback viewModelViewModelCallback,
) _initBindingCallbacks = nativeLib
    .lookup<
        NativeFunction<
            Void Function(
              ViewModelNumberCallback,
              ViewModelBooleanCallback,
              ViewModelColorCallback,
              ViewModelStringCallback,
              ViewModelTriggerCallback,
              ViewModelEnumCallback,
              ViewModelSymbolListIndexCallback,
              ViewModelAssetCallback,
              ViewModelArtboardCallback,
              ViewModelListCallback,
              ViewModelViewModelCallback,
            )>>('initBindingCallbacks')
    .asFunction();

final Pointer<Void> Function(
  Pointer<Uint8> bytes,
  int length,
  Pointer<Void> riveFactory,
  _AssetLoaderCallbackPointer,
  Pointer<Void> vm,
) _loadRiveFile = nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(
              Pointer<Uint8>,
              Uint64,
              Pointer<Void>,
              _AssetLoaderCallbackPointer,
              Pointer<Void>,
            )>>('loadRiveFile')
    .asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteFileAssetNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteFileAsset');
final void Function(Pointer<Void> file) _deleteFileAsset =
    _deleteFileAssetNative.asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteRiveFileNative = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('deleteRiveFile');
final void Function(Pointer<Void> file) _deleteRiveFile =
    _deleteRiveFileNative.asFunction();
final Pointer<Void> Function(Pointer<Void>, bool frameOrigin)
    _riveFileArtboardDefault = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Bool)>>(
            'riveFileArtboardDefault')
        .asFunction();
final Pointer<Void> Function(
        Pointer<Void> file, Pointer<Void> name, bool frameOrigin)
    _riveFileArtboardNamed = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Pointer<Void> name,
                    Bool)>>('riveFileArtboardNamed')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> file, int index, bool frameOrigin)
    _riveFileArtboardByIndex = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>, Uint32, Bool)>>('riveFileArtboardByIndex')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> file, Pointer<Void> name)
    _riveFileArtboardToBindNamed = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>,
                    Pointer<Void> name)>>('riveFileArtboardToBindNamed')
        .asFunction();
final int Function(Pointer<Void>) _riveFileAssetId = nativeLib
    .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>('riveFileAssetId')
    .asFunction();
final Pointer<Utf8> Function(Pointer<Void>) _riveFileAssetName = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
        'riveFileAssetName')
    .asFunction();
final Pointer<Utf8> Function(Pointer<Void>) _riveFileAssetFileExtension =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
            'riveFileAssetFileExtension')
        .asFunction();
final Pointer<Utf8> Function(Pointer<Void>) _riveFileAssetCdnBaseUrl = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
        'riveFileAssetCdnBaseUrl')
    .asFunction();
final Pointer<Utf8> Function(Pointer<Void>) _riveFileAssetCdnUuid = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
        'riveFileAssetCdnUuid')
    .asFunction();
final int Function(Pointer<Void>) _riveFileAssetCoreType = nativeLib
    .lookup<NativeFunction<Uint16 Function(Pointer<Void>)>>(
        'riveFileAssetCoreType')
    .asFunction();
final bool Function(Pointer<Void>, Pointer<Void>) riveFileAssetSetRenderImage =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Void>)>>(
            'riveFileAssetSetRenderImage')
        .asFunction();
final double Function(Pointer<Void> imageAsset) _imageAssetGetWidth = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>('imageAssetGetWidth')
    .asFunction();
final double Function(Pointer<Void> imageAsset) _imageAssetGetHeight = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'imageAssetGetHeight')
    .asFunction();
final bool Function(Pointer<Void>, Pointer<Void>) riveFileAssetSetFont =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Void>)>>(
            'riveFileAssetSetFont')
        .asFunction();
final bool Function(Pointer<Void>, Pointer<Void>) riveFileAssetSetAudioSource =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Void>)>>(
            'riveFileAssetSetAudioSource')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> file, int index, int indexInstance)
    _riveDataContext = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>, Uint64, Uint64)>>('riveDataContext')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> dataContext)
    _riveDataContextViewModelInstance = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'riveDataContextViewModelInstance')
        .asFunction();
final Pointer<Void> Function(
        Pointer<Void> file,
        Pointer<Uint64> viewModelIndices,
        Pointer<Uint64> instanceIndices,
        int count) _riveDataContextFromInstances =
    nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Pointer<Uint64>,
                    Pointer<Uint64>, Uint64)>>('riveDataContextFromInstances')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> dataContext, int index)
    _dataContextViewModelInstanceAt = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Uint64)>>(
            'dataContextViewModelInstanceAt')
        .asFunction();
final Pointer<Void> Function(
        Pointer<Pointer<Void>> instances, int count, Pointer<Void> parent)
    _dataContextFromViewModelInstancePointers = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Pointer<Void>>, Uint64,
                    Pointer<Void>)>>('dataContextFromViewModelInstancePointers')
        .asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteDataContextNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteDataContext');
final void Function(Pointer<Void> file) _deleteDataContext =
    _deleteDataContextNative.asFunction();

final int Function(Pointer<Void> dataBind) _riveDataBindDirt = nativeLib
    .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>('riveDataBindDirt')
    .asFunction();

final void Function(Pointer<Void> dataBind, int dirt) _riveDataBindSetDirt =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint64)>>(
            'riveDataBindSetDirt')
        .asFunction();
final int Function(Pointer<Void> dataBind) _riveDataBindFlags = nativeLib
    .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>('riveDataBindFlags')
    .asFunction();
final int Function(Pointer<Void> dataBind, int dirt) _riveDataBindUpdate =
    nativeLib
        .lookup<NativeFunction<Uint64 Function(Pointer<Void>, Uint64)>>(
            'riveDataBindUpdate')
        .asFunction();
final int Function(Pointer<Void> dataBind) _riveDataBindUpdateSourceBinding =
    nativeLib
        .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
            'riveDataBindUpdateSourceBinding')
        .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Float> out)
    _artboardBounds = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Float>)>>(
            'artboardBounds')
        .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Float> out)
    _artboardWorldBounds = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Float>)>>(
            'artboardWorldBounds')
        .asFunction();
final void Function(Pointer<Void> artboard) _artboardDrawCanvases = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'artboardDrawCanvases')
    .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard)
    _artboardGetDrawCanvasLuauState = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'artboardGetDrawCanvasLuauState')
        .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Void> renderer)
    _artboardDraw = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'artboardDraw')
        .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Void> renderer)
    _artboardDrawInternal = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'artboardDrawInternal')
        .asFunction();
final void Function(Pointer<Void> artboard) _artboardReset = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('artboardReset')
    .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Void> renderPath, double,
        double, double, double, double, double) _artboardAddToRenderPath =
    nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Void>, Float, Float, Float,
                    Float, Float, Float)>>('artboardAddToRenderPath')
        .asFunction();
final int Function(Pointer<Void> artboard) _artboardAnimationCount = nativeLib
    .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
        'artboardAnimationCount')
    .asFunction();
final int Function(Pointer<Void> artboard) _artboardStateMachineCount =
    nativeLib
        .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
            'artboardStateMachineCount')
        .asFunction();
final int Function(Pointer<Void> artboard) _artboardRootFocusDataCount =
    nativeLib
        .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
            'artboardRootFocusDataCount')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, int index)
    _artboardRootFocusNodeAt = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Uint64)>>(
            'artboardRootFocusNodeAt')
        .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Void> focusNode)
    _artboardSetExternalParentFocusNode = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'artboardSetExternalParentFocusNode')
        .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Void> parentFocusNode)
    _artboardBuildFocusTreeWithParent = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'artboardBuildFocusTreeWithParent')
        .asFunction();
final void Function(Pointer<Void> stateMachine, Pointer<Void> focusManager)
    _stateMachineSetExternalFocusManager = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'stateMachineSetExternalFocusManager')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> stateMachine)
    _stateMachineGetFocusManager = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'stateMachineGetFocusManager')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, int index)
    _artboardAnimationAt = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Uint64)>>(
            'artboardAnimationAt')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, int index)
    _artboardStateMachineAt = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Uint64)>>(
            'riveArtboardStateMachineAt')
        .asFunction();
final bool Function(Pointer<Void> artboard) _artboardGetFrameOrigin = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
        'artboardGetFrameOrigin')
    .asFunction();
final bool Function(Pointer<Void> artboard, double seconds, int flags)
    _artboardAdvance = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Float, Int)>>(
            'riveArtboardAdvance')
        .asFunction();
final double Function(Pointer<Void> artboard) _riveArtboardGetOpacity =
    nativeLib
        .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
            'riveArtboardGetOpacity')
        .asFunction();
final void Function(Pointer<Void> artboard, double opacity)
    _riveArtboardSetOpacity = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'riveArtboardSetOpacity')
        .asFunction();
final void Function(Pointer<Void> artboard, double hostOpacity)
    _riveArtboardSetHostOpacity = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'riveArtboardSetHostOpacity')
        .asFunction();
final bool Function(Pointer<Void> artboard) _riveArtboardUpdatePass = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
        'riveArtboardUpdatePass')
    .asFunction();
final bool Function(Pointer<Void> artboard) _riveArtboardHasComponentDirt =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
            'riveArtboardHasComponentDirt')
        .asFunction();
final double Function(Pointer<Void> artboard) _riveArtboardGetWidth = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'riveArtboardGetWidth')
    .asFunction();
final void Function(Pointer<Void> artboard, double width)
    _riveArtboardSetWidth = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'riveArtboardSetWidth')
        .asFunction();
final double Function(Pointer<Void> artboard) _riveArtboardGetHeight = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'riveArtboardGetHeight')
    .asFunction();
final void Function(Pointer<Void> artboard, double height)
    _riveArtboardSetHeight = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'riveArtboardSetHeight')
        .asFunction();
final double Function(Pointer<Void> artboard) _riveArtboardGetOriginX = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'riveArtboardGetOriginX')
    .asFunction();
final void Function(Pointer<Void> artboard, double value)
    _riveArtboardSetOriginX = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'riveArtboardSetOriginX')
        .asFunction();
final double Function(Pointer<Void> artboard) _riveArtboardGetOriginY = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'riveArtboardGetOriginY')
    .asFunction();
final void Function(Pointer<Void> artboard, double value)
    _riveArtboardSetOriginY = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'riveArtboardSetOriginY')
        .asFunction();
final double Function(Pointer<Void> artboard) _riveArtboardGetOriginalWidth =
    nativeLib
        .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
            'riveArtboardGetOriginalWidth')
        .asFunction();
final double Function(Pointer<Void> artboard) _riveArtboardGetOriginalHeight =
    nativeLib
        .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
            'riveArtboardGetOriginalHeight')
        .asFunction();
final Pointer<Utf8> Function(
        Pointer<Void> artboard, Pointer<Void> runName, Pointer<Void> path)
    _artboardGetText = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Utf8> Function(
                    Pointer<Void> artboard,
                    Pointer<Void> runName,
                    Pointer<Void> path)>>('artboardGetText')
        .asFunction();
final bool Function(Pointer<Void> artboard, Pointer<Void> runName,
        Pointer<Void> value, Pointer<Void> path) _artboardSetText =
    nativeLib
        .lookup<
            NativeFunction<
                Bool Function(
                    Pointer<Void> artboard,
                    Pointer<Void> runName,
                    Pointer<Void> value,
                    Pointer<Void> path)>>('artboardSetText')
        .asFunction();
final bool Function(Pointer<Void> artboard, bool value)
    _artboardSetFrameOrigin = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Bool value)>>(
            'artboardSetFrameOrigin')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, Pointer<Void> name)
    _artboardComponentNamed = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>,
                    Pointer<Void> name)>>('artboardComponentNamed')
        .asFunction();
final void Function(Pointer<Void> component, Pointer<Float> out)
    _componentGetWorldTransform = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Float>)>>(
            'componentGetWorldTransform')
        .asFunction();
final void Function(Pointer<Void> component, Pointer<Float> out)
    _componentGetLocalBounds = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Float>)>>(
            'componentGetLocalBounds')
        .asFunction();
final void Function(
  Pointer<Void> artboard,
  double xx,
  double xy,
  double yx,
  double yy,
  double tx,
  double ty,
) _componentSetWorldTransform = nativeLib
    .lookup<
        NativeFunction<
            Void Function(Pointer<Void>, Float xx, Float xy, Float yx, Float yy,
                Float tx, Float ty)>>('componentSetWorldTransform')
    .asFunction();
final void Function(Pointer<Void> component, Pointer<Float> out)
    _artboardGetRenderTransform = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Float>)>>(
            'artboardGetRenderTransform')
        .asFunction();
final void Function(
  Pointer<Void> artboard,
  double xx,
  double xy,
  double yx,
  double yy,
  double tx,
  double ty,
) _artboardSetRenderTransform = nativeLib
    .lookup<
        NativeFunction<
            Void Function(Pointer<Void>, Float xx, Float xy, Float yx, Float yy,
                Float tx, Float ty)>>('artboardSetRenderTransform')
    .asFunction();
final void Function(
  Pointer<Void> artboard,
  double xx,
  double xy,
  double yx,
  double yy,
  double tx,
  double ty,
) _componentSetLocalFromWorld = nativeLib
    .lookup<
        NativeFunction<
            Void Function(Pointer<Void>, Float xx, Float xy, Float yx, Float yy,
                Float tx, Float ty)>>('componentSetLocalFromWorld')
    .asFunction();
final double Function(Pointer<Void> component) _componentGetScaleX = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>('componentGetScaleX')
    .asFunction();
final void Function(Pointer<Void> component, double value) _componentSetScaleX =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'componentSetScaleX')
        .asFunction();
final double Function(Pointer<Void> component) _componentGetScaleY = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>('componentGetScaleY')
    .asFunction();
final void Function(Pointer<Void> component, double value) _componentSetScaleY =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'componentSetScaleY')
        .asFunction();
final void Function(Pointer<Void> component, double value) _componentSetX =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'componentSetX')
        .asFunction();
final double Function(Pointer<Void> component) _componentGetX = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>('componentGetX')
    .asFunction();
final void Function(Pointer<Void> component, double value) _componentSetY =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'componentSetY')
        .asFunction();
final double Function(Pointer<Void> component) _componentGetY = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>('componentGetY')
    .asFunction();
final double Function(Pointer<Void> component) _componentGetRotation = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'componentGetRotation')
    .asFunction();
final void Function(Pointer<Void> component, double value)
    _componentSetRotation = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'componentSetRotation')
        .asFunction();
final Pointer<Utf8> Function(Pointer<Void> artboard) _artboardName = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void> artboard)>>(
        'artboardName')
    .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard) _artboardGetInnerPointer =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void> artboard)>>(
            'artboardGetInnerPointer')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, Pointer<Void> name)
    _artboardAnimationNamed = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>,
                    Pointer<Void> name)>>('artboardAnimationNamed')
        .asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteArtboardInstanceNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteArtboardInstance');
final void Function(Pointer<Void> file) _deleteArtboardInstance =
    _deleteArtboardInstanceNative.asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteBindableArtboardNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteBindableArtboard');
final void Function(Pointer<Void> file) _deleteBindableArtboard =
    _deleteBindableArtboardNative.asFunction();
final Pointer<Void> Function(Pointer<Void> file)
    _riveArtboardStateMachineDefault = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'riveArtboardStateMachineDefault')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> file, Pointer<Void> name)
    _riveArtboardStateMachineNamed = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>,
                    Pointer<Void> name)>>('riveArtboardStateMachineNamed')
        .asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _animationInstanceDeleteNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'animationInstanceDelete');
final void Function(Pointer<Void> smi) _animationInstanceDelete =
    _animationInstanceDeleteNative.asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteStateMachineInstanceNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteStateMachineInstance');
final void Function(Pointer<Void> smi) _deleteStateMachineInstance =
    _deleteStateMachineInstanceNative.asFunction();
final Pointer<Utf8> Function(Pointer<Void> ami) _animationInstanceName =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void> ami)>>(
            'animationInstanceName')
        .asFunction();
final bool Function(Pointer<Void> ami, double) _animationInstanceAdvance =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Float)>>(
            'animationInstanceAdvance')
        .asFunction();

final double Function(Pointer<Void> ami) _animationInstanceGetTime = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'animationInstanceGetTime')
    .asFunction();
final double Function(Pointer<Void> ami) _animationInstanceGetDuration =
    nativeLib
        .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
            'animationInstanceGetDuration')
        .asFunction();
final double Function(Pointer<Void> ami, double)
    animationInstanceGetLocalSeconds = nativeLib
        .lookup<NativeFunction<Float Function(Pointer<Void>, Float)>>(
            'animationInstanceGetLocalSeconds')
        .asFunction();
final void Function(Pointer<Void> ami, double) _animationInstanceSetTime =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'animationInstanceSetTime')
        .asFunction();

final bool Function(Pointer<Void> ami, double)
    _animationInstanceAdvanceAndApply = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Float)>>(
            'animationInstanceAdvanceAndApply')
        .asFunction();
final void Function(Pointer<Void> ami, double) _animationInstanceApply =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'animationInstanceApply')
        .asFunction();
final Pointer<Utf8> Function(Pointer<Void> smi) _stateMachineInstanceName =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void> smi)>>(
            'stateMachineInstanceName')
        .asFunction();
final bool Function(Pointer<Void> ami, double, bool)
    _stateMachineInstanceAdvance = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Float, Bool)>>(
            'stateMachineInstanceAdvance')
        .asFunction();
final bool Function(Pointer<Void> ami, double)
    _stateMachineInstanceAdvanceAndApply = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Float)>>(
            'stateMachineInstanceAdvanceAndApply')
        .asFunction();
final int Function(Pointer<Void> smi) _stateMachineInstanceStateChangedCount =
    nativeLib
        .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
            'stateMachineInstanceStateChangedCount')
        .asFunction();
final Pointer<Utf8> Function(Pointer<Void> smi, int index)
    _stateMachineInstanceStateChangedNameByIndex = nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>, Uint64)>>(
            'stateMachineInstanceStateChangedNameByIndex')
        .asFunction();
final bool Function(Pointer<Void> ami, double x, double y)
    _stateMachineInstanceHitTest = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Float, Float)>>(
            'stateMachineInstanceHitTest')
        .asFunction();
final int Function(
  Pointer<Void> ami,
  double x,
  double y,
  int pointerId,
) _stateMachineInstancePointerDown = nativeLib
    .lookup<NativeFunction<Uint8 Function(Pointer<Void>, Float, Float, Int)>>(
        'stateMachineInstancePointerDown')
    .asFunction();
final int Function(
  Pointer<Void> ami,
  double x,
  double y,
  int pointerId,
) _stateMachineInstancePointerUp = nativeLib
    .lookup<NativeFunction<Uint8 Function(Pointer<Void>, Float, Float, Int)>>(
        'stateMachineInstancePointerUp')
    .asFunction();
final int Function(
  Pointer<Void> ami,
  double x,
  double y,
  double timeStamp,
  int pointerId,
) _stateMachineInstancePointerMove = nativeLib
    .lookup<
        NativeFunction<
            Uint8 Function(Pointer<Void>, Float, Float, Float,
                Int)>>('stateMachineInstancePointerMove')
    .asFunction();
final int Function(
  Pointer<Void> ami,
  double x,
  double y,
  int pointerId,
) _stateMachineInstancePointerExit = nativeLib
    .lookup<NativeFunction<Uint8 Function(Pointer<Void>, Float, Float, Int)>>(
        'stateMachineInstancePointerExit')
    .asFunction();
final int Function(
  Pointer<Void> ami,
  double x,
  double y,
  double timeStamp,
) _stateMachineInstanceDragStart = nativeLib
    .lookup<NativeFunction<Uint8 Function(Pointer<Void>, Float, Float, Float)>>(
        'stateMachineInstanceDragStart')
    .asFunction();
final int Function(
    Pointer<Void> ami,
    double x,
    double y,
    double
        timeStamp) _stateMachineInstanceDragEnd = nativeLib
    .lookup<NativeFunction<Uint8 Function(Pointer<Void>, Float, Float, Float)>>(
        'stateMachineInstanceDragEnd')
    .asFunction();
final bool Function(
  Pointer<Void> ami,
  Pointer<Uint8> data,
  int length,
) _stateMachineInstanceSubmitGamepadsFromBuffer = nativeLib
    .lookup<
        NativeFunction<
            Bool Function(Pointer<Void>, Pointer<Uint8>,
                Uint64)>>('stateMachineInstanceSubmitGamepadsFromBuffer')
    .asFunction();
final Pointer<Void> Function(
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
) _makeGamepadInvocation = nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(
              Uint8,
              Int32,
              Uint64,
              Pointer<Float>,
              Uint64,
              Pointer<Float>,
              Uint64,
              Uint8,
              Uint8,
              Uint8,
              Float,
            )>>('makeGamepadInvocation')
    .asFunction();
final void Function(Pointer<Void>) _deleteGamepadInvocation = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteGamepadInvocation')
    .asFunction();
final void Function(
  Pointer<Void> ami,
  Pointer<Void> invocation,
) _stateMachineInstanceDispatchGamepadInvocation = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
      'stateMachineInstanceDispatchGamepadInvocation',
    )
    .asFunction();
final Pointer<Void> Function(Pointer<Void> smi, int index) _stateMachineInput =
    nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>, Uint64 index)>>('stateMachineInput')
        .asFunction();
final int Function(Pointer<Void> input) _stateMachineInputType = nativeLib
    .lookup<NativeFunction<Uint16 Function(Pointer<Void>)>>(
        'stateMachineInputType')
    .asFunction();
final Pointer<Utf8> Function(Pointer<Void> input) _stateMachineInputName =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
            'stateMachineInputName')
        .asFunction();
final _StateMachineInputNative _stateMachineInstanceNumber = nativeLib
    .lookup<NativeFunction<_StateMachineInputNative>>(
        'stateMachineInstanceNumber')
    .asFunction();
final bool Function(Pointer<Void> smi) _stateMachineInstanceDone = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
        'stateMachineInstanceDone')
    .asFunction();
final double Function(Pointer<Void>) _getNumberValue = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>('getNumberValue')
    .asFunction();
final void Function(Pointer<Void>, double) _setNumberValue = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
        'setNumberValue')
    .asFunction();
void Function(Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Void>, Uint64)>>)
    _setStateMachineInputChangedCallback = nativeLib
        .lookup<
                NativeFunction<
                    Void Function(
                        Pointer<Void>,
                        Pointer<
                            NativeFunction<
                                Void Function(Pointer<Void>, Uint64)>>)>>(
            'setStateMachineInputChangedCallback')
        .asFunction();
void Function(Pointer<Void>, Pointer<NativeFunction<Void Function()>>)
    _setStateMachineDataBindChangedCallback = nativeLib
        .lookup<
                NativeFunction<
                    Void Function(Pointer<Void>,
                        Pointer<NativeFunction<Void Function()>>)>>(
            'setStateMachineDataBindChangedCallback')
        .asFunction();
void Function(
        Pointer<Void>, Pointer<NativeFunction<Void Function(Pointer<Void>)>>)
    _setArtboardLayoutChangedCallback = nativeLib
        .lookup<
                NativeFunction<
                    Void Function(
                        Pointer<Void>,
                        Pointer<
                            NativeFunction<Void Function(Pointer<Void>)>>)>>(
            'setArtboardLayoutChangedCallback')
        .asFunction();
void Function(
        Pointer<Void>,
        Pointer<
            NativeFunction<Uint8 Function(Pointer<Void>, Float, Float, Bool)>>)
    _setArtboardTestBoundsCallback = nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                    Pointer<Void>,
                    Pointer<
                        NativeFunction<
                            Uint8 Function(Pointer<Void>, Float, Float,
                                Bool)>>)>>('setArtboardTestBoundsCallback')
        .asFunction();
void Function(
        Pointer<Void>,
        Pointer<
            NativeFunction<Float Function(Pointer<Void>, Float, Float, Bool)>>)
    _setArtboardRootTransformCallback = nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                    Pointer<Void>,
                    Pointer<
                        NativeFunction<
                            Float Function(Pointer<Void>, Float, Float,
                                Bool)>>)>>('setArtboardRootTransformCallback')
        .asFunction();
void Function(Pointer<Void>,
        Pointer<NativeFunction<Uint8 Function(Pointer<Void>, Uint16)>>)
    _setArtboardIsAncestorCallback = nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                    Pointer<Void>,
                    Pointer<
                        NativeFunction<
                            Uint8 Function(Pointer<Void>,
                                Uint16)>>)>>('setArtboardIsAncestorCallback')
        .asFunction();
void Function(Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Void>, Uint32)>>)
    _setArtboardEventCallback = nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                    Pointer<Void>,
                    Pointer<
                        NativeFunction<
                            Void Function(Pointer<Void>,
                                Uint32)>>)>>('setArtboardEventCallback')
        .asFunction();
final _StateMachineInputNative _stateMachineInstanceBoolean = nativeLib
    .lookup<NativeFunction<_StateMachineInputNative>>(
        'stateMachineInstanceBoolean')
    .asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _deleteInputNative =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('deleteInput');
final void Function(Pointer<Void> file) _deleteInput =
    _deleteInputNative.asFunction();

final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteComponentNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteComponent');
final void Function(Pointer<Void> file) _deleteComponent =
    _deleteComponentNative.asFunction();
final bool Function(Pointer<Void>) _getBooleanValue = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>('getBooleanValue')
    .asFunction();
final void Function(Pointer<Void>, bool) _setBooleanValue = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
        'setBooleanValue')
    .asFunction();
final _StateMachineInputNative _stateMachineInstanceTrigger = nativeLib
    .lookup<NativeFunction<_StateMachineInputNative>>(
        'stateMachineInstanceTrigger')
    .asFunction();
final void Function(Pointer<Void> stateMachine, Pointer<Void> viewModelInstance)
    _stateMachineDataContextFromInstance = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'stateMachineDataContextFromInstance')
        .asFunction();
final void Function(Pointer<Void> stateMachine, Pointer<Void> dataContext)
    _stateMachineDataContext = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'stateMachineDataContext')
        .asFunction();
final void Function(Pointer<Void>) _fireTrigger = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('fireTrigger')
    .asFunction();
final void Function(Pointer<Pointer<Void>>, int, double) _batchAdvance =
    nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Pointer<Void>>, Uint64,
                    Float)>>('stateMachineInstanceBatchAdvance')
        .asFunction();
final void Function(Pointer<Pointer<Void>>, int, double, Pointer<Void>)
    _batchAdvanceAndRender = nativeLib
        .lookup<
                NativeFunction<
                    Void Function(
                        Pointer<Pointer<Void>>, Uint64, Float, Pointer<Void>)>>(
            'stateMachineInstanceBatchAdvanceAndRender')
        .asFunction();
final int Function(Pointer<Void> stateMachine)
    _stateMachineGetReportedEventCount = nativeLib
        .lookup<NativeFunction<Size Function(Pointer<Void>)>>(
            'stateMachineGetReportedEventCount')
        .asFunction();
final ReportedEventStruct Function(
    Pointer<Void> stateMachine,
    int
        index) _stateMachineReportedEventAt = nativeLib
    .lookup<NativeFunction<ReportedEventStruct Function(Pointer<Void>, Size)>>(
        'stateMachineReportedEventAt')
    .asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _deleteEventNative =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('deleteEvent');
final void Function(Pointer<Void> file) _deleteEvent =
    _deleteEventNative.asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteCustomPropertyNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteCustomProperty');
final void Function(Pointer<Void> file) _deleteCustomProperty =
    _deleteCustomPropertyNative.asFunction();
final Pointer<Utf8> Function(Pointer<Void>) _getEventName = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
        'getEventName')
    .asFunction();
final Pointer<Utf8> Function(Pointer<Void>) _getOpenUrlEventUrl = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
        'getOpenUrlEventUrl')
    .asFunction();
final int Function(Pointer<Void>) _getOpenUrlEventTarget = nativeLib
    .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>(
        'getOpenUrlEventTarget')
    .asFunction();
final int Function(Pointer<Void>) _getAudioEventAssetId = nativeLib
    .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>(
        'getAudioEventAssetId')
    .asFunction();
final Pointer<Utf8> Function(Pointer<Void>) _getAudioEventAssetName = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
        'getAudioEventAssetName')
    .asFunction();
final double Function(Pointer<Void>) _getAudioEventVolume = nativeLib
    .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
        'getAudioEventVolume')
    .asFunction();
final int Function(Pointer<Void> stateMachine) _getEventCustomPropertyCount =
    nativeLib
        .lookup<NativeFunction<Size Function(Pointer<Void>)>>(
            'getEventCustomPropertyCount')
        .asFunction();
final CustomPropertyStruct Function(
    Pointer<Void> event,
    int
        index) _getEventCustomProperty = nativeLib
    .lookup<NativeFunction<CustomPropertyStruct Function(Pointer<Void>, Size)>>(
        'getEventCustomProperty')
    .asFunction();
final double Function(Pointer<Void> property) _getCustomPropertyNumber =
    nativeLib
        .lookup<NativeFunction<Float Function(Pointer<Void> property)>>(
            'getCustomPropertyNumber')
        .asFunction();
final bool Function(Pointer<Void> property) _getCustomPropertyBoolean =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void> property)>>(
            'getCustomPropertyBoolean')
        .asFunction();
final Pointer<Utf8> Function(Pointer<Void> property) _getCustomPropertyString =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void> property)>>(
            'getCustomPropertyString')
        .asFunction();

final void Function(Pointer<Void> artboard, Pointer<Float> out)
    _artboardLayoutBounds = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Float>)>>(
            'artboardLayoutBounds')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard) _artboardTakeLayoutNode =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'artboardTakeLayoutNode')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard) _artboardAddedToHost =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'artboardAddedToHost')
        .asFunction();
final void Function(Pointer<Void> artboard) _artboardSyncStyleChanges =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
            'artboardSyncStyleChanges')
        .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Void> viewModelInstance,
        Pointer<Void> dataContext, bool isRoot)
    _artboardDataContextFromInstance = nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
                    Bool)>>('artboardDataContextFromInstance')
        .asFunction();
final void Function(Pointer<Void> artboard) _artboardUpdateDataBinds = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'artboardUpdateDataBinds')
    .asFunction();
final void Function(Pointer<Void> artboard, Pointer<Void> dataContext)
    _artboardInternalDataContext = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'artboardInternalDataContext')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard) _artboardDataContext =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'artboardDataContext')
        .asFunction();
final void Function(Pointer<Void> artboard) _artboardClearDataContext =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
            'artboardClearDataContext')
        .asFunction();
final void Function(Pointer<Void> artboard) _artboardUnbind = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('artboardUnbind')
    .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, double, int, bool)
    _artboardWidthOverride = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Float, Uint64,
                    Bool)>>('artboardWidthOverride')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, double, int, bool)
    _artboardHeightOverride = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Float, Uint64,
                    Bool)>>('artboardHeightOverride')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, bool)
    _artboardParentIsRow = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Bool)>>(
            'artboardParentIsRow')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, bool)
    _artboardWidthIntrinsicallySizeOverride = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Bool)>>(
            'artboardWidthIntrinsicallySizeOverride')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, bool)
    _artboardHeightIntrinsicallySizeOverride = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Bool)>>(
            'artboardHeightIntrinsicallySizeOverride')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> artboard, bool) _updateLayoutBounds =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Bool)>>(
            'updateLayoutBounds')
        .asFunction();
final void Function(Pointer<Void> artboard, int, int, double, int, double,
        double, double, double) _cascadeLayoutStyle =
    nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Int32, Int32, Float, Int32, Float,
                    Float, Float, Float)>>('cascadeLayoutStyle')
        .asFunction();
final void Function(Pointer<Pointer<Void>> artboards, int count, int, int,
        double, int, double, double, double, double) _cascadeLayoutStyleBatch =
    nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                    Pointer<Pointer<Void>>,
                    Int32,
                    Int32,
                    Int32,
                    Float,
                    Int32,
                    Float,
                    Float,
                    Float,
                    Float)>>('cascadeLayoutStyleBatch')
        .asFunction();
final void Function(
    Pointer<Pointer<Void>> artboards,
    int count,
    bool
        collapse) _cascadeCollapseBatch = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Pointer<Void>>, Int32, Bool)>>(
        'cascadeCollapseBatch')
    .asFunction();
final void Function(Pointer<Void> artboards, bool collapse) _cascadeCollapse =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
            'cascadeCollapse')
        .asFunction();

void Function(Pointer<Void>, Pointer<NativeFunction<Void Function()>>)
    _setArtboardLayoutDirtyCallback = nativeLib
        .lookup<
                NativeFunction<
                    Void Function(Pointer<Void>,
                        Pointer<NativeFunction<Void Function()>>)>>(
            'setArtboardLayoutDirtyCallback')
        .asFunction();
void Function(Pointer<Void>, Pointer<NativeFunction<Void Function()>>)
    _setArtboardTransformDirtyCallback = nativeLib
        .lookup<
                NativeFunction<
                    Void Function(Pointer<Void>,
                        Pointer<NativeFunction<Void Function()>>)>>(
            'setArtboardTransformDirtyCallback')
        .asFunction();

final Pointer<Void> Function(
        Pointer<Void>, int index, Pointer<Utf8> name, int propertyType)
    _viewModelInstancePropertyValue = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(Pointer<Void>, Uint64, Pointer<Utf8>,
                    Uint32)>>('viewModelInstancePropertyValue')
        .asFunction();
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteViewModelInstanceValueNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteViewModelInstanceValue');
final void Function(Pointer<Void> file) _deleteViewModelInstanceValue =
    _deleteViewModelInstanceValueNative.asFunction();

final Pointer<Void> Function(Pointer<Void>)
    _viewModelInstanceReferenceViewModel = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'viewModelInstanceReferenceViewModel')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> viewModelInstance, int index)
    _viewModelInstanceListItemViewModel = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Uint64)>>(
            'viewModelInstanceListItemViewModel')
        .asFunction();
final Pointer<Void> Function(Pointer<Void> file, int index, int indexInstance)
    _riveCopyViewModelInstance = nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Void>, Uint64, Uint64)>>('copyViewModelInstance')
        .asFunction();

final void Function(
        Pointer<Void> viewModelInstance, Pointer<Uint32> keepIds, int keepCount)
    _pruneViewModelInstanceToProperties = nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Uint32>,
                    Uint64)>>('pruneViewModelInstanceToProperties')
        .asFunction();

final class _ViewModelInstanceBufferResponseStruct extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int size;
}

final bool Function(Pointer<Void> file, Pointer<Void> instance,
        Pointer<_ViewModelInstanceBufferResponseStruct> response)
    _serializeViewModelInstanceByPointer = nativeLib
        .lookup<
                NativeFunction<
                    Bool Function(Pointer<Void>, Pointer<Void>,
                        Pointer<_ViewModelInstanceBufferResponseStruct>)>>(
            'serializeViewModelInstanceByPointer')
        .asFunction();

final void Function(Pointer<_ViewModelInstanceBufferResponseStruct> response)
    _freeViewModelInstanceSerializedData = nativeLib
        .lookup<
                NativeFunction<
                    Void Function(
                        Pointer<_ViewModelInstanceBufferResponseStruct>)>>(
            'freeViewModelInstanceSerializedData')
        .asFunction();

final void Function(Pointer<Void> artboard) _clearRuntimeViewModelInstances =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
            'clearRuntimeViewModelInstances')
        .asFunction();

final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteViewModelInstanceNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteViewModelInstance');
final void Function(Pointer<Void> file) _deleteViewModelInstance =
    _deleteViewModelInstanceNative.asFunction();
final Pointer<Void> Function(Pointer<Void>)
    _setViewModelInstanceNumberCallback = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceNumberCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>)
    _setViewModelInstanceBooleanCallback = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceBooleanCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>) _setViewModelInstanceColorCallback =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceColorCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>)
    _setViewModelInstanceStringCallback = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceStringCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>)
    _setViewModelInstanceTriggerCallback = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceTriggerCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>) _setViewModelInstanceListCallback =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceListCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>)
    _setViewModelInstanceViewModelCallback = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceViewModelCallback')
        .asFunction();
final int Function(Pointer<Void>) _viewModelInstanceListSize = nativeLib
    .lookup<NativeFunction<Size Function(Pointer<Void>)>>(
        'viewModelInstanceListSize')
    .asFunction();
final void Function(Pointer<Void>) _setViewModelInstanceAdvanced = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'setViewModelInstanceAdvanced')
    .asFunction();
final Pointer<Void> Function(Pointer<Void>) _setViewModelInstanceEnumCallback =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceEnumCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>)
    _setViewModelInstanceSymbolListIndexCallback = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceSymbolListIndexCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>) _setViewModelInstanceAssetCallback =
    nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceAssetCallback')
        .asFunction();
final Pointer<Void> Function(Pointer<Void>)
    _setViewModelInstanceArtboardCallback = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
            'setViewModelInstanceArtboardCallback')
        .asFunction();
final void Function(Pointer<Void>, double) _setViewModelInstanceNumberValue =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
            'setViewModelInstanceNumberValue')
        .asFunction();
final void Function(Pointer<Void>, bool) _setViewModelInstanceBooleanValue =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
            'setViewModelInstanceBooleanValue')
        .asFunction();
final void Function(Pointer<Void>, int) _setViewModelInstanceColorValue =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint64)>>(
            'setViewModelInstanceColorValue')
        .asFunction();
final void Function(Pointer<Void>, Pointer<Void>)
    _setViewModelInstanceStringValue = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'setViewModelInstanceStringValue')
        .asFunction();
final void Function(Pointer<Void>, int) _setViewModelInstanceTriggerValue =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
            'setViewModelInstanceTriggerValue')
        .asFunction();
final void Function(Pointer<Void>, int) _setViewModelInstanceEnumValue =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
            'setViewModelInstanceEnumValue')
        .asFunction();
final void Function(Pointer<Void>, int)
    _setViewModelInstanceSymbolListIndexValue = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
            'setViewModelInstanceSymbolListIndexValue')
        .asFunction();
final void Function(Pointer<Void>, int) _setViewModelInstanceAssetValue =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
            'setViewModelInstanceAssetValue')
        .asFunction();
final int Function(Pointer<Void>, Pointer<Void>)
    _viewModelInstanceAssetImageResolveRuntimeIndex = nativeLib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>, Pointer<Void>)>>(
            'viewModelInstanceAssetImageResolveRuntimeIndex')
        .asFunction();
final int Function(Pointer<Void>, Pointer<Void>)
    _viewModelInstanceAssetFontResolveRuntimeIndex = nativeLib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>, Pointer<Void>)>>(
            'viewModelInstanceAssetFontResolveRuntimeIndex')
        .asFunction();
final void Function(Pointer<Void>, int) _setViewModelInstanceArtboardValue =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
            'setViewModelInstanceArtboardValue')
        .asFunction();
final void Function(Pointer<Void>, Pointer<Void>)
    _setViewModelInstanceViewModelValue = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'setViewModelInstanceViewModelValue')
        .asFunction();
final void Function(Pointer<Void>, Pointer<Pointer<Void>>, int)
    _setViewModelInstanceListValue = nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Pointer<Void>>,
                    Uint64)>>('setViewModelInstanceListValue')
        .asFunction();

/// Reusable native buffer of [Pointer<Void>] entries.
///
/// Lazily allocates a fixed-capacity block on first use and reuses it for all
/// calls within capacity. For larger lists it performs a one-shot
/// malloc/call/free so there is no upper bound on list size.
/// Uses a callback to guarantee the fallback allocation is always freed even
/// if the caller throws.
class _NativePointerScratchBuffer {
  final int capacity;
  Pointer<Pointer<Void>>? _buffer;

  _NativePointerScratchBuffer(this.capacity);

  void use(int count, void Function(Pointer<Pointer<Void>> ptr) fn) {
    if (count <= capacity) {
      _buffer ??=
          malloc.allocate<Pointer<Void>>(capacity * sizeOf<Pointer<Void>>());
      fn(_buffer!);
    } else {
      final tmp =
          malloc.allocate<Pointer<Void>>(count * sizeOf<Pointer<Void>>());
      try {
        fn(tmp);
      } finally {
        malloc.free(tmp);
      }
    }
  }
}

final _instanceListScratchBuffer = _NativePointerScratchBuffer(256);
final _artboardBatchScratchBuffer = _NativePointerScratchBuffer(256);

final Pointer<Void> Function(Pointer<Void>) _makeRawText = nativeLib
    .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
        'makeRawText')
    .asFunction();

final Pointer<Pointer<Void>> Function(
        Pointer<Void> artboard, Pointer<Int> count) _artboardGetAllTextRuns =
    nativeLib
        .lookup<
            NativeFunction<
                Pointer<Pointer<Void>> Function(
                    Pointer<Void>, Pointer<Int>)>>('artboardGetAllTextRuns')
        .asFunction();

final void Function(Pointer<Pointer<Void>> arr) _freeTextRunsArray = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Pointer<Void>>)>>(
        'freeTextRunsArray')
    .asFunction();

final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _deleteTextValueRunNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'deleteTextValueRun');
final void Function(Pointer<Void> wrappedTextRun) _deleteTextValueRun =
    _deleteTextValueRunNative.asFunction();

final Pointer<Utf8> Function(Pointer<Void> wrappedTextRun) _textValueRunName =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
            'textValueRunName')
        .asFunction();

final Pointer<Utf8> Function(Pointer<Void> wrappedTextRun) _textValueRunText =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
            'textValueRunText')
        .asFunction();

final Pointer<Utf8> Function(Pointer<Void> wrappedTextRun) _textValueRunPath =
    nativeLib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
            'textValueRunPath')
        .asFunction();

final void Function(Pointer<Void> wrappedTextRun, Pointer<Void> text)
    _textValueRunSetText = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
            'textValueRunSetText')
        .asFunction();

abstract class _NativeFile {
  static final int Function(Pointer<Void> file) viewModelCount = nativeLib
      .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
          'riveFileViewModelCount')
      .asFunction();
  static final Pointer<Void> Function(
      Pointer<Void> file,
      int
          index) viewModelRuntimeByIndex = nativeLib
      .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Uint32)>>(
          'riveFileViewModelRuntimeByIndex')
      .asFunction();
  static final Pointer<Void> Function(Pointer<Void> file, Pointer<Void> name)
      viewModelRuntimeByName = nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> name)>>('riveFileViewModelRuntimeByName')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> file, Pointer<Void> artboard)
      defaultArtboardViewModelRuntime = nativeLib
          .lookup<
                  NativeFunction<
                      Pointer<Void> Function(
                          Pointer<Void>, Pointer<Void> artboard)>>(
              'riveFileDefaultArtboardViewModelRuntime')
          .asFunction();
  static final DataEnumArray Function(Pointer<Void> file) enums = nativeLib
      .lookup<NativeFunction<DataEnumArray Function(Pointer<Void> file)>>(
          'fileEnums')
      .asFunction();
  static final void Function(DataEnumArray dataArray) deleteDataEnumArray =
      nativeLib
          .lookup<NativeFunction<Void Function(DataEnumArray)>>(
              'deleteDataEnumArray')
          .asFunction();
  static final void Function() riveAdvanceFrameId = nativeLib
      .lookup<NativeFunction<Void Function()>>('riveAdvanceFrameId')
      .asFunction();
}

abstract class _NativeArtboard {
  static final void Function(
          Pointer<Void> artboard, Pointer<Void> viewModelInstance)
      setVMIRuntime = nativeLib
          .lookup<
              NativeFunction<
                  Void Function(
                    Pointer<Void>,
                    Pointer<Void>,
                  )>>('artboardSetVMIRuntime')
          .asFunction();
}

abstract class _NativeStateMachine {
  static final void Function(
          Pointer<Void> stateMachine, Pointer<Void> viewModelInstanceRuntime)
      setVMIRuntime = nativeLib
          .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
              'stateMachineSetVMIRuntime')
          .asFunction();
}

abstract class _NativeViewModelRuntime {
  static final int Function(Pointer<Void> viewModel) propertyCount = nativeLib
      .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
          'viewModelRuntimePropertyCount')
      .asFunction();
  static final int Function(Pointer<Void> viewModel) instanceCount = nativeLib
      .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
          'viewModelRuntimeInstanceCount')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Void> viewModel) name = nativeLib
      .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
          'viewModelRuntimeName')
      .asFunction();
  static final ViewModelPropertyDataArray Function(Pointer<Void> viewModel)
      properties = nativeLib
          .lookup<
              NativeFunction<
                  ViewModelPropertyDataArray Function(
                      Pointer<Void>)>>('viewModelRuntimeProperties')
          .asFunction();
  static final void Function(ViewModelPropertyDataArray dataArray)
      deletePropertyDataArray = nativeLib
          .lookup<NativeFunction<Void Function(ViewModelPropertyDataArray)>>(
              'deleteViewModelPropertyDataArray')
          .asFunction();
  static final Pointer<Void> Function(Pointer<Void> file, int index)
      createFromIndex = nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(
                      Pointer<Void>, Size index)>>('createVMIRuntimeFromIndex')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> name) createFromName =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> name)>>('createVMIRuntimeFromName')
          .asFunction();
  static final Pointer<Void> Function(Pointer<Void> viewModel) createDefault =
      nativeLib
          .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
              'createDefaultVMIRuntime')
          .asFunction();
  static final Pointer<Void> Function(Pointer<Void> viewModel) create =
      nativeLib
          .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
              'createVMIRuntime')
          .asFunction();
  static final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
      deleteNative =
      nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'deleteViewModelRuntime');
  static final void Function(Pointer<Void> smi) delete =
      deleteNative.asFunction();
}

abstract class _NativeVMIRuntime {
  static final Pointer<Utf8> Function(Pointer<Void> viewModel) name = nativeLib
      .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
          'vmiRuntimeName')
      .asFunction();
  static final ViewModelPropertyDataArray Function(Pointer<Void> viewModel)
      properties = nativeLib
          .lookup<
              NativeFunction<
                  ViewModelPropertyDataArray Function(
                      Pointer<Void>)>>('vmiRuntimeProperties')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getNumberProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> path)>>('vmiRuntimeGetNumberProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getStringProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> path)>>('vmiRuntimeGetStringProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getColorProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> path)>>('vmiRuntimeGetColorProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getBooleanProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> path)>>('vmiRuntimeGetBooleanProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getEnumProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> path)>>('vmiRuntimeGetEnumProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getTriggerProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> path)>>('vmiRuntimeGetTriggerProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getAssetImageProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void> viewModel,
                      Pointer<Void> path)>>('vmiRuntimeGetAssetImageProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getAssetFontProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void> viewModel,
                      Pointer<Void> path)>>('vmiRuntimeGetAssetFontProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getListProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void> viewModel,
                      Pointer<Void> path)>>('vmiRuntimeGetListProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getArtboardProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void> viewModel,
                      Pointer<Void> path)>>('vmiRuntimeGetArtboardProperty')
          .asFunction();
  static final Pointer<Void> Function(
          Pointer<Void> viewModel, Pointer<Void> path) getViewModelProperty =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void> path)>>('vmiRuntimeGetViewModelProperty')
          .asFunction();
  static final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
      deleteNative =
      nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'deleteVMIRuntime');
  static final void Function(Pointer<Void> smi) delete =
      deleteNative.asFunction();
}

abstract class _NativeVMIValueRuntime {
  static final bool Function(Pointer<Void>) hasChanged = nativeLib
      .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
          'vmiValueRuntimeHasChanged')
      .asFunction();
  static final void Function(Pointer<Void>) clearChanges = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'vmiValueRuntimeClearChanges')
      .asFunction();
  static final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
      deleteNative =
      nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'deleteVMIValueRuntime');
  static final void Function(Pointer<Void> file) delete =
      deleteNative.asFunction();
}

abstract class _NativeVMINumberRuntime {
  static final double Function(Pointer<Void>) getValue = nativeLib
      .lookup<NativeFunction<Float Function(Pointer<Void>)>>(
          'getVMINumberRuntimeValue')
      .asFunction();
  static final void Function(Pointer<Void>, double) setValue = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>, Float)>>(
          'setVMINumberRuntimeValue')
      .asFunction();
}

abstract class _NativeVMIStringRuntime {
  static final Pointer<Utf8> Function(Pointer<Void>) getValue = nativeLib
      .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
          'getVMIStringRuntimeValue')
      .asFunction();
  static final void Function(Pointer<Void>, Pointer<Utf8>) setValue = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Utf8>)>>(
          'setVMIStringRuntimeValue')
      .asFunction();
}

abstract class _NativeVMIColorRuntime {
  static final int Function(Pointer<Void>) getValue = nativeLib
      .lookup<NativeFunction<Int Function(Pointer<Void>)>>(
          'getVMIColorRuntimeValue')
      .asFunction();
  static final void Function(Pointer<Void>, int) setValue = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>, Int)>>(
          'setVMIColorRuntimeValue')
      .asFunction();
}

abstract class _NativeVMIBooleanRuntime {
  static final bool Function(Pointer<Void>) getValue = nativeLib
      .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
          'getVMIBooleanRuntimeValue')
      .asFunction();
  static final void Function(Pointer<Void>, bool) setValue = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
          'setVMIBooleanRuntimeValue')
      .asFunction();
}

abstract class _NativeVMIEnumRuntime {
  static final Pointer<Utf8> Function(Pointer<Void>) getValue = nativeLib
      .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
          'getVMIEnumRuntimeValue')
      .asFunction();
  static final void Function(Pointer<Void>, Pointer<Utf8>) setValue = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Utf8>)>>(
          'setVMIEnumRuntimeValue')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Void>) getEnumType = nativeLib
      .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
          'getVMIEnumRuntimeEnumType')
      .asFunction();
}

abstract class _NativeVMITriggerRuntime {
  static final void Function(Pointer<Void>) trigger = nativeLib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'triggerVMITriggerRuntime')
      .asFunction();
}

abstract class _NativeVMIAssetImageRuntime {
  static final void Function(Pointer<Void> property, Pointer<Void> value)
      setValue = nativeLib
          .lookup<
              NativeFunction<
                  Void Function(Pointer<Void> property,
                      Pointer<Void> value)>>('setVMIAssetImageRuntimeValue')
          .asFunction();
}

abstract class _NativeVMIAssetFontRuntime {
  static final void Function(Pointer<Void> property, Pointer<Void> value)
      setValue = nativeLib
          .lookup<
              NativeFunction<
                  Void Function(Pointer<Void> property,
                      Pointer<Void> value)>>('setVMIAssetFontRuntimeValue')
          .asFunction();
}

abstract class _NativeVMIListRuntime {
  static final int Function(Pointer<Void>) size = nativeLib
      .lookup<NativeFunction<Size Function(Pointer<Void>)>>(
          'getVMIListRuntimeSize')
      .asFunction();
  static final void Function(Pointer<Void> vmi, Pointer<Void> instance)
      addInstance = nativeLib
          .lookup<
              NativeFunction<
                  Void Function(Pointer<Void> vmi,
                      Pointer<Void> instance)>>('vmiListRuntimeAddInstance')
          .asFunction();
  static final bool Function(
          Pointer<Void> vmi, Pointer<Void> instance, int index) addInstanceAt =
      nativeLib
          .lookup<
              NativeFunction<
                  Bool Function(Pointer<Void> vmi, Pointer<Void> instance,
                      Int index)>>('vmiListRuntimeAddInstanceAt')
          .asFunction();
  static final void Function(Pointer<Void> vmi, Pointer<Void> instance)
      removeInstance = nativeLib
          .lookup<
              NativeFunction<
                  Void Function(Pointer<Void> vmi,
                      Pointer<Void> instance)>>('vmiListRuntimeRemoveInstance')
          .asFunction();
  static final void Function(Pointer<Void> vmi, int index) removeInstanceAt =
      nativeLib
          .lookup<NativeFunction<Void Function(Pointer<Void> vmi, Int index)>>(
              'vmiListRuntimeRemoveInstanceAt')
          .asFunction();
  static final Pointer<Void> Function(Pointer<Void> vmi, int index) instanceAt =
      nativeLib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void> vmi,
                      Int index)>>('vmiListRuntimeInstanceAt')
          .asFunction();
  static final void Function(Pointer<Void> vmi, int a, int b) swap = nativeLib
      .lookup<
          NativeFunction<
              Void Function(
                  Pointer<Void> vmi, Uint32 a, Uint32 b)>>('vmiListRuntimeSwap')
      .asFunction();
}

abstract class _NativeVMIArtboardRuntime {
  static final void Function(Pointer<Void> vmi, Pointer<Void> artboard,
          Pointer<Void> viewModelInstance) setValue =
      nativeLib
          .lookup<
                  NativeFunction<
                      Void Function(Pointer<Void> vmi, Pointer<Void> artboard,
                          Pointer<Void> viewModelInstance)>>(
              'setVMIArtboardRuntimeValue')
          .asFunction();
}

final Pointer<Float> _floatQueryBuffer =
    calloc.allocate<Float>(sizeOf<Float>() * 6);

sealed class FFIFileAsset
    implements FileAssetInterface, RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_deleteFileAssetNative);

  @override
  Pointer<Void> get pointer => _pointer;

  Pointer<Void> _pointer;
  final Factory _riveFactory;

  FFIFileAsset(this._pointer, this._riveFactory) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  int get assetId => _riveFileAssetId(pointer);

  @override
  String get name => safeString(_riveFileAssetName(pointer));

  @override
  String get fileExtension =>
      safeString(_riveFileAssetFileExtension(pointer), deleteNative: true);

  @override
  String get cdnBaseUrl => safeString(_riveFileAssetCdnBaseUrl(pointer));

  @override
  String get cdnUuid =>
      safeString(_riveFileAssetCdnUuid(pointer), deleteNative: true);

  @override
  Factory get riveFactory => _riveFactory;

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _finalizer.detach(this);
    _deleteFileAsset(_pointer);
    _pointer = nullptr;
  }
}

class FFIUnknownAsset extends FFIFileAsset implements UnknownAsset {
  FFIUnknownAsset(super.pointer, super.riveFactory);

  @override
  Future<bool> decode(Uint8List bytes) async {
    return false; // nothing to decode
  }
}

class FFIImageAsset extends FFIFileAsset implements ImageAsset {
  FFIImageAsset(super.pointer, super.riveFactory);

  @override
  double get width => _imageAssetGetWidth(pointer);

  @override
  double get height => _imageAssetGetHeight(pointer);

  @override
  bool renderImage(RenderImage renderImage) => riveFileAssetSetRenderImage(
        pointer,
        (renderImage as FFIRenderImage).pointer,
      );

  @override
  Future<bool> decode(Uint8List bytes) async {
    final decodedImage = await riveFactory.decodeImage(bytes);
    if (decodedImage == null) {
      return false;
    }
    final result = renderImage(decodedImage);
    decodedImage.dispose();
    return result;
  }
}

class FFIFontAsset extends FFIFileAsset implements FontAsset {
  FFIFontAsset(super.pointer, super.riveFactory);

  @override
  bool font(Font font) => riveFileAssetSetFont(
        pointer,
        (font as FontFFI).fontPtr,
      );

  @override
  Future<bool> decode(Uint8List bytes) async {
    final decodedFont = await riveFactory.decodeFont(bytes);
    if (decodedFont == null) {
      return Future.value(false);
    }
    final result = font(decodedFont);
    decodedFont.dispose();
    return result;
  }
}

class FFIAudioAsset extends FFIFileAsset implements AudioAsset {
  FFIAudioAsset(super.pointer, super.riveFactory);

  @override
  bool audio(AudioSource audioSource) {
    return riveFileAssetSetAudioSource(
      pointer,
      (audioSource as AudioSourceFFI).nativePtr,
    );
  }

  @override
  Future<bool> decode(Uint8List bytes) async {
    final decodedAudio = await riveFactory.decodeAudio(bytes);
    if (decodedAudio == null) {
      return false;
    }
    final result = audio(decodedAudio);
    decodedAudio.dispose();
    return result;
  }
}

class FFIRiveFile extends File implements RiveFFIReference, Finalizable {
  final Factory riveFactory;
  static final _finalizer = NativeFinalizer(_deleteRiveFileNative);

  @override
  String toString() {
    return 'FFIRiveFile($_pointer)';
  }

  @override
  Pointer<Void> get pointer => _pointer;

  Pointer<Void> _pointer;

  static final _instances = <int, InternalViewModelInstanceValue?>{};

  @internal
  static void internalRegisterViewModelInstance(
      int ptr, InternalViewModelInstanceValue vmi) {
    _instances[ptr] = vmi;
  }

  @internal
  static void internalUnregisterViewModelInstance(int ptr) {
    _instances[ptr] = null;
  }

  static void _vmNumberCallback(int ptr, double value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceNumber) {
      vmi.nativeValue = value;
    }
  }

  static void _vmBooleanCallback(int ptr, bool value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceBoolean) {
      vmi.nativeValue = value;
    }
  }

  static void _vmColorCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceColor) {
      vmi.nativeValue = value;
    }
  }

  static void _vmStringCallback(int ptr, Pointer<Utf8> value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceString) {
      vmi.nativeValue = value.toDartString();
    }
  }

  static void _vmTriggerCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceTrigger) {
      vmi.nativeValue = value;
    }
  }

  static void _vmEnumCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceEnum) {
      vmi.nativeValue = value;
    }
  }

  static void _vmSymbolListIndexCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceSymbolListIndex) {
      vmi.nativeValue = value;
    }
  }

  static void _vmAssetCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceAsset) {
      vmi.nativeValue = value;
    }
  }

  static void _vmArtboardCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIInternalViewModelInstanceArtboard) {
      vmi.nativeValue = value;
    }
  }

  static void _vmListCallback(int ptr) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIRiveInternalViewModelInstanceList) {
      vmi.syncValue();
    }
  }

  static void _vmViewModelCallback(int ptr) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is FFIRiveInternalViewModelInstanceViewModel) {
      vmi.syncValue();
    }
  }

  FFIRiveFile(this._pointer, this.riveFactory) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
    _initBindingCallbacks(
      Pointer.fromFunction(_vmNumberCallback),
      Pointer.fromFunction(_vmBooleanCallback),
      Pointer.fromFunction(_vmColorCallback),
      Pointer.fromFunction(_vmStringCallback),
      Pointer.fromFunction(_vmTriggerCallback),
      Pointer.fromFunction(_vmEnumCallback),
      Pointer.fromFunction(_vmSymbolListIndexCallback),
      Pointer.fromFunction(_vmAssetCallback),
      Pointer.fromFunction(_vmArtboardCallback),
      Pointer.fromFunction(_vmListCallback),
      Pointer.fromFunction(_vmViewModelCallback),
    );
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _finalizer.detach(this);
    _deleteRiveFile(_pointer);
    _pointer = nullptr;
  }

  @override
  Artboard? defaultArtboard({bool frameOrigin = true}) {
    var ptr = _riveFileArtboardDefault(pointer, frameOrigin);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveArtboard(ptr, riveFactory);
  }

  @override
  Artboard? artboard(String name, {bool frameOrigin = true}) {
    var nativeString = name.toNativeUtf8();
    var ptr = _riveFileArtboardNamed(pointer, nativeString.cast(), frameOrigin);
    malloc.free(nativeString);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveArtboard(ptr, riveFactory);
  }

  @override
  Artboard? artboardAt(int index, {bool frameOrigin = true}) {
    var ptr = _riveFileArtboardByIndex(pointer, index, frameOrigin);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveArtboard(ptr, riveFactory);
  }

  @override
  BindableArtboard? artboardToBind(
    String name, {
    ViewModelInstance? viewModelInstance,
  }) {
    var nativeString = name.toNativeUtf8();
    var ptr = _riveFileArtboardToBindNamed(pointer, nativeString.cast());
    malloc.free(nativeString);
    if (ptr == nullptr) {
      return null;
    }
    final ffiViewModelInstance =
        viewModelInstance is FFIRiveViewModelInstanceRuntime
            ? viewModelInstance
            : null;
    return FFIBindableArtboard(
      ptr,
      viewModelInstance: ffiViewModelInstance,
    );
  }

  @override
  InternalDataContext? internalDataContext(
      int viewModelIndex, int instanceIndex) {
    var ptr = _riveDataContext(pointer, viewModelIndex, instanceIndex);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveInternalDataContext(ptr);
  }

  @override
  InternalDataContext? internalDataContextFromInstances(
      List<int> viewModelIndices, List<int> instanceIndices) {
    assert(viewModelIndices.length == instanceIndices.length);
    final count = viewModelIndices.length;
    if (count == 0) return null;
    final vmPtr = malloc.allocate<Uint64>(count * sizeOf<Uint64>());
    final instPtr = malloc.allocate<Uint64>(count * sizeOf<Uint64>());
    try {
      for (var i = 0; i < count; i++) {
        vmPtr[i] = viewModelIndices[i];
        instPtr[i] = instanceIndices[i];
      }
      final ptr = _riveDataContextFromInstances(pointer, vmPtr, instPtr, count);
      if (ptr == nullptr) return null;
      return FFIRiveInternalDataContext(ptr);
    } finally {
      malloc.free(vmPtr);
      malloc.free(instPtr);
    }
  }

  @override
  InternalDataContext? internalDataContextFromNativeInstances(
      List<InternalViewModelInstance> instances,
      {InternalDataContext? parent}) {
    if (instances.isEmpty) return null;
    final count = instances.length;
    final ptrs =
        malloc.allocate<Pointer<Void>>(count * sizeOf<Pointer<Void>>());
    try {
      for (var i = 0; i < count; i++) {
        ptrs[i] = (instances[i] as FFIRiveInternalViewModelInstance).pointer;
      }
      final parentPtr = parent != null
          ? (parent as FFIRiveInternalDataContext).pointer
          : nullptr;
      final ptr =
          _dataContextFromViewModelInstancePointers(ptrs, count, parentPtr);
      if (ptr == nullptr) {
        return null;
      }
      return FFIRiveInternalDataContext(ptr);
    } finally {
      malloc.free(ptrs);
    }
  }

  @override
  InternalViewModelInstance? copyViewModelInstance(
      int viewModelIndex, int instanceIndex) {
    var ptr =
        _riveCopyViewModelInstance(pointer, viewModelIndex, instanceIndex);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveInternalViewModelInstance(ptr);
  }

  @override
  void clearViewModelInstances() {
    _clearRuntimeViewModelInstances(pointer);
  }

  static const int _uint32Max = 4294967295;

  @override
  int? resolveViewModelInstanceAssetImageRuntimeIndex(int coreAddress) {
    if (coreAddress == 0) {
      return null;
    }
    final r = _viewModelInstanceAssetImageResolveRuntimeIndex(
        pointer, Pointer<Void>.fromAddress(coreAddress));
    if (r < 0 || r == _uint32Max) {
      return null;
    }
    return r;
  }

  @override
  int? resolveViewModelInstanceAssetFontRuntimeIndex(int coreAddress) {
    if (coreAddress == 0) {
      return null;
    }
    final r = _viewModelInstanceAssetFontResolveRuntimeIndex(
        pointer, Pointer<Void>.fromAddress(coreAddress));
    if (r < 0 || r == _uint32Max) {
      return null;
    }
    return r;
  }

  @override
  Uint8List? requestSerializedViewModelInstance(
      InternalViewModelInstance instance) {
    if (instance is! FFIRiveInternalViewModelInstance) {
      return null;
    }
    final response = calloc<_ViewModelInstanceBufferResponseStruct>();
    try {
      final ok = _serializeViewModelInstanceByPointer(
          pointer, instance.pointer, response);
      if (!ok || response.ref.data == nullptr || response.ref.size <= 0) {
        return null;
      }
      return Uint8List.fromList(
          response.ref.data.asTypedList(response.ref.size).toList());
    } finally {
      _freeViewModelInstanceSerializedData(response);
      calloc.free(response);
    }
  }

  @override
  void setScriptingState(covariant LuauStateFFI vm) {
    riveFileSetScriptingVM(pointer, vm.pointer);
  }

  @override
  int get viewModelCount => _NativeFile.viewModelCount(pointer);

  @override
  ViewModel? viewModelByIndex(int index) {
    var ptr = _NativeFile.viewModelRuntimeByIndex(pointer, index);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveViewModelRuntime(ptr);
  }

  @override
  ViewModel? viewModelByName(String name) {
    var nativeString = name.toNativeUtf8();
    var ptr = _NativeFile.viewModelRuntimeByName(pointer, nativeString.cast());
    malloc.free(nativeString);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveViewModelRuntime(ptr);
  }

  @override
  ViewModel? defaultArtboardViewModel(covariant FFIRiveArtboard artboard) {
    var ptr =
        _NativeFile.defaultArtboardViewModelRuntime(pointer, artboard.pointer);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveViewModelRuntime(ptr);
  }

  @override
  List<DataEnum> get enums {
    final result = _NativeFile.enums(pointer);
    final list = <DataEnum>[];
    for (int i = 0; i < result.length; i++) {
      final ffiEnum = result.data[i];
      final name = ffiEnum.name.toDartString();
      final enumList = <String>[];
      for (int j = 0; j < ffiEnum.length; j++) {
        enumList.add(ffiEnum.values[j].toDartString());
      }
      list.add(DataEnum(name, enumList));
    }

    _NativeFile.deleteDataEnumArray(result);
    return list;
  }

  @override
  void advanceFrameId() {
    _NativeFile.riveAdvanceFrameId();
  }
}

/// A helper function to convert the native property data array into a
/// Dart list of [ViewModelProperty].
List<ViewModelProperty> _generateViewModelPropertyList(
    ViewModelPropertyDataArray result) {
  final list = <ViewModelProperty>[];
  for (int i = 0; i < result.length; i++) {
    final ffiProp = result.data[i];
    final type = DataType.values[ffiProp.type];

    final name = ffiProp.name.toDartString();
    list.add(ViewModelProperty(name, type));
  }

  _NativeViewModelRuntime.deletePropertyDataArray(result);
  return list;
}

class FFIRiveViewModelRuntime
    implements ViewModel, RiveFFIReference, Finalizable {
  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  static final _finalizer =
      NativeFinalizer(_NativeViewModelRuntime.deleteNative);

  FFIRiveViewModelRuntime(this._pointer) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  int get propertyCount => _NativeViewModelRuntime.propertyCount(pointer);

  @override
  int get instanceCount => _NativeViewModelRuntime.instanceCount(pointer);

  @override
  String get name => safeString(_NativeViewModelRuntime.name(pointer));

  @override
  List<ViewModelProperty> get properties {
    final result = _NativeViewModelRuntime.properties(pointer);
    return _generateViewModelPropertyList(result);
  }

  @override
  ViewModelInstance? createInstanceByIndex(int index) {
    var ptr = _NativeViewModelRuntime.createFromIndex(pointer, index);
    return ptr == nullptr ? null : FFIRiveViewModelInstanceRuntime(ptr);
  }

  @override
  ViewModelInstance? createInstanceByName(String name) {
    var nativeString = name.toNativeUtf8();
    var ptr =
        _NativeViewModelRuntime.createFromName(pointer, nativeString.cast());
    malloc.free(nativeString);
    return ptr == nullptr ? null : FFIRiveViewModelInstanceRuntime(ptr);
  }

  @override
  ViewModelInstance? createDefaultInstance() {
    var ptr = _NativeViewModelRuntime.createDefault(pointer);
    return ptr == nullptr ? null : FFIRiveViewModelInstanceRuntime(ptr);
  }

  @override
  ViewModelInstance? createInstance() {
    var ptr = _NativeViewModelRuntime.create(pointer);
    return ptr == nullptr ? null : FFIRiveViewModelInstanceRuntime(ptr);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _NativeViewModelRuntime.delete(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }
}

class FFIRiveViewModelInstanceRuntime
    with ViewModelInstanceCallbackMixin, AdvanceRequestMixin
    implements ViewModelInstance, RiveFFIReference, Finalizable {
  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  late FFIRiveViewModelInstanceRuntime _rootViewModelInstance;

  static final _finalizer = NativeFinalizer(_NativeVMIRuntime.deleteNative);

  FFIRiveViewModelInstanceRuntime(
    this._pointer, {
    FFIRiveViewModelInstanceRuntime? rootViewModelInstance,
  }) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
    if (rootViewModelInstance == null) {
      _rootViewModelInstance = this;
    } else {
      _rootViewModelInstance = rootViewModelInstance;
    }
  }

  Pointer<Void> _findPointerByPath(
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>) function,
      String path) {
    var nativeString = path.toNativeUtf8();
    var ptr = function.call(pointer, nativeString.cast());
    malloc.free(nativeString);
    return ptr;
  }

  @override
  String get name => safeString(_NativeVMIRuntime.name(pointer));

  @override
  List<ViewModelProperty> get properties {
    final result = _NativeVMIRuntime.properties(pointer);
    return _generateViewModelPropertyList(result);
  }

  @override
  ViewModelInstanceNumber? number(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getNumberProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceNumberRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceString? string(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getStringProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceStringRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceBoolean? boolean(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getBooleanProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceBooleanRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceColor? color(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getColorProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceColorRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceEnum? enumerator(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getEnumProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceEnumRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceTrigger? trigger(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getTriggerProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceTriggerRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceAssetImage? image(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getAssetImageProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceAssetImageRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceAssetFont? font(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getAssetFontProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceAssetFontRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceList? list(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getListProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceListRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceArtboard? artboard(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getArtboardProperty, path);
    return ptr == nullptr
        ? null
        : FFIViewModelInstanceArtboardRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstance? viewModel(String path) {
    var ptr = _findPointerByPath(_NativeVMIRuntime.getViewModelProperty, path);
    return ptr == nullptr
        ? null
        : FFIRiveViewModelInstanceRuntime(
            ptr,
            rootViewModelInstance: _rootViewModelInstance,
          );
  }

  @override
  void dispose() {
    clearCallbacks();
    removeAllAdvanceRequestListeners();

    if (_pointer == nullptr) {
      return;
    }
    _NativeVMIRuntime.delete(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
    _pointer = nullptr;
  }

  @override
  bool get isDisposed => _pointer == nullptr;
}

abstract class FFIViewModelInstanceValueRuntime
    implements ViewModelInstanceValue, RiveFFIReference, Finalizable {
  static final _finalizer =
      NativeFinalizer(_NativeVMIValueRuntime.deleteNative);

  final FFIRiveViewModelInstanceRuntime _rootViewModelInstance;
  @override
  ViewModelInstance get rootViewModelInstance => _rootViewModelInstance;

  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  FFIViewModelInstanceValueRuntime(this._pointer, this._rootViewModelInstance) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _NativeVMIValueRuntime.delete(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }
}

abstract class FFIViewModelInstanceObservableValueRuntime<T>
    extends FFIViewModelInstanceValueRuntime
    with ViewModelInstanceObservableValueMixin<T> {
  FFIViewModelInstanceObservableValueRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  bool get hasChanged => _NativeVMIValueRuntime.hasChanged(pointer);

  @override
  void clearChanges() => _NativeVMIValueRuntime.clearChanges(pointer);

  @override
  void dispose() {
    clearListeners();
    super.dispose();
  }
}

class FFIViewModelInstanceNumberRuntime
    extends FFIViewModelInstanceObservableValueRuntime<double>
    implements ViewModelInstanceNumber {
  FFIViewModelInstanceNumberRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  double get nativeValue => _NativeVMINumberRuntime.getValue(pointer);

  @override
  set nativeValue(double value) =>
      _NativeVMINumberRuntime.setValue(pointer, value);
}

class FFIViewModelInstanceStringRuntime
    extends FFIViewModelInstanceObservableValueRuntime<String>
    implements ViewModelInstanceString {
  FFIViewModelInstanceStringRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  String get nativeValue =>
      safeString(_NativeVMIStringRuntime.getValue(pointer));

  @override
  set nativeValue(String value) {
    var nativeString = value.toNativeUtf8();
    _NativeVMIStringRuntime.setValue(pointer, nativeString.cast());
    malloc.free(nativeString);
  }
}

class FFIViewModelInstanceBooleanRuntime
    extends FFIViewModelInstanceObservableValueRuntime<bool>
    implements ViewModelInstanceBoolean {
  FFIViewModelInstanceBooleanRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  bool get nativeValue => _NativeVMIBooleanRuntime.getValue(pointer);

  @override
  set nativeValue(bool value) =>
      _NativeVMIBooleanRuntime.setValue(pointer, value);
}

class FFIViewModelInstanceColorRuntime
    extends FFIViewModelInstanceObservableValueRuntime<Color>
    implements ViewModelInstanceColor {
  FFIViewModelInstanceColorRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  Color get nativeValue {
    var color = _NativeVMIColorRuntime.getValue(pointer);
    return Color(color);
  }

  @override
  set nativeValue(Color value) {
    // ignore: deprecated_member_use
    _NativeVMIColorRuntime.setValue(pointer, value.value);
  }
}

class FFIViewModelInstanceEnumRuntime
    extends FFIViewModelInstanceObservableValueRuntime<String>
    implements ViewModelInstanceEnum {
  FFIViewModelInstanceEnumRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  String get nativeValue =>
      safeString(_NativeVMIEnumRuntime.getValue(pointer), deleteNative: true);

  @override
  set nativeValue(String value) {
    var nativeString = value.toNativeUtf8();
    _NativeVMIEnumRuntime.setValue(pointer, nativeString.cast());
    malloc.free(nativeString);
  }

  @override
  String get enumType => safeString(_NativeVMIEnumRuntime.getEnumType(pointer),
      deleteNative: true);
}

class FFIViewModelInstanceTriggerRuntime
    extends FFIViewModelInstanceObservableValueRuntime<bool>
    implements ViewModelInstanceTrigger {
  FFIViewModelInstanceTriggerRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  void trigger() {
    _rootViewModelInstance.requestAdvance();
    _NativeVMITriggerRuntime.trigger(pointer);
  }

  @override
  bool get nativeValue {
    return false;
  }

  @override
  set nativeValue(bool value) {
    if (value) {
      trigger();
    }
  }
}

class FFIViewModelInstanceAssetImageRuntime
    extends FFIViewModelInstanceValueRuntime
    implements ViewModelInstanceAssetImage {
  FFIViewModelInstanceAssetImageRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  set value(covariant FFIRenderImage? value) {
    _rootViewModelInstance.requestAdvance();
    _NativeVMIAssetImageRuntime.setValue(pointer, value?.pointer ?? nullptr);
  }
}

class FFIViewModelInstanceAssetFontRuntime
    extends FFIViewModelInstanceValueRuntime
    implements ViewModelInstanceAssetFont {
  FFIViewModelInstanceAssetFontRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  set value(covariant FontFFI? value) {
    _rootViewModelInstance.requestAdvance();
    _NativeVMIAssetFontRuntime.setValue(pointer, value?.fontPtr ?? nullptr);
  }
}

class FFIViewModelInstanceListRuntime extends FFIViewModelInstanceValueRuntime
    implements ViewModelInstanceList {
  FFIViewModelInstanceListRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );
  @override
  int get length => _NativeVMIListRuntime.size(pointer);

  @override
  void add(covariant FFIRiveViewModelInstanceRuntime instance) {
    _rootViewModelInstance.requestAdvance();
    _NativeVMIListRuntime.addInstance(
      pointer,
      instance.pointer,
    );
  }

  @override
  bool insert(
    int index,
    covariant FFIRiveViewModelInstanceRuntime instance,
  ) {
    RangeError.checkNotNegative(index, "index");
    if (index >= length) {
      throw RangeError.range(index, 0, length - 1, "index");
    }
    _rootViewModelInstance.requestAdvance();
    return _NativeVMIListRuntime.addInstanceAt(
        pointer, instance.pointer, index);
  }

  @override
  void remove(covariant FFIRiveViewModelInstanceRuntime instance) {
    _rootViewModelInstance.requestAdvance();
    _NativeVMIListRuntime.removeInstance(
      pointer,
      instance.pointer,
    );
  }

  @override
  void removeAt(int index) {
    RangeError.checkNotNegative(index, "index");
    if (index >= length) {
      throw RangeError.range(index, 0, length - 1, "index");
    }
    _rootViewModelInstance.requestAdvance();
    _NativeVMIListRuntime.removeInstanceAt(pointer, index);
  }

  @override
  ViewModelInstance instanceAt(int index) {
    RangeError.checkNotNegative(index, "index");
    if (index >= length) {
      throw RangeError.range(index, 0, length - 1, "index");
    }
    final ptr = _NativeVMIListRuntime.instanceAt(pointer, index);
    if (ptr == nullptr) {
      throw RiveError.nullNativePointer();
    }
    return FFIRiveViewModelInstanceRuntime(ptr,
        rootViewModelInstance: _rootViewModelInstance);
  }

  @override
  void swap(int a, int b) {
    RangeError.checkNotNegative(a, "a");
    RangeError.checkNotNegative(b, "b");
    final length = this.length;
    if (a >= length) {
      throw RangeError.range(a, 0, length - 1, "a");
    }
    if (b >= length) {
      throw RangeError.range(b, 0, length - 1, "b");
    }
    _rootViewModelInstance.requestAdvance();
    _NativeVMIListRuntime.swap(pointer, a, b);
  }

  @override
  ViewModelInstance first() => instanceAt(0);

  @override
  ViewModelInstance last() => instanceAt(length - 1);

  @override
  ViewModelInstance? firstOrNull() => length > 0 ? first() : null;

  @override
  ViewModelInstance? lastOrNull() => length > 0 ? last() : null;

  @override
  ViewModelInstance operator [](int index) => instanceAt(index);

  @override
  void operator []=(
    int index,
    covariant FFIRiveViewModelInstanceRuntime value,
  ) =>
      insert(index, value);
}

class FFIViewModelInstanceArtboardRuntime
    extends FFIViewModelInstanceValueRuntime
    implements ViewModelInstanceArtboard {
  FFIViewModelInstanceArtboardRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  set value(covariant FFIBindableArtboard value) {
    _rootViewModelInstance.requestAdvance();
    _NativeVMIArtboardRuntime.setValue(
      pointer,
      value.pointer,
      value.viewModelInstancePointer,
    );
  }
}

class FFIStateMachine extends StateMachine
    with EventListenerMixin, AdvanceRequestMixin
    implements RiveFFIReference, Finalizable {
  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;
  static final _finalizer = NativeFinalizer(_deleteStateMachineInstanceNative);
  final _stateChangedListeners = <void Function(String stateName)>{};

  FFIStateMachine(this._pointer) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  String get name =>
      safeString(_stateMachineInstanceName(pointer), deleteNative: true);

  @override
  bool advance(double elapsedSeconds, bool newFrame) =>
      _stateMachineInstanceAdvance(pointer, elapsedSeconds, newFrame);

  @override
  bool advanceAndApply(double elapsedSeconds) {
    _handleEvents();
    final result =
        _stateMachineInstanceAdvanceAndApply(pointer, elapsedSeconds);
    boundRuntimeViewModelInstance?.handleCallbacks();
    if (_stateChangedListeners.isNotEmpty) {
      final count = _stateMachineInstanceStateChangedCount(pointer);
      for (var i = 0; i < count; i++) {
        final stateName = safeString(
            _stateMachineInstanceStateChangedNameByIndex(pointer, i),
            deleteNative: true);
        for (final listener in _stateChangedListeners.toList()) {
          listener(stateName);
        }
      }
    }
    return result;
  }

  @override
  void dispose() {
    super.dispose();
    removeAllEventListeners();
    _stateChangedListeners.clear();
    if (_pointer == nullptr) {
      return;
    }
    _deleteStateMachineInstance(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }

  @override
  CallbackHandler onStateChanged(void Function(String stateName) callback) {
    _stateChangedListeners.add(callback);
    return ClosureCallbackHandler(() {
      _stateChangedListeners.remove(callback);
    });
  }

  @override
  CallbackHandler onInputChanged(void Function(int index) callback) {
    final nativeCallback =
        NativeCallable<Void Function(Pointer<Void>, Uint64)>.isolateLocal(
      (Pointer<Void> stateMachineInput, int index) {
        return callback(index);
      },
    );
    _setStateMachineInputChangedCallback(
        pointer, nativeCallback.nativeFunction);

    return ClosureCallbackHandler(() {
      _setStateMachineInputChangedCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  CallbackHandler onDataBindChanged(void Function() callback) {
    final nativeCallback = NativeCallable<Void Function()>.isolateLocal(
      callback,
    );
    _setStateMachineDataBindChangedCallback(
        pointer, nativeCallback.nativeFunction);

    return ClosureCallbackHandler(() {
      nativeCallback.close();
    });
  }

  Pointer<Void> _inputWrapper(
    _StateMachineInputNative nativeFunction,
    String name, {
    String? path,
  }) {
    final nativeName = name.toNativeUtf8();
    final nativePath = path?.toNativeUtf8() ?? nullptr;
    final ptr = nativeFunction(pointer, nativeName.cast(), nativePath.cast());
    malloc.free(nativeName);
    if (nativePath != nullptr) {
      malloc.free(nativePath);
    }
    return ptr;
  }

  @override
  BooleanInput? boolean(String name, {String? path}) {
    final ptr = _inputWrapper(_stateMachineInstanceBoolean, name, path: path);
    return ptr == nullptr ? null : FFIBooleanInput(ptr, this);
  }

  @override
  NumberInput? number(String name, {String? path}) {
    final ptr = _inputWrapper(_stateMachineInstanceNumber, name, path: path);
    return ptr == nullptr ? null : FFINumberInput(ptr, this);
  }

  @override
  TriggerInput? trigger(String name, {String? path}) {
    final ptr = _inputWrapper(_stateMachineInstanceTrigger, name, path: path);
    return ptr == nullptr ? null : FFITriggerInput(ptr, this);
  }

  @override
  Input? inputAt(int index) {
    var inputPointer = _stateMachineInput(pointer, index);
    if (inputPointer == nullptr) {
      return null;
    }
    switch (_stateMachineInputType(inputPointer)) {
      case 56:
        return FFINumberInput(inputPointer, this);
      case 58:
        return FFITriggerInput(inputPointer, this);
      case 59:
        return FFIBooleanInput(inputPointer, this);
      default:
        return null;
    }
  }

  @override
  bool get isDone => _stateMachineInstanceDone(pointer);

  @override
  bool hitTest(Vec2D position) =>
      _stateMachineInstanceHitTest(pointer, position.x, position.y);

  @override
  HitResult pointerDown(Vec2D position, {int pointerId = 0}) {
    var result = _stateMachineInstancePointerDown(
        pointer, position.x, position.y, pointerId);
    return HitResult.values[result];
  }

  @override
  HitResult pointerExit(Vec2D position, {int pointerId = 0}) {
    var result = _stateMachineInstancePointerExit(
        pointer, position.x, position.y, pointerId);
    return HitResult.values[result];
  }

  @override
  HitResult pointerMove(Vec2D position,
      {double? timeStamp, int pointerId = 0}) {
    var result = _stateMachineInstancePointerMove(
        pointer, position.x, position.y, timeStamp ?? 0, pointerId);
    return HitResult.values[result];
  }

  @override
  HitResult pointerUp(Vec2D position, {int pointerId = 0}) {
    var result = _stateMachineInstancePointerUp(
        pointer, position.x, position.y, pointerId);
    return HitResult.values[result];
  }

  @override
  HitResult dragStart(Vec2D position, {double? timeStamp}) {
    var result = _stateMachineInstanceDragStart(
        pointer, position.x, position.y, timeStamp ?? 0);
    return HitResult.values[result];
  }

  @override
  HitResult dragEnd(Vec2D position, {double? timeStamp}) {
    var result = _stateMachineInstanceDragEnd(
        pointer, position.x, position.y, timeStamp ?? 0);
    return HitResult.values[result];
  }

  @override
  bool submitGamepadsFromBuffer(Uint8List buffer) {
    if (buffer.isEmpty) {
      return false;
    }
    final native = malloc.allocate<Uint8>(buffer.length);
    try {
      native.asTypedList(buffer.length).setAll(0, buffer);
      return _stateMachineInstanceSubmitGamepadsFromBuffer(
          pointer, native, buffer.length);
    } finally {
      malloc.free(native);
    }
  }

  @override
  void dispatchGamepadInvocation(GamepadInvocationHandle handle) {
    final ffiHandle = handle as FFIGamepadInvocationHandle;
    final native = ffiHandle._pointer;
    if (native == nullptr) {
      return;
    }
    _stateMachineInstanceDispatchGamepadInvocation(pointer, native);
  }

  @override
  void enableSemantics() {
    SemanticsFFI.enableSemantics(pointer);
  }

  @override
  SemanticsDiff drainSemanticsDiff() => SemanticsFFI.drainDiff(pointer);

  @override
  bool focusSemanticNode(int semanticNodeId) =>
      SemanticsFFI.requestFocus(pointer, semanticNodeId);

  @override
  void fireSemanticAction(int semanticNodeId, SemanticActionType actionType) {
    SemanticsFFI.fireAction(pointer, semanticNodeId, actionType.index);
  }

  @override
  void internalBindViewModelInstance(InternalViewModelInstance instance) {
    _stateMachineDataContextFromInstance(
        pointer, (instance as FFIRiveInternalViewModelInstance).pointer);
  }

  @override
  void bindViewModelInstance(
      covariant FFIRiveViewModelInstanceRuntime viewModelInstance) {
    super.bindViewModelInstance(viewModelInstance);
    _NativeStateMachine.setVMIRuntime(pointer, viewModelInstance.pointer);
  }

  @override
  void internalDataContext(InternalDataContext dataContext) {
    _stateMachineDataContext(
        pointer, (dataContext as FFIRiveInternalDataContext).pointer);
  }

  void _handleEvents() {
    final listeners = eventListeners.toList();
    // Only fetch reported events if a listener is present.
    if (listeners.isNotEmpty) {
      final events = reportedEvents();
      for (var listener in listeners) {
        events.forEach(listener);
      }
    }
  }

  @override
  List<Event> reportedEvents() {
    final count = _stateMachineGetReportedEventCount(pointer);
    List<Event> events = [];
    for (var index = 0; index < count; index++) {
      final eventReport = _stateMachineReportedEventAt(pointer, index);
      final eventType = EventType.from[eventReport.type];
      if (eventType == null) {
        // An event of this type is not handled at runtime, immediately dispose
        // native resources and continue to the next event.
        _deleteEvent(eventReport.event);
        continue;
      }
      Event event = switch (eventType) {
        EventType.general => FFIGeneralEvent(eventReport),
        EventType.openURL => FFIOpenURLEvent(eventReport),
        EventType.audio => FFIAudioRuntimeEvent(eventReport),
      };
      events.add(event);
    }
    return events;
  }

  /// Get the focus manager for this state machine.
  /// Returns the active focus manager (external if set, internal otherwise).
  @override
  focus.FocusManager? get focusManager {
    final ptr = _stateMachineGetFocusManager(pointer);
    if (ptr == nullptr) {
      return null;
    }
    return NativeFocusManagerWrapper(ptr);
  }

  /// Set an external focus manager to use instead of the internal one.
  /// This allows nested artboards to share focus with their parent.
  @override
  void setExternalFocusManager(int? pointerAddress) {
    final ptr = pointerAddress != null
        ? Pointer<Void>.fromAddress(pointerAddress)
        : nullptr;
    _stateMachineSetExternalFocusManager(pointer, ptr);
  }
}

/// FFI-backed implementation of [GamepadInvocationHandle]. Owns the native
/// `ListenerInvocation*` returned by `makeGamepadInvocation`.
class FFIGamepadInvocationHandle implements GamepadInvocationHandle {
  Pointer<Void> _pointer;
  FFIGamepadInvocationHandle._(this._pointer);

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _deleteGamepadInvocation(_pointer);
    _pointer = nullptr;
  }
}

/// Top-level factory for [GamepadInvocationHandle] resolved via the
/// conditional import in `rive.dart`. Copies the button/axis arrays into
/// temporary native buffers, hands them to `makeGamepadInvocation`, then
/// frees them — the C++ side copies into its own `std::vector`.
FFIGamepadInvocationHandle makeGamepadInvocationHandle({
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
  final buttonPtr = bN == 0 ? nullptr : calloc<Float>(bN);
  final axesPtr = aN == 0 ? nullptr : calloc<Float>(aN);
  try {
    for (var i = 0; i < bN; i++) {
      buttonPtr[i] = buttonValues[i];
    }
    for (var i = 0; i < aN; i++) {
      axesPtr[i] = axes[i];
    }
    final native = _makeGamepadInvocation(
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
    return FFIGamepadInvocationHandle._(native);
  } finally {
    if (buttonPtr != nullptr) calloc.free(buttonPtr);
    if (axesPtr != nullptr) calloc.free(axesPtr);
  }
}

sealed class FFIEvent
    with EventPropertyMixin
    implements EventInterface, RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_deleteEventNative);

  final ReportedEventStruct _native;
  FFIEvent._(this._native) {
    _finalizer.attach(this, pointer.cast(), detach: this);
  }

  @override
  void dispose() {
    if (pointer == nullptr) {
      return;
    }
    _deleteEvent(pointer);
    _native.event = nullptr;
    _finalizer.detach(this);
  }

  @override
  Pointer<Void> get pointer => _native.event;

  Map<String, CustomProperty>? _cachedProperties;

  @override
  Map<String, CustomProperty> get properties {
    if (_cachedProperties == null) {
      _populateProperties();
    }
    return _cachedProperties!;
  }

  void _populateProperties() {
    _cachedProperties = {};
    final count = _getEventCustomPropertyCount(pointer);
    for (var index = 0; index < count; index++) {
      final propertyStruct = _getEventCustomProperty(pointer, index);
      final propertyType = CustomPropertyType.from[propertyStruct.type];
      CustomProperty? property = switch (propertyType) {
        null => null,
        CustomPropertyType.number => FFICustomNumberProperty(propertyStruct),
        CustomPropertyType.boolean => FFICustomBooleanProperty(propertyStruct),
        CustomPropertyType.string => FFICustomStringProperty(propertyStruct),
      };

      if (property != null) {
        _cachedProperties![property.name] = property;
      }
    }
  }

  @override
  String get name => safeString(_getEventName(pointer));

  @override
  double get secondsDelay => _native.secondsDelay;

  @override
  EventType get type => EventType.from[_native.type] ?? EventType.general;
}

class FFIGeneralEvent extends FFIEvent implements GeneralEvent {
  FFIGeneralEvent(super._native) : super._();

  @override
  String toString() {
    return 'GeneralEvent{type: $type, name: $name, properties: $properties}';
  }
}

class FFIOpenURLEvent extends FFIEvent implements OpenUrlEvent {
  FFIOpenURLEvent(super._native) : super._();

  @override
  OpenUrlTarget get target {
    final targetInt = _getOpenUrlEventTarget(pointer);
    final value = OpenUrlTarget.from[targetInt];
    return value ?? OpenUrlTarget.blank;
  }

  @override
  String get url => safeString(_getOpenUrlEventUrl(pointer));

  @override
  String toString() {
    return 'OpenURLEvent{type: $type, name: $name, url: $url, target: $target, properties: $properties}';
  }
}

class FFIAudioRuntimeEvent extends FFIEvent implements AudioRuntimeEvent {
  FFIAudioRuntimeEvent(super._native) : super._();

  @override
  int get assetId => _getAudioEventAssetId(pointer);

  @override
  String get assetName => safeString(_getAudioEventAssetName(pointer));

  @override
  double get volume => _getAudioEventVolume(pointer);

  @override
  String toString() {
    return 'AudioRuntimeEvent{type: $type, name: $name, assetId: $assetId, '
        'assetName: $assetName, volume: $volume, properties: $properties}';
  }
}

sealed class FFICustomProperty<T>
    implements CustomPropertyInterface<T>, RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_deleteCustomPropertyNative);

  final CustomPropertyStruct _native;
  FFICustomProperty(this._native) {
    _finalizer.attach(this, pointer.cast(), detach: this);
  }

  @override
  void dispose() {
    if (pointer == nullptr) {
      return;
    }
    _deleteCustomProperty(pointer);
    _native.property = nullptr;
    _finalizer.detach(this);
  }

  @override
  Pointer<Void> get pointer => _native.property;

  @override
  String get name => safeString(_native.name);

  @override
  CustomPropertyType get type => CustomPropertyType.from[_native.type]!;

  @override
  String toString() {
    return 'CustomProperty{type: $type, name: $name, value: $value}';
  }
}

class FFICustomNumberProperty extends FFICustomProperty<double>
    implements CustomNumberProperty {
  FFICustomNumberProperty(super._native);

  @override
  double get value => _getCustomPropertyNumber(pointer);
}

class FFICustomBooleanProperty extends FFICustomProperty<bool>
    implements CustomBooleanProperty {
  FFICustomBooleanProperty(super._native);

  @override
  bool get value => _getCustomPropertyBoolean(pointer);
}

class FFICustomStringProperty extends FFICustomProperty<String>
    implements CustomStringProperty {
  FFICustomStringProperty(super._native);

  @override
  String get value => safeString(_getCustomPropertyString(pointer));
}

abstract class FFIInput extends Input implements RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_deleteInputNative);

  final FFIStateMachine _stateMachine;

  @override
  Pointer<Void> pointer;

  FFIInput(this.pointer, this._stateMachine) {
    _finalizer.attach(this, pointer.cast(), detach: this);
  }

  @override
  String get name => safeString(_stateMachineInputName(pointer));

  @override
  void dispose() {
    if (pointer == nullptr) {
      return;
    }
    _deleteInput(pointer);
    pointer = nullptr;
    _finalizer.detach(this);
  }

  @override
  StateMachine get internalStateMachine => _stateMachine;
}

class FFIBooleanInput extends FFIInput implements BooleanInput {
  FFIBooleanInput(super.pointer, super._stateMachine);

  @override
  bool get value => _getBooleanValue(pointer);

  @override
  set value(bool value) {
    _setBooleanValue(pointer, value);
    internalStateMachine.requestAdvance();
  }
}

class FFINumberInput extends FFIInput implements NumberInput {
  FFINumberInput(super.pointer, super._stateMachine);

  @override
  double get value => _getNumberValue(pointer);

  @override
  set value(double value) {
    _setNumberValue(pointer, value);
    internalStateMachine.requestAdvance();
  }
}

class FFITriggerInput extends FFIInput implements TriggerInput {
  FFITriggerInput(super.pointer, super._stateMachine);

  @override
  void fire() {
    _fireTrigger(pointer);
    internalStateMachine.requestAdvance();
  }
}

class FFIRiveArtboard extends Artboard
    implements RiveFFIReference, Finalizable {
  @override
  final Factory riveFactory;
  static final _finalizer = NativeFinalizer(_deleteArtboardInstanceNative);

  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  @override
  int? get nativePointerAddress => _pointer.address;

  @override
  int? get artboardUniqueId => _artboardGetInnerPointer(_pointer).address;

  FFIRiveArtboard(this._pointer, this.riveFactory) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  String get name => safeString(_artboardName(pointer), deleteNative: true);

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _deleteArtboardInstance(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }

  @override
  void drawCanvases() {
    _artboardDrawCanvases(pointer);
  }

  @override
  LuauState? get drawCanvasState {
    final statePtr = _artboardGetDrawCanvasLuauState(pointer);
    if (statePtr.address == 0) return null;
    // ignore: deprecated_member_use_from_same_package
    return LuauStateFFI(statePtr);
  }

  @override
  void draw(Renderer renderer) {
    assert(riveFactory.isValidRenderer(renderer));
    _artboardDraw(pointer, (renderer as RiveFFIReference).pointer);
  }

  @override
  void drawInternal(Renderer renderer) {
    assert(riveFactory.isValidRenderer(renderer));
    _artboardDrawInternal(pointer, (renderer as RiveFFIReference).pointer);
  }

  @override
  void advanceFrameId() {
    _NativeFile.riveAdvanceFrameId();
  }

  @override
  void reset() {
    _artboardReset(pointer);
  }

  @override
  StateMachine? defaultStateMachine() {
    var smiPointer = _riveArtboardStateMachineDefault(pointer);
    if (smiPointer == nullptr) {
      return null;
    }
    return FFIStateMachine(smiPointer);
  }

  @override
  StateMachine? stateMachine(String name) {
    var nativeString = name.toNativeUtf8();
    var smiPointer =
        _riveArtboardStateMachineNamed(pointer, nativeString.cast());
    malloc.free(nativeString);
    if (smiPointer == nullptr) {
      return null;
    }
    return FFIStateMachine(smiPointer);
  }

  @override
  StateMachine? stateMachineAt(int index) =>
      FFIStateMachine(_artboardStateMachineAt(pointer, index));

  @override
  AABB get bounds {
    _artboardBounds(pointer, _floatQueryBuffer);
    return AABB.fromValues(_floatQueryBuffer[0], _floatQueryBuffer[1],
        _floatQueryBuffer[2], _floatQueryBuffer[3]);
  }

  @override
  AABB get worldBounds {
    _artboardWorldBounds(pointer, _floatQueryBuffer);
    return AABB.fromValues(_floatQueryBuffer[0], _floatQueryBuffer[1],
        _floatQueryBuffer[2], _floatQueryBuffer[3]);
  }

  @override
  AABB get layoutBounds {
    _artboardLayoutBounds(pointer, _floatQueryBuffer);
    return AABB.fromValues(_floatQueryBuffer[0], _floatQueryBuffer[1],
        _floatQueryBuffer[2], _floatQueryBuffer[3]);
  }

  @override
  void addToRenderPath(RenderPath renderPath, Mat2D transform) =>
      _artboardAddToRenderPath(
        pointer,
        (renderPath as RiveFFIReference).pointer,
        transform[0],
        transform[1],
        transform[2],
        transform[3],
        transform[4],
        transform[5],
      );
  @override
  int animationCount() => _artboardAnimationCount(pointer);

  @override
  int stateMachineCount() => _artboardStateMachineCount(pointer);

  @override
  int get rootFocusDataCount => _artboardRootFocusDataCount(pointer);

  @override
  focus.FocusNode? rootFocusNodeAt(int index) {
    final ptr = _artboardRootFocusNodeAt(pointer, index);
    if (ptr == nullptr) {
      return null;
    }
    return NativeFocusNodeWrapper(ptr);
  }

  @override
  void setExternalParentFocusNode(focus.FocusNode? node) {
    Pointer<Void> nodePtr;
    if (node is NativeFocusNodeWrapper) {
      nodePtr = node.pointer;
    } else if (node is FocusNodeFFI) {
      nodePtr = node.pointer;
    } else {
      nodePtr = nullptr;
    }
    _artboardSetExternalParentFocusNode(pointer, nodePtr);
  }

  @override
  void buildFocusTreeWithParent(focus.FocusNode? parentNode) {
    Pointer<Void> nodePtr;
    if (parentNode is NativeFocusNodeWrapper) {
      nodePtr = parentNode.pointer;
    } else if (parentNode is FocusNodeFFI) {
      nodePtr = parentNode.pointer;
    } else {
      nodePtr = nullptr;
    }
    _artboardBuildFocusTreeWithParent(pointer, nodePtr);
  }

  @override
  Animation animationAt(int index) {
    return FFIAnimation(_artboardAnimationAt(pointer, index));
  }

  @override
  Animation? animationNamed(String name) {
    var nativeString = name.toNativeUtf8();
    var ptr = _artboardAnimationNamed(pointer, nativeString.cast());
    malloc.free(nativeString);

    if (ptr == nullptr) {
      return null;
    }

    return FFIAnimation(ptr);
  }

  @override
  bool get frameOrigin => _artboardGetFrameOrigin(pointer);

  @override
  set frameOrigin(bool value) => _artboardSetFrameOrigin(pointer, value);

  @override
  Component? component(String name) {
    var nativeString = name.toNativeUtf8();
    var ptr = _artboardComponentNamed(pointer, nativeString.cast());
    malloc.free(nativeString);

    if (ptr == nullptr) {
      return null;
    }

    return FFIComponent(ptr);
  }

  @override
  String getText(String runName, {String? path}) {
    final nativeRunName = runName.toNativeUtf8();
    final nativePath = path?.toNativeUtf8() ?? nullptr;
    final stringPointer =
        _artboardGetText(pointer, nativeRunName.cast(), nativePath.cast());
    malloc.free(nativeRunName);
    if (nativePath != nullptr) {
      malloc.free(nativePath);
    }
    return safeString(stringPointer);
  }

  @override
  bool setText(String runName, String value, {String? path}) {
    final nativeRunName = runName.toNativeUtf8();
    final nativeValue = value.toNativeUtf8();
    final nativePath = path?.toNativeUtf8() ?? nullptr;

    final result = _artboardSetText(
        pointer, nativeRunName.cast(), nativeValue.cast(), nativePath.cast());
    malloc.free(nativeRunName);
    malloc.free(nativeValue);
    if (nativePath != nullptr) {
      malloc.free(nativePath);
    }
    return result;
  }

  @override
  Mat2D get renderTransform {
    _artboardGetRenderTransform(pointer, _floatQueryBuffer);
    return Mat2D()
      ..values[0] = _floatQueryBuffer[0]
      ..values[1] = _floatQueryBuffer[1]
      ..values[2] = _floatQueryBuffer[2]
      ..values[3] = _floatQueryBuffer[3]
      ..values[4] = _floatQueryBuffer[4]
      ..values[5] = _floatQueryBuffer[5];
  }

  @override
  set renderTransform(Mat2D value) => _artboardSetRenderTransform(
        pointer,
        value[0],
        value[1],
        value[2],
        value[3],
        value[4],
        value[5],
      );

  // Flags AdvanceFlags.advanceNested and AdvanceFlags.newFrame set to true
  // by default
  @override
  bool advance(double seconds, {int flags = 9}) =>
      _artboardAdvance(pointer, seconds, flags);

  @override
  double get opacity => _riveArtboardGetOpacity(pointer);

  @override
  set opacity(double value) => _riveArtboardSetOpacity(pointer, value);

  @override
  set hostOpacity(double value) => _riveArtboardSetHostOpacity(pointer, value);

  @override
  double get width => _riveArtboardGetWidth(pointer);

  @override
  set width(double value) => _riveArtboardSetWidth(pointer, value);

  @override
  double get height => _riveArtboardGetHeight(pointer);

  @override
  set height(double value) => _riveArtboardSetHeight(pointer, value);

  @override
  double get originX => _riveArtboardGetOriginX(pointer);

  @override
  set originX(double value) => _riveArtboardSetOriginX(pointer, value);

  @override
  double get originY => _riveArtboardGetOriginY(pointer);

  @override
  set originY(double value) => _riveArtboardSetOriginY(pointer, value);

  @override
  double get heightOriginal => _riveArtboardGetOriginalHeight(pointer);

  @override
  double get widthOriginal => _riveArtboardGetOriginalWidth(pointer);

  @override
  void resetArtboardSize() {
    width = widthOriginal;
    height = heightOriginal;
  }

  @override
  CallbackHandler onEvent(void Function(int) callback) {
    final nativeCallback =
        NativeCallable<Void Function(Pointer<Void>, Uint32)>.isolateLocal(
            (Pointer<Void> artboardPtr, int id) => callback(id));
    _setArtboardEventCallback(pointer, nativeCallback.nativeFunction);
    return ClosureCallbackHandler(() {
      _setArtboardEventCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  CallbackHandler onLayoutChanged(void Function() callback) {
    final nativeCallback =
        NativeCallable<Void Function(Pointer<Void>)>.isolateLocal(
            (Pointer<Void> artboardPtr) => callback());
    _setArtboardLayoutChangedCallback(pointer, nativeCallback.nativeFunction);
    return ClosureCallbackHandler(() {
      _setArtboardLayoutChangedCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  CallbackHandler onTestBounds(
      int Function(Vec2D position, bool skip) callback) {
    final nativeCallback = NativeCallable<
            Uint8 Function(Pointer<Void>, Float, Float, Bool)>.isolateLocal(
        (Pointer<Void> artboardPtr, double x, double y, bool skip) {
      return callback(Vec2D.fromValues(x, y), skip);
    }, exceptionalReturn: 1);
    _setArtboardTestBoundsCallback(pointer, nativeCallback.nativeFunction);
    return ClosureCallbackHandler(() {
      _setArtboardTestBoundsCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  CallbackHandler onIsAncestor(int Function(int artboardId) callback) {
    final nativeCallback =
        NativeCallable<Uint8 Function(Pointer<Void>, Uint16)>.isolateLocal(
            (Pointer<Void> artboardPtr, int artboardId) {
      return callback(artboardId);
    }, exceptionalReturn: 1);
    _setArtboardIsAncestorCallback(pointer, nativeCallback.nativeFunction);
    return ClosureCallbackHandler(() {
      _setArtboardIsAncestorCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  CallbackHandler onRootTransform(
      double Function(Vec2D position, bool xAxis) callback) {
    final nativeCallback = NativeCallable<
            Float Function(Pointer<Void>, Float, Float, Bool)>.isolateLocal(
        (Pointer<Void> artboardPtr, double x, double y, bool xAxis) {
      return callback(Vec2D.fromValues(x, y), xAxis);
    }, exceptionalReturn: 1.0);
    _setArtboardRootTransformCallback(pointer, nativeCallback.nativeFunction);
    return ClosureCallbackHandler(() {
      _setArtboardRootTransformCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  CallbackHandler onLayoutDirty(void Function() callback) {
    final nativeCallback =
        NativeCallable<Void Function()>.isolateLocal(callback);
    _setArtboardLayoutDirtyCallback(pointer, nativeCallback.nativeFunction);
    return ClosureCallbackHandler(() {
      _setArtboardLayoutDirtyCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  CallbackHandler onTransformDirty(void Function() callback) {
    final nativeCallback =
        NativeCallable<Void Function()>.isolateLocal(callback);
    _setArtboardTransformDirtyCallback(pointer, nativeCallback.nativeFunction);
    return ClosureCallbackHandler(() {
      _setArtboardTransformDirtyCallback(
        pointer,
        nullptr,
      );
      nativeCallback.close();
    });
  }

  @override
  dynamic takeLayoutNode() => _artboardTakeLayoutNode(pointer);

  @override
  void addedToHost() => _artboardAddedToHost(pointer);

  @override
  void syncStyleChanges() => _artboardSyncStyleChanges(pointer);

  @override
  void widthOverride(double width, int widthUnitValue, bool isRow) =>
      _artboardWidthOverride(pointer, width, widthUnitValue, isRow);

  @override
  void heightOverride(double height, int heightUnitValue, bool isRow) =>
      _artboardHeightOverride(pointer, height, heightUnitValue, isRow);

  @override
  void parentIsRow(bool isRow) => _artboardParentIsRow(pointer, isRow);

  @override
  void widthIntrinsicallySizeOverride(bool intrinsic) =>
      _artboardWidthIntrinsicallySizeOverride(pointer, intrinsic);

  @override
  void heightIntrinsicallySizeOverride(bool intrinsic) =>
      _artboardHeightIntrinsicallySizeOverride(pointer, intrinsic);

  @override
  void updateLayoutBounds(bool animate) =>
      _updateLayoutBounds(pointer, animate);

  @override
  void cascadeLayoutStyle(
          int direction,
          int interpolationType,
          double interpolationTime,
          int interpolatorTypeKey,
          double p0,
          double p1,
          double p2,
          double p3) =>
      _cascadeLayoutStyle(pointer, direction, interpolationType,
          interpolationTime, interpolatorTypeKey, p0, p1, p2, p3);

  @override
  void cascadeLayoutStyleBatch(
      List<Artboard> artboards,
      int direction,
      int interpolationType,
      double interpolationTime,
      int interpolatorTypeKey,
      double p0,
      double p1,
      double p2,
      double p3) {
    final count = artboards.length;
    _artboardBatchScratchBuffer.use(count, (ptr) {
      for (var i = 0; i < count; i++) {
        ptr[i] = (artboards[i] as FFIRiveArtboard).pointer;
      }
      _cascadeLayoutStyleBatch(ptr, count, direction, interpolationType,
          interpolationTime, interpolatorTypeKey, p0, p1, p2, p3);
    });
  }

  @override
  void cascadeCollapseBatch(List<Artboard> artboards, bool collapse) {
    final count = artboards.length;
    _artboardBatchScratchBuffer.use(count, (ptr) {
      for (var i = 0; i < count; i++) {
        ptr[i] = (artboards[i] as FFIRiveArtboard).pointer;
      }
      _cascadeCollapseBatch(ptr, count, collapse);
    });
  }

  @override
  void cascadeCollapse(bool collapse) {
    _cascadeCollapse(pointer, collapse);
  }

  @override
  void internalBindViewModelInstance(InternalViewModelInstance instance,
      InternalDataContext? dataContext, bool isRoot) {
    _artboardDataContextFromInstance(
        pointer,
        (instance as FFIRiveInternalViewModelInstance).pointer,
        dataContext != null
            ? (dataContext as FFIRiveInternalDataContext).pointer
            : nullptr,
        isRoot);
  }

  @override
  void internalUpdateDataBinds() {
    _artboardUpdateDataBinds(pointer);
  }

  @override
  void bindViewModelInstance(
      covariant FFIRiveViewModelInstanceRuntime viewModelInstance) {
    _NativeArtboard.setVMIRuntime(pointer, viewModelInstance.pointer);
  }

  @override
  void internalSetDataContext(InternalDataContext dataContext) {
    _artboardInternalDataContext(
        pointer, (dataContext as FFIRiveInternalDataContext).pointer);
  }

  @override
  InternalDataContext? get internalGetDataContext {
    var ptr = _artboardDataContext(pointer);
    if (ptr == nullptr) {
      return null;
    }
    return FFIRiveInternalDataContext(ptr);
  }

  @override
  void internalClearDataContext() {
    _artboardClearDataContext(pointer);
  }

  @override
  void internalUnbind() {
    _artboardUnbind(pointer);
  }

  @override
  bool updatePass() {
    return _riveArtboardUpdatePass(pointer);
  }

  @override
  bool hasComponentDirt() {
    return _riveArtboardHasComponentDirt(pointer);
  }

  @override
  List<TextValueRunRuntime> get textRuns {
    final countPtr = calloc<Int>();
    final arrayPtr = _artboardGetAllTextRuns(pointer, countPtr);
    final count = countPtr.value;
    calloc.free(countPtr);

    if (arrayPtr == nullptr || count == 0) {
      if (arrayPtr != nullptr) {
        _freeTextRunsArray(arrayPtr);
      }
      return [];
    }

    final textRuns = <TextValueRunRuntime>[];
    for (int i = 0; i < count; i++) {
      final wrappedTextRunPtr = arrayPtr[i];
      if (wrappedTextRunPtr != nullptr) {
        textRuns.add(FFITextValueRun(wrappedTextRunPtr));
      }
    }

    _freeTextRunsArray(arrayPtr);
    return textRuns;
  }
}

class FFIBindableArtboard extends BindableArtboard
    implements RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_deleteBindableArtboardNative);

  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  /// Strong reference to avoid GC/finalization of the associated VMI while
  /// this bindable artboard is still in use.
  FFIRiveViewModelInstanceRuntime? _viewModelInstance;

  Pointer<Void> get viewModelInstancePointer =>
      _viewModelInstance?.pointer ?? nullptr;

  FFIBindableArtboard(
    this._pointer, {
    FFIRiveViewModelInstanceRuntime? viewModelInstance,
  }) : _viewModelInstance = viewModelInstance {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _viewModelInstance = null;
    _deleteBindableArtboard(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }
}

class FFIInternalViewModelInstanceValue<T>
    extends InternalViewModelInstanceValue<T>
    implements RiveFFIReference, Finalizable {
  void Function(T value)? _callback;
  static final _finalizer =
      NativeFinalizer(_deleteViewModelInstanceValueNative);

  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  FFIInternalViewModelInstanceValue(this._pointer) {
    _finalizer.attach(this, _pointer.cast(), detach: this);

    Pointer<Void> instancePointer = getInstancePointer();
    instancePointerAddress = instancePointer.address;
    if (instancePointer != nullptr) {
      FFIRiveFile.internalRegisterViewModelInstance(
          instancePointerAddress, this);
    }
  }

  @override
  void onChanged(void Function(T value) callback) {
    _callback = callback;
  }

  Pointer<Void> getInstancePointer() {
    return nullptr;
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _finalizer.detach(this);
    FFIRiveFile.internalUnregisterViewModelInstance(instancePointerAddress);
    _deleteViewModelInstanceValue(_pointer);
    _pointer = nullptr;
  }

  @override
  advanced() {
    _setViewModelInstanceAdvanced(pointer);
  }

  @override
  set value(T val) {
    if (suppressCallback) {
      return;
    }
    suppressCallback = true;
    applyValue(val);
    suppressCallback = false;
  }

  @override
  set nativeValue(T val) {
    if (suppressCallback) {
      return;
    }
    suppressCallback = true;
    if (_callback != null) {
      _callback!(val);
    }
    suppressCallback = false;
  }

  void applyValue(T val) {}
}

class FFIRiveInternalViewModelInstance extends InternalViewModelInstance
    implements Finalizable {
  static final _finalizer = NativeFinalizer(_deleteViewModelInstanceNative);

  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;
  FFIRiveInternalViewModelInstance(this._pointer);

  @override
  String uniqueId() {
    return _pointer.address.toString();
  }

  Pointer<Void> _propertyValuePointer(
      int index, String name, int propertyType) {
    final namePtr = name.toNativeUtf8();
    try {
      return _viewModelInstancePropertyValue(
          pointer, index, namePtr, propertyType);
    } finally {
      malloc.free(namePtr);
    }
  }

  @override
  InternalViewModelInstanceViewModel propertyViewModel(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIRiveInternalViewModelInstanceViewModel(propertyPointer);
  }

  @override
  InternalViewModelInstanceNumber propertyNumber(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceNumber(propertyPointer);
  }

  @override
  InternalViewModelInstanceTrigger propertyTrigger(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceTrigger(propertyPointer);
  }

  @override
  InternalViewModelInstanceBoolean propertyBoolean(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceBoolean(propertyPointer);
  }

  @override
  InternalViewModelInstanceColor propertyColor(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceColor(propertyPointer);
  }

  @override
  InternalViewModelInstanceString propertyString(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceString(propertyPointer);
  }

  @override
  InternalViewModelInstanceEnum propertyEnum(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceEnum(propertyPointer);
  }

  @override
  InternalViewModelInstanceList propertyList(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIRiveInternalViewModelInstanceList(propertyPointer);
  }

  @override
  InternalViewModelInstanceAsset propertyAsset(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceAsset(propertyPointer);
  }

  @override
  InternalViewModelInstanceSymbolListIndex propertySymbolListIndex(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceSymbolListIndex(propertyPointer);
  }

  @override
  InternalViewModelInstanceArtboard propertyArtboard(
      int index, String name, int propertyType) {
    final propertyPointer = _propertyValuePointer(index, name, propertyType);
    return FFIInternalViewModelInstanceArtboard(propertyPointer);
  }

  @override
  void pruneToProperties(List<int> keepPropertyIds) {
    if (_pointer == nullptr) {
      return;
    }
    final count = keepPropertyIds.length;
    final idsPtr = count == 0 ? nullptr : malloc<Uint32>(count);
    try {
      for (var i = 0; i < count; i++) {
        idsPtr[i] = keepPropertyIds[i];
      }
      _pruneViewModelInstanceToProperties(_pointer, idsPtr, count);
    } finally {
      if (count != 0) {
        malloc.free(idsPtr);
      }
    }
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _deleteViewModelInstance(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }
}

class FFIRiveInternalViewModelInstanceViewModel
    extends FFIInternalViewModelInstanceValue<InternalViewModelInstance?>
    implements RiveFFIReference, InternalViewModelInstanceViewModel {
  FFIRiveInternalViewModelInstanceViewModel(super.pointer);

  @override
  InternalViewModelInstance get referenceViewModelInstance {
    final viewModelInstancePointer =
        _viewModelInstanceReferenceViewModel(pointer);
    return FFIRiveInternalViewModelInstance(viewModelInstancePointer);
  }

  syncValue() {
    if (suppressCallback) {
      return;
    }
    if (_callback != null) {
      suppressCallback = true;
      _callback!(null);
      suppressCallback = false;
    }
  }

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceViewModelCallback(pointer);
  }

  @override
  void applyValue(InternalViewModelInstance? val) {
    if (val != null) {
      _setViewModelInstanceViewModelValue(
          pointer, (val as FFIRiveInternalViewModelInstance).pointer);
    }
  }
}

class FFIInternalViewModelInstanceNumber
    extends FFIInternalViewModelInstanceValue<double>
    implements RiveFFIReference, InternalViewModelInstanceNumber {
  FFIInternalViewModelInstanceNumber(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceNumberCallback(pointer);
  }

  @override
  void applyValue(double val) {
    _setViewModelInstanceNumberValue(pointer, val);
  }
}

class FFIInternalViewModelInstanceColor
    extends FFIInternalViewModelInstanceValue<int>
    implements RiveFFIReference, InternalViewModelInstanceColor {
  FFIInternalViewModelInstanceColor(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceColorCallback(pointer);
  }

  @override
  void applyValue(int val) {
    _setViewModelInstanceColorValue(pointer, val);
  }
}

class FFIInternalViewModelInstanceString
    extends FFIInternalViewModelInstanceValue<String>
    implements RiveFFIReference, InternalViewModelInstanceString {
  FFIInternalViewModelInstanceString(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceStringCallback(pointer);
  }

  @override
  void applyValue(String val) {
    var nativeString = val.toNativeUtf8();
    _setViewModelInstanceStringValue(pointer, nativeString.cast());
    malloc.free(nativeString);
  }
}

class FFIInternalViewModelInstanceBoolean
    extends FFIInternalViewModelInstanceValue<bool>
    implements RiveFFIReference, InternalViewModelInstanceBoolean {
  FFIInternalViewModelInstanceBoolean(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceBooleanCallback(pointer);
  }

  @override
  void applyValue(bool val) {
    _setViewModelInstanceBooleanValue(pointer, val);
  }
}

class FFIInternalViewModelInstanceTrigger
    extends FFIInternalViewModelInstanceValue<int>
    implements RiveFFIReference, InternalViewModelInstanceTrigger {
  FFIInternalViewModelInstanceTrigger(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceTriggerCallback(pointer);
  }

  @override
  void applyValue(int val) {
    _setViewModelInstanceTriggerValue(pointer, val);
  }
}

class FFIInternalViewModelInstanceEnum
    extends FFIInternalViewModelInstanceValue<int>
    implements RiveFFIReference, InternalViewModelInstanceEnum {
  FFIInternalViewModelInstanceEnum(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceEnumCallback(pointer);
  }

  @override
  void applyValue(int val) {
    _setViewModelInstanceEnumValue(pointer, val);
  }
}

class FFIRiveInternalViewModelInstanceList
    extends FFIInternalViewModelInstanceValue<List<InternalViewModelInstance>?>
    implements RiveFFIReference, InternalViewModelInstanceList {
  FFIRiveInternalViewModelInstanceList(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceListCallback(pointer);
  }

  @override
  InternalViewModelInstance referenceViewModelInstance(int index) {
    final viewModelInstancePointer =
        _viewModelInstanceListItemViewModel(pointer, index);
    return FFIRiveInternalViewModelInstance(viewModelInstancePointer);
  }

  @override
  int size() {
    final listSize = _viewModelInstanceListSize(pointer);
    return listSize;
  }

  @override
  void applyValue(List<InternalViewModelInstance>? val) {
    if (val == null || val.isEmpty) {
      _setViewModelInstanceListValue(
          pointer, Pointer<Pointer<Void>>.fromAddress(0), 0);
      return;
    }
    final count = val.length;
    _instanceListScratchBuffer.use(count, (ptr) {
      for (var i = 0; i < count; i++) {
        ptr[i] = (val[i] as FFIRiveInternalViewModelInstance).pointer;
      }
      _setViewModelInstanceListValue(pointer, ptr, count);
    });
  }

  syncValue() {
    if (suppressCallback) {
      return;
    }
    if (_callback != null) {
      suppressCallback = true;
      _callback!(null);
      suppressCallback = false;
    }
  }
}

class FFIInternalViewModelInstanceSymbolListIndex
    extends FFIInternalViewModelInstanceValue<int>
    implements RiveFFIReference, InternalViewModelInstanceSymbolListIndex {
  FFIInternalViewModelInstanceSymbolListIndex(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceSymbolListIndexCallback(pointer);
  }

  @override
  void applyValue(int val) {
    _setViewModelInstanceSymbolListIndexValue(pointer, val);
  }
}

class FFIRiveInternalDataContext extends InternalDataContext
    implements RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_deleteDataContextNative);
  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;
  FFIRiveInternalDataContext(this._pointer) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  InternalViewModelInstance get viewModelInstance {
    final viewModelInstancePointer = _riveDataContextViewModelInstance(pointer);
    return FFIRiveInternalViewModelInstance(viewModelInstancePointer);
  }

  @override
  InternalViewModelInstance? viewModelInstanceAt(int index) {
    final ptr = _dataContextViewModelInstanceAt(pointer, index);
    if (ptr == nullptr) return null;
    return FFIRiveInternalViewModelInstance(ptr);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _deleteDataContext(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }
}

class FFIInternalViewModelInstanceAsset
    extends FFIInternalViewModelInstanceValue<int>
    implements RiveFFIReference, InternalViewModelInstanceAsset {
  FFIInternalViewModelInstanceAsset(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceAssetCallback(pointer);
  }

  @override
  void applyValue(int val) {
    _setViewModelInstanceAssetValue(pointer, val);
  }
}

class FFIInternalViewModelInstanceArtboard
    extends FFIInternalViewModelInstanceValue<int>
    implements RiveFFIReference, InternalViewModelInstanceArtboard {
  FFIInternalViewModelInstanceArtboard(super.pointer);

  @override
  Pointer<Void> getInstancePointer() {
    return _setViewModelInstanceArtboardCallback(pointer);
  }

  @override
  void applyValue(int val) {
    _setViewModelInstanceArtboardValue(pointer, val);
  }
}

class FFIRiveInternalDataBind extends InternalDataBind
    implements RiveFFIReference {
  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;
  FFIRiveInternalDataBind(this._pointer);

  @override
  int get dirt => _riveDataBindDirt(pointer);

  @override
  set dirt(int value) => _riveDataBindSetDirt(pointer, value);

  @override
  int get flags => _riveDataBindFlags(pointer);

  @override
  void updateSourceBinding() {
    _riveDataBindUpdateSourceBinding(pointer);
  }

  @override
  void update(int dirt) {
    _riveDataBindUpdate(pointer, dirt);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _pointer = nullptr;
  }
}

class FFIComponent extends Component implements RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_deleteComponentNative);

  @override
  Pointer<Void> pointer;

  FFIComponent(this.pointer) {
    _finalizer.attach(this, pointer.cast(), detach: this);
  }

  @override
  void dispose() {
    if (pointer == nullptr) {
      return;
    }
    _deleteComponent(pointer);
    pointer = nullptr;
    _finalizer.detach(this);
  }

  @override
  Mat2D get worldTransform {
    _componentGetWorldTransform(pointer, _floatQueryBuffer);
    return Mat2D()
      ..values[0] = _floatQueryBuffer[0]
      ..values[1] = _floatQueryBuffer[1]
      ..values[2] = _floatQueryBuffer[2]
      ..values[3] = _floatQueryBuffer[3]
      ..values[4] = _floatQueryBuffer[4]
      ..values[5] = _floatQueryBuffer[5];
  }

  @override
  AABB get localBounds {
    _componentGetLocalBounds(pointer, _floatQueryBuffer);
    return AABB.fromValues(_floatQueryBuffer[0], _floatQueryBuffer[1],
        _floatQueryBuffer[2], _floatQueryBuffer[3]);
  }

  @override
  set worldTransform(Mat2D value) => _componentSetWorldTransform(
        pointer,
        value[0],
        value[1],
        value[2],
        value[3],
        value[4],
        value[5],
      );

  @override
  double get scaleX => _componentGetScaleX(pointer);

  @override
  set scaleX(double value) => _componentSetScaleX(pointer, value);

  @override
  double get scaleY => _componentGetScaleY(pointer);

  @override
  set rotation(double value) => _componentSetRotation(pointer, value);

  @override
  double get rotation => _componentGetRotation(pointer);

  @override
  set scaleY(double value) => _componentSetScaleY(pointer, value);

  @override
  double get x => _componentGetX(pointer);

  @override
  set x(double value) => _componentSetX(pointer, value);

  @override
  double get y => _componentGetY(pointer);

  @override
  set y(double value) => _componentSetY(pointer, value);

  @override
  void setLocalFromWorld(Mat2D worldTransform) => _componentSetLocalFromWorld(
        pointer,
        worldTransform[0],
        worldTransform[1],
        worldTransform[2],
        worldTransform[3],
        worldTransform[4],
        worldTransform[5],
      );
}

class FFITextValueRun extends TextValueRunRuntime implements Finalizable {
  static final _finalizer = NativeFinalizer(_deleteTextValueRunNative);

  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  FFITextValueRun(this._pointer) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  String get name => safeString(_textValueRunName(pointer));

  @override
  String get text => safeString(_textValueRunText(pointer));

  @override
  String get path => safeString(_textValueRunPath(pointer));

  @override
  set text(String value) {
    final nativeString = value.toNativeUtf8();
    _textValueRunSetText(pointer, nativeString.cast());
    malloc.free(nativeString);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _finalizer.detach(this);
    _deleteTextValueRun(_pointer);
    _pointer = nullptr;
  }
}

class FFIAnimation extends Animation implements RiveFFIReference, Finalizable {
  static final _finalizer = NativeFinalizer(_animationInstanceDeleteNative);

  @override
  Pointer<Void> get pointer => _pointer;
  Pointer<Void> _pointer;

  FFIAnimation(this._pointer) {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  String get name =>
      safeString(_animationInstanceName(pointer), deleteNative: true);

  @override
  double get time => _animationInstanceGetTime(pointer);

  @override
  set time(double value) => _animationInstanceSetTime(pointer, value);

  @override
  bool advance(double elapsedSeconds) =>
      _animationInstanceAdvance(pointer, elapsedSeconds);

  @override
  bool advanceAndApply(double elapsedSeconds) =>
      _animationInstanceAdvanceAndApply(pointer, elapsedSeconds);

  @override
  void apply({double mix = 1.0}) => _animationInstanceApply(pointer, mix);

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _animationInstanceDelete(_pointer);
    _pointer = nullptr;
    _finalizer.detach(this);
  }

  @override
  double get duration => _animationInstanceGetDuration(_pointer);

  @override
  double globalToLocalTime(double seconds) =>
      animationInstanceGetLocalSeconds(_pointer, seconds);
}

Future<File?> decodeRiveFile(
  Uint8List bytes,
  Factory riveFactory, {
  AssetLoaderCallback? assetLoader,
  LuauState? vm,
}) async {
  // let the factory know we're starting to decode.
  var pointer = malloc.allocate<Uint8>(bytes.length);
  for (int i = 0; i < bytes.length; i++) {
    pointer[i] = bytes[i];
  }

  Pointer<Void>? vmPointer;
  if (vm != null && vm is RiveFFIReference) {
    // Pass the ScriptingVM pointer - File::import now accepts ScriptingVM*.
    vmPointer = (vm as RiveFFIReference).pointer;
  }

  NativeCallable<_AssetLoaderCallbackNative>? nativeCallback;
  if (assetLoader != null) {
    nativeCallback = NativeCallable<_AssetLoaderCallbackNative>.isolateLocal(
      (
        Pointer<Void> fileAssetPointer,
        Pointer<Uint8> data,
        int size,
      ) {
        final assetType = _riveFileAssetCoreType(fileAssetPointer);

        FileAsset fileAsset = switch (assetType) {
          ImageAsset.coreType => FFIImageAsset(fileAssetPointer, riveFactory),
          FontAsset.coreType => FFIFontAsset(fileAssetPointer, riveFactory),
          AudioAsset.coreType => FFIAudioAsset(fileAssetPointer, riveFactory),
          _ => FFIUnknownAsset(fileAssetPointer, riveFactory),
        };

        final Uint8List? assetData =
            data != nullptr ? data.asTypedList(size) : null;

        return assetLoader(
          fileAsset,
          assetData,
        );
      },
      exceptionalReturn: false,
    );
  }

  // Pass the pointer in to a native method.
  var result = _loadRiveFile(
    pointer,
    bytes.length,
    (riveFactory as FFIFactory).pointer,
    nativeCallback?.nativeFunction ?? nullptr,
    vmPointer ?? nullptr,
  );
  malloc.free(pointer);
  await riveFactory.completedDecodingFile(result != nullptr);
  nativeCallback?.close();
  nativeCallback = null;
  if (result == nullptr) {
    return null;
  }

  return FFIRiveFile(result, riveFactory);
}

void batchAdvanceStateMachines(
    Iterable<StateMachine> stateMachines, double elapsedSeconds) {
  if (stateMachines.isEmpty) {
    return;
  }

  var mem = malloc
      .allocate<Pointer<Void>>(stateMachines.length * sizeOf<Pointer<Void>>());
  int index = 0;
  for (final machine in stateMachines) {
    mem[index++] = (machine as RiveFFIReference).pointer;
  }
  _batchAdvance(mem, stateMachines.length, elapsedSeconds);
  malloc.free(mem);
}

void batchAdvanceAndRenderStateMachines(Iterable<StateMachine> stateMachines,
    double elapsedSeconds, Renderer renderer) {
  if (stateMachines.isEmpty) {
    return;
  }

  var mem = malloc
      .allocate<Pointer<Void>>(stateMachines.length * sizeOf<Pointer<Void>>());
  int index = 0;
  for (final machine in stateMachines) {
    mem[index++] = (machine as RiveFFIReference).pointer;
  }
  _batchAdvanceAndRender(mem, stateMachines.length, elapsedSeconds,
      (renderer as RiveFFIReference).pointer);
  malloc.free(mem);
}

abstract class FFIFactory extends Factory {
  Pointer<Void> pointer;
  FFIFactory(this.pointer);

  @override
  int get nativePointerAddress => pointer.address;

  @override
  RenderPath makePath([bool initEmpty = false]) =>
      FFIRenderPath(this, initEmpty);

  @override
  RenderPaint makePaint() => FFIRenderPaint(this);

  @override
  IndexRenderBuffer? makeIndexBuffer(int elementCount) {
    if (elementCount <= 0) {
      return null;
    }
    return FFIIndexRenderBuffer(this, elementCount);
  }

  @override
  VertexRenderBuffer? makeVertexBuffer(int elementCount) {
    if (elementCount <= 0) {
      return null;
    }
    return FFIVertexRenderBuffer(this, elementCount);
  }

  @override
  Future<RenderImage?> decodeImage(Uint8List bytes) =>
      FFIRenderImage.decode(this, bytes);

  @override
  Future<Font?> decodeFont(Uint8List bytes) async => Font.decode(bytes);

  @override
  Future<AudioSource?> decodeAudio(Uint8List bytes) async =>
      AudioEngine.loadSource(bytes);

  @override
  RenderText makeText() => RenderTextFFI(_makeRawText(pointer));
}

Factory getRiveFactory() => FFIRiveFactory.instance;

Factory getFlutterFactory() => FFIFlutterFactory.instance;

// ============================================================================
// Profiler FFI bindings
// ============================================================================

final bool Function() _profilerStart = nativeLib
    .lookup<NativeFunction<Bool Function()>>('profilerStart')
    .asFunction();

final bool Function() _profilerStop = nativeLib
    .lookup<NativeFunction<Bool Function()>>('profilerStop')
    .asFunction();

final bool Function() _profilerIsActive = nativeLib
    .lookup<NativeFunction<Bool Function()>>('profilerIsActive')
    .asFunction();

final int Function() _profilerDump = nativeLib
    .lookup<NativeFunction<Size Function()>>('profilerDump')
    .asFunction();

final Pointer<Uint8> Function() _profilerGetBufferPtr = nativeLib
    .lookup<NativeFunction<Pointer<Uint8> Function()>>('profilerGetBufferPtr')
    .asFunction();

final int Function() _profilerGetBufferSize = nativeLib
    .lookup<NativeFunction<Size Function()>>('profilerGetBufferSize')
    .asFunction();

final void Function() _profilerFreeBuffer = nativeLib
    .lookup<NativeFunction<Void Function()>>('profilerFreeBuffer')
    .asFunction();

final void Function() _profilerEndFrame = nativeLib
    .lookup<NativeFunction<Void Function()>>('profilerEndFrame')
    .asFunction();

/// FFI implementation of [RiveProfiler].
class FFIRiveProfiler extends RiveProfiler {
  static FFIRiveProfiler? _instance;
  static FFIRiveProfiler get instance => _instance ??= FFIRiveProfiler._();
  FFIRiveProfiler._();

  @override
  bool start() => _profilerStart();

  @override
  bool stop() => _profilerStop();

  @override
  bool get isActive => _profilerIsActive();

  @override
  Uint8List? dump() {
    final size = _profilerDump();
    if (size == 0) return null;

    final ptr = _profilerGetBufferPtr();
    if (ptr == nullptr) return null;

    // Copy buffer then clear it on native side
    // First dump has HEADER, subsequent dumps have just FRAMES
    final data = Uint8List.fromList(ptr.asTypedList(size));
    _profilerFreeBuffer();
    return data;
  }

  @override
  void endFrame() => _profilerEndFrame();
}

/// Returns the FFI profiler instance.
RiveProfiler getRiveProfiler() => FFIRiveProfiler.instance;

Pointer<Uint8> _stringBytes = calloc.allocate(4096);
int _stringBytesSize = 4096;

Pointer<Utf8> toNativeString(String value) {
  final units = utf8.encode(value);
  if (_stringBytesSize < units.length + 1) {
    calloc.free(_stringBytes);
    _stringBytes = calloc.allocate(units.length + 1);
    _stringBytesSize = units.length + 1;
  }
  final nativeString = _stringBytes.asTypedList(units.length + 1);
  nativeString.setAll(0, units);
  nativeString[units.length] = 0;
  return _stringBytes.cast();
}
