import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:meta/meta.dart';
import 'package:rive_native/focus.dart' as focus;
import 'package:rive_native/rive_audio.dart';
import 'package:rive_native/semantics.dart';
import 'package:rive_native/rive_luau.dart';
import 'package:rive_native/rive_native.dart';
import 'package:rive_native/src/errors.dart';
import 'package:rive_native/src/rive.dart' show RiveProfiler;
import 'package:rive_native/src/rive_native_web.dart';
import 'package:rive_native/src/web/flutter_renderer_web.dart';
import 'package:rive_native/src/web/rive_audio_web.dart';
import 'package:rive_native/src/web/rive_luau_web.dart';
import 'package:rive_native/src/web/rive_renderer_web.dart';
import 'package:rive_native/src/web/rive_focus_web.dart';
import 'package:rive_native/src/web/rive_semantic_web.dart';
import 'package:rive_native/src/web/rive_text_web.dart';

/// JS interop binding to the global `BigInt` constructor. Required when
/// passing values to WASM exports compiled with `-s WASM_BIGINT`, where
/// `i64` parameters expect a `BigInt` rather than a `Number`.
@js.JS('BigInt')
external js.JSBigInt _jsBigInt(js.JSAny value);

/// Load a list of bytes from a file on the local filesystem at [path].
Future<Uint8List?> localFileBytes(String path) =>
    throw UnsupportedError('Cannot load from a local file on the web.');

/// Helper function to convert a JS object to a Dart list of [ViewModelProperty].
List<ViewModelProperty> _parseViewModelProperties(js.JSObject result) {
  final properties = <ViewModelProperty>[];

  final length = (result.getProperty('length'.toJS) as js.JSNumber).toDartInt;
  for (int i = 0; i < length; i++) {
    final jsProp = result.getProperty(i.toJS) as js.JSObject;

    final name = (jsProp.getProperty('name'.toJS) as js.JSString).toDart;
    final type = (jsProp.getProperty('type'.toJS) as js.JSNumber).toDartInt;

    properties.add(ViewModelProperty(name, DataType.values[type]));
  }
  return properties;
}

class _WebAssetLoaderCallable {
  final AssetLoaderCallback assetLoader;
  final Factory riveFactory;
  late bool Function(int, int, int) webLoader;

  _WebAssetLoaderCallable(this.assetLoader, this.riveFactory) {
    webLoader = (int assetPointer, int bytesPointer, int size) {
      final dartBytes =
          bytesPointer != 0 ? _wasmHeapUint8(bytesPointer, size) : null;
      final assetType = (RiveWasm.riveFileAssetCoreType
              .callAsFunction(null, assetPointer.toJS) as js.JSNumber)
          .toDartInt;

      FileAsset fileAsset = switch (assetType) {
        ImageAsset.coreType => WebImageAsset(assetPointer, riveFactory),
        FontAsset.coreType => WebFontAsset(assetPointer, riveFactory),
        AudioAsset.coreType => WebAudioAsset(assetPointer, riveFactory),
        _ => WebUnknownAsset(assetPointer, riveFactory)
      };

      return assetLoader(fileAsset, dartBytes);
    };
  }

  static Uint8List _wasmHeapUint8(int ptr, int length) =>
      RiveWasm.heap(ptr, length);
}

Future<File?> decodeRiveFile(
  Uint8List bytes,
  Factory riveFactory, {
  AssetLoaderCallback? assetLoader,
  LuauState? vm,
}) async {
  final wasmBuffer = WasmBuffer.fromBytes(bytes);
  _WebAssetLoaderCallable? assetLoaderCallable = assetLoader != null
      ? _WebAssetLoaderCallable(assetLoader, riveFactory)
      : null;

  int? vmPointer;
  if (vm != null && vm is LuauStateWasm) {
    vmPointer = vm.vmPtr;
  }

  final result = (RiveWasm.loadRiveFile.callAsFunction(
    null,
    wasmBuffer.pointer,
    wasmBuffer.data.length.toJS,
    (riveFactory as WebFactory).pointer,
    (assetLoaderCallable != null) ? assetLoaderCallable.webLoader.toJS : null,
    (vmPointer != null) ? vmPointer.toJS : 0.toJS,
  ) as js.JSNumber)
      .toDartInt;
  wasmBuffer.dispose();
  await riveFactory.completedDecodingFile(result != 0);
  assetLoaderCallable = null;
  if (result == 0) {
    return null;
  }
  return WebRiveFile(result, riveFactory);
}

void batchAdvanceStateMachines(
    Iterable<StateMachine> stateMachines, double elapsedSeconds) {}

void batchAdvanceAndRenderStateMachines(Iterable<StateMachine> stateMachines,
    double elapsedSeconds, Renderer renderer) {}

abstract class WebFactory extends Factory {
  js.JSAny pointer;
  WebFactory(this.pointer);

  @override
  int get nativePointerAddress => (pointer as js.JSNumber).toDartInt;

  @override
  RenderPath makePath([bool initEmpty = false]) =>
      WebRenderPath(this, initEmpty);

  @override
  RenderPaint makePaint() => WebRenderPaint(this);

  @override
  RenderText makeText() => WebRenderText(this);

  @override
  IndexRenderBuffer? makeIndexBuffer(int elementCount) {
    if (elementCount <= 0) {
      return null;
    }
    return WebIndexRenderBuffer(this, elementCount);
  }

  @override
  VertexRenderBuffer? makeVertexBuffer(int elementCount) {
    if (elementCount <= 0) {
      return null;
    }
    return WebVertexRenderBuffer(this, elementCount);
  }

  @override
  Future<RenderImage?> decodeImage(Uint8List bytes) async {
    var imagePointer = RiveWasm.decodeImage
        .callAsFunction(null, pointer, bytes.toJS) as js.JSAny;
    return WebRenderImage(imagePointer);
  }

  @override
  Future<Font?> decodeFont(Uint8List bytes) async => Font.decode(bytes);

  @override
  Future<AudioSource?> decodeAudio(Uint8List bytes) async =>
      AudioEngine.loadSource(bytes);
}

Factory getRiveFactory() => WebRiveFactory.instance;

Factory getFlutterFactory() => WebFlutterFactory.instance;

int toPointer(js.JSAny? any) => (any as js.JSNumber).toDartInt;

sealed class WebFileAsset implements FileAssetInterface {
  static final _finalizer = Finalizer((js.JSAny pointer) =>
      RiveWasm.deleteFileAsset.callAsFunction(null, pointer));

  int _pointer;
  final Factory _riveFactory;
  int get pointer => _pointer;

  WebFileAsset(this._pointer, this._riveFactory) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  int get assetId =>
      (RiveWasm.riveFileAssetId.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  String get cdnBaseUrl => RiveWasm.toDartString(
      (RiveWasm.riveFileAssetCdnBaseUrl.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt);

  @override
  String get cdnUuid => RiveWasm.toDartString(
      (RiveWasm.riveFileAssetCdnUuid.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt,
      deleteNative: true);

  @override
  String get fileExtension => RiveWasm.toDartString(
      (RiveWasm.riveFileAssetFileExtension.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt,
      deleteNative: true);

  @override
  String get name => RiveWasm.toDartString((RiveWasm.riveFileAssetName
          .callAsFunction(null, pointer.toJS) as js.JSNumber)
      .toDartInt);

  @override
  Factory get riveFactory => _riveFactory;

  @override
  void dispose() {
    if (pointer == 0) {
      return;
    }
    _finalizer.detach(this);
    RiveWasm.deleteFileAsset.callAsFunction(null, pointer.toJS);
    _pointer = 0;
  }
}

class WebImageAsset extends WebFileAsset implements ImageAsset {
  WebImageAsset(super.pointer, super._riveFactory);

  @override
  double get width =>
      (RiveWasm.imageAssetGetWidth.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  double get height =>
      (RiveWasm.imageAssetGetHeight.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  bool renderImage(RenderImage renderImage) =>
      _wasmBool(RiveWasm.riveFileAssetSetRenderImage.callAsFunction(
        null,
        pointer.toJS,
        (renderImage as WebRenderImage).pointer,
      ));

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

class WebFontAsset extends WebFileAsset implements FontAsset {
  WebFontAsset(super.pointer, super._riveFactory);

  @override
  bool font(Font font) =>
      _wasmBool(RiveWasm.riveFileAssetSetFont.callAsFunction(
        null,
        pointer.toJS,
        (font as FontWasm).fontPtr.toJS,
      ));

  @override
  Future<bool> decode(Uint8List bytes) async {
    final decodedFont = await riveFactory.decodeFont(bytes);
    if (decodedFont == null) {
      return false;
    }
    final result = font(decodedFont);
    decodedFont.dispose();
    return result;
  }
}

class WebAudioAsset extends WebFileAsset implements AudioAsset {
  WebAudioAsset(super.pointer, super._riveFactory);

  @override
  bool audio(AudioSource audioSource) =>
      _wasmBool(RiveWasm.riveFileAssetSetAudioSource.callAsFunction(
        null,
        pointer.toJS,
        (audioSource as AudioSourceWasm).nativePtr.toJS,
      ));

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

class WebUnknownAsset extends WebFileAsset implements UnknownAsset {
  WebUnknownAsset(super.pointer, super._riveFactory);

  @override
  Future<bool> decode(Uint8List bytes) async {
    return false; // nothing to decode
  }
}

class WebRiveFile extends File {
  final Factory riveFactory;
  static final _finalizer = Finalizer((js.JSAny pointer) =>
      RiveWasm.deleteRiveFile.callAsFunction(null, pointer));
  int _pointer;

  int get pointer => _pointer;

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
    if (vmi is WebInternalViewModelInstanceNumber) {
      vmi.nativeValue = value;
    }
  }

  static void _vmBooleanCallback(int ptr, bool value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceBoolean) {
      vmi.nativeValue = value;
    }
  }

  static void _vmColorCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceColor) {
      vmi.nativeValue = value;
    }
  }

  static void _vmStringCallback(int ptr, String value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceString) {
      vmi.nativeValue = value;
    }
  }

  static void _vmTriggerCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceTrigger) {
      vmi.nativeValue = value;
    }
  }

  static void _vmEnumCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceEnum) {
      vmi.nativeValue = value;
    }
  }

  static void _vmSymbolListIndexCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceSymbolListIndex) {
      vmi.nativeValue = value;
    }
  }

  static void _vmAssetCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceAsset) {
      vmi.nativeValue = value;
    }
  }

  static void _vmArtboardCallback(int ptr, int value) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceAsset) {
      vmi.nativeValue = value;
    }
  }

  static void _vmListCallback(int ptr) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebInternalViewModelInstanceList) {
      vmi.syncValue();
    }
  }

  static void _vmViewModelCallback(int ptr) {
    InternalViewModelInstanceValue? vmi = _instances[ptr];
    if (vmi is WebRiveInternalViewModelInstanceViewModel) {
      vmi.syncValue();
    }
  }

  @override
  Uint8List? requestSerializedViewModelInstance(
      InternalViewModelInstance instance) {
    if (instance is! WebRiveInternalViewModelInstance) {
      return null;
    }
    final fn = RiveWasm.requestSerializedViewModelInstance;
    if (fn == null) {
      return null;
    }
    final result =
        fn.callAsFunction(null, _pointer.toJS, instance.pointer.toJS);
    if (result == null) {
      return null;
    }
    final bytes =
        Uint8List.fromList(((result as js.JSArray).toDart as List).cast<int>());
    return bytes;
  }

  @override
  void setScriptingState(covariant LuauStateWasm vm) {
    RiveWasm.riveFileSetScriptingVM
        ?.callAsFunction(null, _pointer.toJS, vm.vmPtr.toJS);
  }

  @override
  void clearViewModelInstances() {
    RiveWasm.clearRuntimeViewModelInstances.callAsFunction(null, _pointer.toJS);
  }

  static const int _uint32Max = 4294967295;

  @override
  int? resolveViewModelInstanceAssetImageRuntimeIndex(int coreAddress) {
    if (_pointer == 0 || coreAddress == 0) {
      return null;
    }
    final r = (RiveWasm.viewModelInstanceAssetImageResolveRuntimeIndex
                .callAsFunction(null, _pointer.toJS, coreAddress.toJS)
            as js.JSNumber)
        .toDartInt;
    if (r < 0 || r == _uint32Max) {
      return null;
    }
    return r;
  }

  @override
  int? resolveViewModelInstanceAssetFontRuntimeIndex(int coreAddress) {
    if (_pointer == 0 || coreAddress == 0) {
      return null;
    }
    final r = (RiveWasm.viewModelInstanceAssetFontResolveRuntimeIndex
                .callAsFunction(null, _pointer.toJS, coreAddress.toJS)
            as js.JSNumber)
        .toDartInt;
    if (r < 0 || r == _uint32Max) {
      return null;
    }
    return r;
  }

  WebRiveFile(this._pointer, this.riveFactory) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
    RiveWasm.initBindingCallbacks.callAsFunctionEx(
      null,
      _vmNumberCallback.toJS,
      _vmBooleanCallback.toJS,
      _vmColorCallback.toJS,
      _vmStringCallback.toJS,
      _vmTriggerCallback.toJS,
      _vmEnumCallback.toJS,
      _vmSymbolListIndexCallback.toJS,
      _vmAssetCallback.toJS,
      _vmArtboardCallback.toJS,
      _vmListCallback.toJS,
      _vmViewModelCallback.toJS,
    );
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    _finalizer.detach(this);
    RiveWasm.deleteRiveFile.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
  }

  @override
  Artboard? artboard(String name, {bool frameOrigin = true}) =>
      RiveWasm.toNativeString(name, (namePointer) {
        final ptr = toPointer(RiveWasm.riveFileArtboardNamed.callAsFunction(
            null, _pointer.toJS, namePointer, _boolWasm(frameOrigin)));
        if (ptr == 0) {
          return null;
        }
        return WebRiveArtboard(ptr, riveFactory);
      });

  @override
  Artboard? artboardAt(int index, {bool frameOrigin = true}) {
    var ptr = toPointer(RiveWasm.riveFileArtboardByIndex.callAsFunction(
        null, _pointer.toJS, index.toJS, _boolWasm(frameOrigin)));
    if (ptr == 0) {
      return null;
    }
    return WebRiveArtboard(ptr, riveFactory);
  }

  @override
  Artboard? defaultArtboard({bool frameOrigin = true}) {
    var ptr = toPointer(RiveWasm.riveFileArtboardDefault
        .callAsFunction(null, _pointer.toJS, _boolWasm(frameOrigin)));
    if (ptr == 0) {
      return null;
    }
    return WebRiveArtboard(ptr, riveFactory);
  }

  @override
  BindableArtboard? artboardToBind(
    String name, {
    ViewModelInstance? viewModelInstance,
  }) =>
      RiveWasm.toNativeString(name, (namePointer) {
        final ptr = toPointer(RiveWasm.riveFileArtboardToBindNamed
            .callAsFunction(null, _pointer.toJS, namePointer));
        if (ptr == 0) {
          return null;
        }
        final webViewModelInstance =
            viewModelInstance is WebViewModelInstanceRuntime
                ? viewModelInstance
                : null;
        return WebBindableArtboard(
          ptr,
          viewModelInstance: webViewModelInstance,
        );
      });

  @override
  InternalDataContext? internalDataContext(
      int viewModelIndex, int instanceIndex) {
    var ptr = toPointer(RiveWasm.riveDataContext.callAsFunction(
        null, _pointer.toJS, viewModelIndex.toJS, instanceIndex.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebRiveDataContext(ptr);
  }

  @override
  InternalDataContext? internalDataContextFromInstances(
      List<int> viewModelIndices, List<int> instanceIndices) {
    assert(viewModelIndices.length == instanceIndices.length);
    final count = viewModelIndices.length;
    if (count == 0) return null;
    const int u32Size = 4;
    final vmBuf = (RiveWasm.allocateBuffer
            .callAsFunction(null, (count * u32Size).toJS) as js.JSNumber)
        .toDartInt;
    final instBuf = (RiveWasm.allocateBuffer
            .callAsFunction(null, (count * u32Size).toJS) as js.JSNumber)
        .toDartInt;
    final vmView = RiveWasm.heapViewU32(vmBuf, count);
    final instView = RiveWasm.heapViewU32(instBuf, count);
    for (var i = 0; i < count; i++) {
      vmView[i] = viewModelIndices[i];
      instView[i] = instanceIndices[i];
    }
    final ptr = toPointer(RiveWasm.riveDataContextFromInstances
        .callAsFunction(null, _pointer.toJS, vmBuf.toJS, instBuf.toJS,
            count.toJS));
    RiveWasm.deleteBuffer.callAsFunction(null, vmBuf.toJS);
    RiveWasm.deleteBuffer.callAsFunction(null, instBuf.toJS);
    if (ptr == 0) return null;
    return WebRiveDataContext(ptr);
  }

  @override
  InternalDataContext? internalDataContextFromNativeInstances(
      List<InternalViewModelInstance> instances,
      {InternalDataContext? parent}) {
    if (instances.isEmpty) return null;
    final count = instances.length;
    const int ptrSize = 4; // WASM 32-bit pointers
    final buf = (RiveWasm.allocateBuffer
            .callAsFunction(null, (count * ptrSize).toJS) as js.JSNumber)
        .toDartInt;
    final view = RiveWasm.heapViewU32(buf, count);
    for (var i = 0; i < count; i++) {
      view[i] = (instances[i] as WebRiveInternalViewModelInstance).pointer;
    }
    final parentPtr = parent != null
        ? (parent as WebRiveDataContext).pointer
        : 0;
    final ptr = toPointer(
        RiveWasm.dataContextFromViewModelInstancePointers
            .callAsFunction(null, buf.toJS, count.toJS, parentPtr.toJS));
    RiveWasm.deleteBuffer.callAsFunction(null, buf.toJS);
    if (ptr == 0) return null;
    return WebRiveDataContext(ptr);
  }

  @override
  InternalViewModelInstance? copyViewModelInstance(
      int viewModelIndex, int instanceIndex) {
    var ptr = toPointer(RiveWasm.copyViewModelInstance.callAsFunction(
        null, _pointer.toJS, viewModelIndex.toJS, instanceIndex.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebRiveInternalViewModelInstance(ptr);
  }

  @override
  int get viewModelCount =>
      (RiveWasm.riveFileViewModelCount.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  ViewModel? viewModelByIndex(int index) {
    var ptr = toPointer(RiveWasm.riveFileViewModelRuntimeByIndex
        .callAsFunction(null, _pointer.toJS, index.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebViewModelRuntime(ptr);
  }

  @override
  ViewModel? viewModelByName(String name) => RiveWasm.toNativeString(
        name,
        (namePointer) {
          final ptr = toPointer(RiveWasm.riveFileViewModelRuntimeByName
              .callAsFunction(null, _pointer.toJS, namePointer));
          if (ptr == 0) {
            return null;
          }
          return WebViewModelRuntime(ptr);
        },
      );

  @override
  ViewModel? defaultArtboardViewModel(Artboard artboard) {
    var ptr = toPointer(RiveWasm.riveFileDefaultArtboardViewModelRuntime
        .callAsFunction(
            null, _pointer.toJS, (artboard as WebRiveArtboard).pointer.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebViewModelRuntime(ptr);
  }

  @override
  List<DataEnum> get enums {
    final result =
        RiveWasm.fileEnums.callAsFunction(null, _pointer.toJS) as js.JSObject;
    final dataEnums = <DataEnum>[];
    final length = (result.getProperty('length'.toJS) as js.JSNumber).toDartInt;
    for (int i = 0; i < length; i++) {
      final jsProp = result.getProperty(i.toJS) as js.JSObject;
      final name = (jsProp.getProperty('name'.toJS) as js.JSString).toDart;
      final values = (jsProp.getProperty('values'.toJS) as js.JSArray)
          .toDart
          .cast<String>();
      dataEnums.add(DataEnum(name, values));
    }
    return dataEnums;
  }

  @override
  void advanceFrameId() {
    RiveWasm.riveAdvanceFrameId.callAsFunction(null);
  }
}

class WebViewModelRuntime implements ViewModel {
  int get pointer => _pointer;
  int _pointer;

  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteViewModelRuntime.callAsFunction(null, pointer),
  );

  WebViewModelRuntime(this._pointer) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  int get propertyCount => (RiveWasm.viewModelRuntimePropertyCount
          .callAsFunction(null, _pointer.toJS) as js.JSNumber)
      .toDartInt;

  @override
  int get instanceCount => (RiveWasm.viewModelRuntimeInstanceCount
          .callAsFunction(null, _pointer.toJS) as js.JSNumber)
      .toDartInt;

  @override
  String get name {
    final stringPointer = (RiveWasm.viewModelRuntimeName
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  List<ViewModelProperty> get properties {
    final result = RiveWasm.viewModelRuntimeProperties
        .callAsFunction(null, pointer.toJS) as js.JSObject;
    return _parseViewModelProperties(result);
  }

  @override
  ViewModelInstance? createInstanceByIndex(int index) {
    final ptr = toPointer(RiveWasm.createVMIRuntimeFromIndex
        .callAsFunction(null, _pointer.toJS, index.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceRuntime(ptr);
  }

  @override
  ViewModelInstance? createInstanceByName(String name) =>
      RiveWasm.toNativeString(
        name,
        (namePointer) {
          var ptr = toPointer(RiveWasm.createVMIRuntimeFromName
              .callAsFunction(null, _pointer.toJS, namePointer));

          if (ptr == 0) {
            return null;
          }
          return WebViewModelInstanceRuntime(ptr);
        },
      );

  @override
  ViewModelInstance? createDefaultInstance() {
    var ptr = toPointer(
        RiveWasm.createDefaultVMIRuntime.callAsFunction(null, _pointer.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceRuntime(ptr);
  }

  @override
  ViewModelInstance? createInstance() {
    var ptr = toPointer(
        RiveWasm.createVMIRuntime.callAsFunction(null, _pointer.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceRuntime(ptr);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    var pointer = _pointer;
    _pointer = 0;
    _finalizer.detach(this);
    RiveWasm.deleteViewModelRuntime.callAsFunction(null, pointer.toJS);
  }
}

class WebViewModelInstanceRuntime
    with ViewModelInstanceCallbackMixin, AdvanceRequestMixin
    implements ViewModelInstance {
  int get pointer => _pointer;
  int _pointer;

  late WebViewModelInstanceRuntime _rootViewModelInstance;

  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteVMIRuntime.callAsFunction(null, pointer),
  );

  WebViewModelInstanceRuntime(
    this._pointer, {
    WebViewModelInstanceRuntime? rootViewModelInstance,
  }) {
    _finalizer.attach(this, _pointer.toJS, detach: this);

    if (rootViewModelInstance == null) {
      _rootViewModelInstance = this;
    } else {
      _rootViewModelInstance = rootViewModelInstance;
    }
  }

  int _findPointerByPath(String path, js.JSFunction function) =>
      RiveWasm.toNativeString(
        path,
        (pathPointer) {
          final ptr = toPointer(
              function.callAsFunction(null, _pointer.toJS, pathPointer));

          return ptr;
        },
      );

  @override
  String get name {
    final stringPointer = (RiveWasm.vmiRuntimeName
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  List<ViewModelProperty> get properties {
    final result = RiveWasm.vmiRuntimeProperties
        .callAsFunction(null, pointer.toJS) as js.JSObject;
    return _parseViewModelProperties(result);
  }

  @override
  ViewModelInstanceNumber? number(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetNumberProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceNumberRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceString? string(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetStringProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceStringRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceBoolean? boolean(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetBooleanProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceBooleanRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceColor? color(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetColorProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceColorRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceEnum? enumerator(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetEnumProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceEnumRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceTrigger? trigger(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetTriggerProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceTriggerRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceAssetImage? image(String path) {
    var ptr =
        _findPointerByPath(path, RiveWasm.vmiRuntimeGetAssetImageProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceAssetImageRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceAssetFont? font(String path) {
    var ptr =
        _findPointerByPath(path, RiveWasm.vmiRuntimeGetAssetFontProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceAssetFontRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstance? viewModel(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetViewModelProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceRuntime(
      ptr,
      rootViewModelInstance: _rootViewModelInstance,
    );
  }

  @override
  ViewModelInstanceList? list(String path) {
    var ptr = _findPointerByPath(path, RiveWasm.vmiRuntimeGetListProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceListRuntime(ptr, _rootViewModelInstance);
  }

  @override
  ViewModelInstanceArtboard? artboard(String path) {
    final ptr =
        _findPointerByPath(path, RiveWasm.vmiRuntimeGetArtboardProperty);
    if (ptr == 0) {
      return null;
    }
    return WebViewModelInstanceArtboardRuntime(ptr, _rootViewModelInstance);
  }

  @override
  void dispose() {
    clearCallbacks();
    removeAllAdvanceRequestListeners();

    if (_pointer == 0) {
      return;
    }
    var pointer = _pointer;
    _pointer = 0;
    _finalizer.detach(this);
    RiveWasm.deleteVMIRuntime.callAsFunction(null, pointer.toJS);
  }

  @override
  bool get isDisposed => _pointer == 0;
}

abstract class WebViewModelInstanceValueRuntime
    implements ViewModelInstanceValue {
  int get pointer => _pointer;
  int _pointer;

  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteVMIValueRuntime.callAsFunction(null, pointer),
  );

  final ViewModelInstance _rootViewModelInstance;

  @override
  ViewModelInstance get rootViewModelInstance => _rootViewModelInstance;

  WebViewModelInstanceValueRuntime(this._pointer, this._rootViewModelInstance) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    var pointer = _pointer;
    _pointer = 0;
    _finalizer.detach(this);
    RiveWasm.deleteVMIValueRuntime.callAsFunction(null, pointer.toJS);
  }
}

abstract class WebViewModelInstanceObservableValueRuntime<T>
    extends WebViewModelInstanceValueRuntime
    with ViewModelInstanceObservableValueMixin<T> {
  WebViewModelInstanceObservableValueRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  bool get hasChanged => _wasmBool(
      RiveWasm.vmiValueRuntimeHasChanged.callAsFunction(null, pointer.toJS));

  @override
  void clearChanges() =>
      RiveWasm.vmiValueRuntimeClearChanges.callAsFunction(null, pointer.toJS);

  @override
  void dispose() {
    clearListeners();
    super.dispose();
  }
}

class WebViewModelInstanceNumberRuntime
    extends WebViewModelInstanceObservableValueRuntime<double>
    implements ViewModelInstanceNumber {
  WebViewModelInstanceNumberRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  double get nativeValue =>
      (RiveWasm.getVMINumberRuntimeValue.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set nativeValue(double value) => RiveWasm.setVMINumberRuntimeValue
      .callAsFunction(null, pointer.toJS, value.toJS);
}

class WebViewModelInstanceStringRuntime
    extends WebViewModelInstanceObservableValueRuntime<String>
    implements ViewModelInstanceString {
  WebViewModelInstanceStringRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  String get nativeValue {
    var stringPointer = (RiveWasm.getVMIStringRuntimeValue
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  set nativeValue(String value) => RiveWasm.toNativeString(
        value,
        (valuePointer) {
          RiveWasm.setVMIStringRuntimeValue
              .callAsFunction(null, _pointer.toJS, valuePointer);
        },
      );
}

class WebViewModelInstanceBooleanRuntime
    extends WebViewModelInstanceObservableValueRuntime<bool>
    implements ViewModelInstanceBoolean {
  WebViewModelInstanceBooleanRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  bool get nativeValue => _wasmBool(
      RiveWasm.getVMIBooleanRuntimeValue.callAsFunction(null, pointer.toJS));

  @override
  set nativeValue(bool value) => RiveWasm.setVMIBooleanRuntimeValue
      .callAsFunction(null, pointer.toJS, value.toJS);
}

class WebViewModelInstanceColorRuntime
    extends WebViewModelInstanceObservableValueRuntime<Color>
    implements ViewModelInstanceColor {
  WebViewModelInstanceColorRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  Color get nativeValue {
    final color = (RiveWasm.getVMIColorRuntimeValue
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    return Color(color);
  }

  @override
  set nativeValue(Color value) => RiveWasm.setVMIColorRuntimeValue
      // ignore: deprecated_member_use
      .callAsFunction(null, pointer.toJS, value.value.toJS);
}

class WebViewModelInstanceEnumRuntime
    extends WebViewModelInstanceObservableValueRuntime<String>
    implements ViewModelInstanceEnum {
  WebViewModelInstanceEnumRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  String get nativeValue => RiveWasm.toDartString(
      (RiveWasm.getVMIEnumRuntimeValue.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt,
      deleteNative: true);

  @override
  set nativeValue(String value) => RiveWasm.toNativeString(
        value,
        (valuePointer) {
          RiveWasm.setVMIEnumRuntimeValue
              .callAsFunction(null, _pointer.toJS, valuePointer);
        },
      );

  @override
  String get enumType => RiveWasm.toDartString(
      (RiveWasm.getVMIEnumRuntimeEnumType.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt,
      deleteNative: true);
}

class WebViewModelInstanceTriggerRuntime
    extends WebViewModelInstanceObservableValueRuntime<bool>
    implements ViewModelInstanceTrigger {
  WebViewModelInstanceTriggerRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  void trigger() {
    _rootViewModelInstance.requestAdvance();
    RiveWasm.triggerVMITriggerRuntime.callAsFunction(null, pointer.toJS);
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

class WebViewModelInstanceAssetImageRuntime
    extends WebViewModelInstanceValueRuntime
    implements ViewModelInstanceAssetImage {
  WebViewModelInstanceAssetImageRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  set value(covariant WebRenderImage? value) {
    _rootViewModelInstance.requestAdvance();
    RiveWasm.setVMIAssetImageRuntimeValue.callAsFunction(
      null,
      _pointer.toJS,
      value?.pointer ?? 0.toJS,
    );
  }
}

class WebViewModelInstanceAssetFontRuntime
    extends WebViewModelInstanceValueRuntime
    implements ViewModelInstanceAssetFont {
  WebViewModelInstanceAssetFontRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  set value(covariant FontWasm? value) {
    _rootViewModelInstance.requestAdvance();
    RiveWasm.setVMIAssetFontRuntimeValue.callAsFunction(
      null,
      _pointer.toJS,
      value?.fontPtr.toJS ?? 0.toJS,
    );
  }
}

class WebViewModelInstanceArtboardRuntime
    extends WebViewModelInstanceValueRuntime
    implements ViewModelInstanceArtboard {
  WebViewModelInstanceArtboardRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  set value(covariant WebBindableArtboard value) {
    _rootViewModelInstance.requestAdvance();
    RiveWasm.setVMIArtboardRuntimeValue.callAsFunction(
      null,
      _pointer.toJS,
      value.pointer.toJS,
      value.viewModelInstancePointer.toJS,
    );
  }
}

class WebViewModelInstanceListRuntime extends WebViewModelInstanceValueRuntime
    implements ViewModelInstanceList {
  WebViewModelInstanceListRuntime(
    super._pointer,
    super._rootViewModelInstance,
  );

  @override
  int get length =>
      (RiveWasm.getVMIListRuntimeSize.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  void add(covariant WebViewModelInstanceRuntime instance) {
    _rootViewModelInstance.requestAdvance();
    RiveWasm.vmiListRuntimeAddInstance
        .callAsFunction(null, _pointer.toJS, instance.pointer.toJS);
  }

  @override
  void remove(covariant WebViewModelInstanceRuntime instance) {
    _rootViewModelInstance.requestAdvance();
    RiveWasm.vmiListRuntimeRemoveInstance
        .callAsFunction(null, _pointer.toJS, instance.pointer.toJS);
  }

  @override
  bool insert(int index, covariant WebViewModelInstanceRuntime instance) {
    RangeError.checkNotNegative(index, "index");
    if (index >= length) {
      throw RangeError.range(index, 0, length - 1, "index");
    }
    _rootViewModelInstance.requestAdvance();
    return _wasmBool(RiveWasm.vmiListRuntimeAddInstanceAt.callAsFunction(
      null,
      _pointer.toJS,
      instance.pointer.toJS,
      index.toJS,
    ));
  }

  @override
  void removeAt(int index) {
    RangeError.checkNotNegative(index, "index");
    if (index >= length) {
      throw RangeError.range(index, 0, length - 1, "index");
    }
    _rootViewModelInstance.requestAdvance();
    RiveWasm.vmiListRuntimeRemoveInstanceAt
        .callAsFunction(null, _pointer.toJS, index.toJS);
  }

  @override
  ViewModelInstance instanceAt(int index) {
    RangeError.checkNotNegative(index, "index");
    if (index >= length) {
      throw RangeError.range(index, 0, length - 1, "index");
    }
    var ptr = (RiveWasm.vmiListRuntimeInstanceAt
            .callAsFunction(null, _pointer.toJS, index.toJS) as js.JSNumber)
        .toDartInt;
    if (ptr == 0) {
      throw RiveError.nullNativePointer();
    }
    return WebViewModelInstanceRuntime(ptr,
        rootViewModelInstance:
            _rootViewModelInstance as WebViewModelInstanceRuntime);
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
    RiveWasm.vmiListRuntimeSwap
        .callAsFunction(null, _pointer.toJS, a.toJS, b.toJS);
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
    covariant WebViewModelInstanceRuntime value,
  ) =>
      insert(index, value);
}

class WebRiveArtboard extends Artboard {
  @override
  final Factory riveFactory;

  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteArtboardInstance.callAsFunction(null, pointer),
  );

  int get pointer => _pointer;
  int _pointer;

  @override
  int? get nativePointerAddress => _pointer;

  @override
  int? get artboardUniqueId =>
      (RiveWasm.artboardGetInnerPointer.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  WebRiveArtboard(this._pointer, this.riveFactory) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  String get name => RiveWasm.toDartString(
        (RiveWasm.artboardName.callAsFunction(null, pointer.toJS)
                as js.JSNumber)
            .toDartInt,
        deleteNative: true,
      );

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    var pointer = _pointer;
    _pointer = 0;
    _finalizer.detach(this);
    RiveWasm.deleteArtboardInstance.callAsFunction(null, pointer.toJS);
  }

  @override
  void drawCanvases() {
    RiveWasm.artboardDrawCanvases.callAsFunction(null, pointer.toJS);
  }

  @override
  LuauState? get drawCanvasState {
    final statePtr = toPointer(RiveWasm.artboardGetDrawCanvasLuauState
        .callAsFunction(null, pointer.toJS));
    if (statePtr == 0) return null;
    return LuauStateWasm.fromNativePointer(statePtr);
  }

  @override
  void draw(covariant WebRiveRenderer renderer) {
    assert(riveFactory.isValidRenderer(renderer));
    RiveWasm.artboardDraw
        .callAsFunction(null, pointer.toJS, renderer.jsRendererPtr);
  }

  @override
  void drawInternal(covariant WebRiveRenderer renderer) {
    assert(riveFactory.isValidRenderer(renderer));
    RiveWasm.artboardDrawInternal
        .callAsFunction(null, pointer.toJS, renderer.jsRendererPtr);
  }

  @override
  void advanceFrameId() {
    RiveWasm.riveAdvanceFrameId.callAsFunction(null);
  }

  @override
  void reset() {
    RiveWasm.artboardReset.callAsFunction(null, pointer.toJS);
  }

  @override
  StateMachine? defaultStateMachine() {
    var smiPointer = toPointer(RiveWasm.riveArtboardStateMachineDefault
        .callAsFunction(null, _pointer.toJS));
    if (smiPointer == 0) {
      return null;
    }
    return WebStateMachine(smiPointer);
  }

  @override
  StateMachine? stateMachine(String name) => RiveWasm.toNativeString(
        name,
        (namePointer) {
          final smiPointer = toPointer(RiveWasm.riveArtboardStateMachineNamed
              .callAsFunction(null, pointer.toJS, namePointer));

          if (smiPointer == 0) {
            return null;
          }
          return WebStateMachine(smiPointer);
        },
      );

  @override
  StateMachine? stateMachineAt(int index) =>
      WebStateMachine((RiveWasm.riveArtboardStateMachineAt
              .callAsFunction(null, pointer.toJS, index.toJS) as js.JSNumber)
          .toDartInt);

  @override
  AABB get bounds {
    RiveWasm.artboardBounds
        .callAsFunction(null, pointer.toJS, RiveWasm.scratchBufferPtr);
    final floats = RiveWasm.scratchBufferFloat;

    return AABB.fromValues(floats[0], floats[1], floats[2], floats[3]);
  }

  @override
  AABB get worldBounds {
    RiveWasm.artboardWorldBounds
        .callAsFunction(null, pointer.toJS, RiveWasm.scratchBufferPtr);
    final floats = RiveWasm.scratchBufferFloat;

    return AABB.fromValues(floats[0], floats[1], floats[2], floats[3]);
  }

  @override
  void addToRenderPath(covariant WebRenderPath renderPath, Mat2D transform) =>
      RiveWasm.artboardAddToRenderPath.callAsFunctionEx(
        null,
        pointer.toJS,
        renderPath.pointer,
        transform[0].toJS,
        transform[1].toJS,
        transform[2].toJS,
        transform[3].toJS,
        transform[4].toJS,
        transform[5].toJS,
      );

  @override
  int animationCount() =>
      (RiveWasm.artboardAnimationCount.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  int stateMachineCount() =>
      (RiveWasm.artboardStateMachineCount.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  int get rootFocusDataCount {
    final fn = RiveWasm.artboardRootFocusDataCount;
    if (fn == null) return 0;
    return (fn.callAsFunction(null, pointer.toJS) as js.JSNumber).toDartInt;
  }

  @override
  focus.FocusNode? rootFocusNodeAt(int index) {
    final fn = RiveWasm.artboardRootFocusNodeAt;
    if (fn == null) return null;
    final ptr =
        (fn.callAsFunction(null, pointer.toJS, index.toJS) as js.JSNumber)
            .toDartInt;
    if (ptr == 0) {
      return null;
    }
    return NativeFocusNodeWasmWrapper(ptr);
  }

  @override
  void setExternalParentFocusNode(focus.FocusNode? node) {
    final fn = RiveWasm.artboardSetExternalParentFocusNode;
    if (fn == null) return;
    int nodePtr = 0;
    if (node is NativeFocusNodeWasmWrapper) {
      nodePtr = node.nativePtr;
    } else if (node is FocusNodeWasm) {
      nodePtr = node.nativePtr;
    }
    fn.callAsFunction(null, pointer.toJS, nodePtr.toJS);
  }

  @override
  Animation animationAt(int index) {
    return WebAnimation((RiveWasm.artboardAnimationAt
            .callAsFunction(null, pointer.toJS, index.toJS) as js.JSNumber)
        .toDartInt);
  }

  @override
  Animation? animationNamed(String name) => RiveWasm.toNativeString(
        name,
        (namePointer) {
          final ptr = (RiveWasm.artboardAnimationNamed.callAsFunction(
                  null, pointer.toJS, namePointer) as js.JSNumber)
              .toDartInt;

          if (ptr == 0) {
            return null;
          }

          return WebAnimation(ptr);
        },
      );

  @override
  bool get frameOrigin => _wasmBool(
      RiveWasm.artboardGetFrameOrigin.callAsFunction(null, pointer.toJS));

  @override
  set frameOrigin(bool value) => RiveWasm.artboardSetFrameOrigin
      .callAsFunction(null, pointer.toJS, _boolWasm(value));

  @override
  Component? component(String name) => RiveWasm.toNativeString(
        name,
        (namePointer) {
          final ptr = (RiveWasm.artboardComponentNamed.callAsFunction(
                  null, _pointer.toJS, namePointer) as js.JSNumber)
              .toDartInt;

          if (ptr == 0) {
            return null;
          }

          return WebComponent(ptr);
        },
      );

  @override
  String getText(String runName, {String? path}) => RiveWasm.toNativeString(
        runName,
        (runNamePointer) {
          final nativePath = path?.toWasmUtf8();
          final stringPointer = (RiveWasm.artboardGetText.callAsFunction(
            null,
            _pointer.toJS,
            runNamePointer,
            nativePath?.pointer,
          ) as js.JSNumber)
              .toDartInt;
          if (stringPointer == 0) {
            return '';
          }
          final result = RiveWasm.toDartString(stringPointer);
          nativePath?.dispose();
          return result;
        },
      );

  @override
  bool setText(String runName, String value, {String? path}) =>
      RiveWasm.toNativeString(
        runName,
        (runNamePointer) {
          final nativeValue = value.toWasmUtf8();
          final nativePath = path?.toWasmUtf8();
          final result = _wasmBool(
            RiveWasm.artboardSetText.callAsFunction(
              null,
              _pointer.toJS,
              runNamePointer,
              nativeValue.pointer,
              nativePath?.pointer,
            ),
          );

          nativeValue.dispose();
          nativePath?.dispose();
          return result;
        },
      );

  @override
  Mat2D get renderTransform {
    RiveWasm.artboardGetRenderTransform
        .callAsFunction(null, _pointer.toJS, RiveWasm.scratchBufferPtr);
    final floats = RiveWasm.scratchBufferFloat;
    return Mat2D()
      ..values[0] = floats[0]
      ..values[1] = floats[1]
      ..values[2] = floats[2]
      ..values[3] = floats[3]
      ..values[4] = floats[4]
      ..values[5] = floats[5];
  }

  @override
  set renderTransform(Mat2D value) =>
      RiveWasm.artboardSetRenderTransform.callAsFunctionEx(
        null,
        _pointer.toJS,
        value[0].toJS,
        value[1].toJS,
        value[2].toJS,
        value[3].toJS,
        value[4].toJS,
        value[5].toJS,
      );

  // Flags AdvanceFlags.advanceNested and AdvanceFlags.newFrame set to true
  // by default
  @override
  bool advance(double seconds, {int flags = 9}) =>
      (RiveWasm.riveArtboardAdvance.callAsFunction(
              null, _pointer.toJS, seconds.toJS, flags.toJS) as js.JSNumber)
          .toDartInt ==
      1;

  @override
  double get opacity =>
      (RiveWasm.riveArtboardGetOpacity.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set opacity(double value) => RiveWasm.riveArtboardSetOpacity
      .callAsFunction(null, _pointer.toJS, value.toJS);

  @override
  set hostOpacity(double value) => RiveWasm.riveArtboardSetHostOpacity
      .callAsFunction(null, _pointer.toJS, value.toJS);

  @override
  double get width =>
      (RiveWasm.riveArtboardGetWidth.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set width(double value) => RiveWasm.riveArtboardSetWidth
      .callAsFunction(null, _pointer.toJS, value.toJS);

  @override
  double get height =>
      (RiveWasm.riveArtboardGetHeight.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set height(double value) => RiveWasm.riveArtboardSetHeight
      .callAsFunction(null, _pointer.toJS, value.toJS);

  @override
  double get originX =>
      (RiveWasm.riveArtboardGetOriginX.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set originX(double value) => RiveWasm.riveArtboardSetOriginX
      .callAsFunction(null, _pointer.toJS, value.toJS);

  @override
  double get originY =>
      (RiveWasm.riveArtboardGetOriginY.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set originY(double value) => RiveWasm.riveArtboardSetOriginY
      .callAsFunction(null, _pointer.toJS, value.toJS);

  @override
  double get heightOriginal => (RiveWasm.riveArtboardGetOriginalHeight
          .callAsFunction(null, _pointer.toJS) as js.JSNumber)
      .toDartDouble;

  @override
  double get widthOriginal =>
      (RiveWasm.riveArtboardGetOriginalWidth.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  void resetArtboardSize() {
    width = widthOriginal;
    height = heightOriginal;
  }

  @override
  CallbackHandler onLayoutChanged(void Function() callback) {
    RiveWasm.setArtboardLayoutChangedCallback.callAsFunction(
      null,
      _pointer.toJS,
      callback.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setArtboardLayoutChangedCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  CallbackHandler onTestBounds(int Function(Vec2D pos, bool skip) callback) {
    RiveWasm.setArtboardTestBoundsCallback.callAsFunction(
      null,
      _pointer.toJS,
      (double x, double y, bool skip) {
        return callback(Vec2D.fromValues(x, y), skip).toJS;
      }.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setArtboardTestBoundsCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  CallbackHandler onIsAncestor(int Function(int artboardId) callback) {
    RiveWasm.setArtboardIsAncestorCallback.callAsFunction(
      null,
      _pointer.toJS,
      (int artboardId) {
        return callback(artboardId).toJS;
      }.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setArtboardIsAncestorCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  CallbackHandler onRootTransform(
      double Function(Vec2D pos, bool xAxis) callback) {
    RiveWasm.setArtboardRootTransformCallback.callAsFunction(
      null,
      _pointer.toJS,
      (double x, double y, bool xAxis) {
        return callback(Vec2D.fromValues(x, y), xAxis).toJS;
      }.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setArtboardRootTransformCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  CallbackHandler onEvent(void Function(int) callback) {
    RiveWasm.setArtboardEventCallback.callAsFunction(
      null,
      _pointer.toJS,
      callback.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setArtboardEventCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  AABB get layoutBounds {
    RiveWasm.artboardLayoutBounds
        .callAsFunction(null, pointer.toJS, RiveWasm.scratchBufferPtr);

    final floats = RiveWasm.scratchBufferFloat;

    return AABB.fromValues(floats[0], floats[1], floats[2], floats[3]);
  }

  @override
  CallbackHandler onLayoutDirty(void Function() callback) {
    RiveWasm.setArtboardLayoutDirtyCallback.callAsFunction(
      null,
      _pointer.toJS,
      callback.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setArtboardLayoutDirtyCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  CallbackHandler onTransformDirty(void Function() callback) {
    RiveWasm.setArtboardTransformDirtyCallback.callAsFunction(
      null,
      _pointer.toJS,
      callback.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setArtboardTransformDirtyCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  void syncStyleChanges() =>
      RiveWasm.artboardSyncStyleChanges.callAsFunction(null, _pointer.toJS);

  @override
  dynamic takeLayoutNode() =>
      (RiveWasm.artboardTakeLayoutNode.callAsFunction(null, _pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  void addedToHost() =>
      (RiveWasm.artboardAddedToHost.callAsFunction(null, _pointer.toJS));

  @override
  void widthOverride(double width, int widthUnitValue, bool isRow) =>
      RiveWasm.artboardWidthOverride.callAsFunction(
          null, _pointer.toJS, width.toJS, widthUnitValue.toJS, isRow.toJS);

  @override
  void heightOverride(double height, int heightUnitValue, bool isRow) =>
      RiveWasm.artboardHeightOverride.callAsFunction(
          null, _pointer.toJS, height.toJS, heightUnitValue.toJS, isRow.toJS);

  @override
  void parentIsRow(bool isRow) => RiveWasm.artboardParentIsRow
      .callAsFunction(null, _pointer.toJS, isRow.toJS);

  @override
  void widthIntrinsicallySizeOverride(bool intrinsic) =>
      RiveWasm.artboardWidthIntrinsicallySizeOverride
          .callAsFunction(null, _pointer.toJS, intrinsic.toJS);

  @override
  void heightIntrinsicallySizeOverride(bool intrinsic) =>
      RiveWasm.artboardHeightIntrinsicallySizeOverride
          .callAsFunction(null, _pointer.toJS, intrinsic.toJS);

  @override
  void updateLayoutBounds(bool animate) => RiveWasm.updateLayoutBounds
      .callAsFunction(null, _pointer.toJS, animate.toJS);

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
      RiveWasm.cascadeLayoutStyle.callAsFunctionEx(
          null,
          _pointer.toJS,
          direction.toJS,
          interpolationType.toJS,
          interpolationTime.toJS,
          interpolatorTypeKey.toJS,
          p0.toJS,
          p1.toJS,
          p2.toJS,
          p3.toJS);

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
    // WASM pointers are 32-bit; pack them into a Uint32List and copy into
    // WASM heap as a contiguous uint32_t array (matches uintptr_t on WASM32).
    final ptrs = Uint32List(artboards.length);
    for (var i = 0; i < artboards.length; i++) {
      ptrs[i] = (artboards[i] as WebRiveArtboard)._pointer;
    }
    final wasmBuffer = WasmBuffer.fromBytes(ptrs.buffer.asUint8List());
    RiveWasm.cascadeLayoutStyleBatch.callAsFunctionEx(
        null,
        wasmBuffer.pointer,
        artboards.length.toJS,
        direction.toJS,
        interpolationType.toJS,
        interpolationTime.toJS,
        interpolatorTypeKey.toJS,
        p0.toJS,
        p1.toJS,
        p2.toJS,
        p3.toJS);
    wasmBuffer.dispose();
  }

  @override
  void cascadeCollapseBatch(List<Artboard> artboards, bool collapse) {
    final count = artboards.length;
    final ptrs = Uint32List(artboards.length);
    for (var i = 0; i < artboards.length; i++) {
      ptrs[i] = (artboards[i] as WebRiveArtboard)._pointer;
    }
    final wasmBuffer = WasmBuffer.fromBytes(ptrs.buffer.asUint8List());
    RiveWasm.cascadeCollapseBatch
        ?.callAsFunction(null, wasmBuffer.pointer, count.toJS, collapse.toJS);
    wasmBuffer.dispose();
  }

  @override
  void cascadeCollapse(bool collapse) {
    RiveWasm.cascadeCollapse
        ?.callAsFunction(null, _pointer.toJS, collapse.toJS);
  }

  @override
  void internalBindViewModelInstance(InternalViewModelInstance instance,
      InternalDataContext? dataContext, bool isRoot) {
    RiveWasm.artboardDataContextFromInstance.callAsFunction(
        null,
        _pointer.toJS,
        (instance as WebRiveInternalViewModelInstance).pointer.toJS,
        dataContext != null
            ? (dataContext as WebRiveDataContext).pointer.toJS
            : null,
        isRoot.toJS);
  }

  @override
  void internalSetDataContext(InternalDataContext dataContext) {
    RiveWasm.artboardInternalDataContext.callAsFunction(
        null, _pointer.toJS, (dataContext as WebRiveDataContext).pointer.toJS);
  }

  @override
  InternalDataContext? get internalGetDataContext {
    var ptr = toPointer(
        RiveWasm.artboardDataContext.callAsFunction(null, _pointer.toJS));
    if (ptr == 0) {
      return null;
    }
    return WebRiveDataContext(ptr);
  }

  @override
  void internalClearDataContext() {
    RiveWasm.artboardClearDataContext.callAsFunction(null, _pointer.toJS);
  }

  @override
  void internalUnbind() {
    RiveWasm.artboardUnbind.callAsFunction(null, _pointer.toJS);
  }

  @override
  void internalUpdateDataBinds() {
    RiveWasm.artboardUpdateDataBinds.callAsFunction(
      null,
      _pointer.toJS,
    );
  }

  @override
  bool hasComponentDirt() => _wasmBool(RiveWasm.riveArtboardHasComponentDirt
      .callAsFunction(null, _pointer.toJS) as js.JSNumber);

  @override
  bool updatePass() {
    return _wasmBool(RiveWasm.riveArtboardUpdatePass
        .callAsFunction(null, _pointer.toJS) as js.JSNumber);
  }

  @override
  void bindViewModelInstance(
      covariant WebViewModelInstanceRuntime viewModelInstance) {
    RiveWasm.artboardSetVMIRuntime.callAsFunction(
      null,
      _pointer.toJS,
      viewModelInstance.pointer.toJS,
    );
  }

  @override
  List<TextValueRunRuntime> get textRuns {
    final rawResult =
        RiveWasm.artboardGetAllTextRuns.callAsFunction(null, _pointer.toJS);
    if (rawResult == null) {
      return [];
    }
    final result = rawResult as js.JSObject;
    final count = (result.getProperty('count'.toJS) as js.JSNumber).toDartInt;
    final arrayPtr =
        (result.getProperty('array'.toJS) as js.JSNumber).toDartInt;

    if (count == 0 || arrayPtr == 0) {
      if (arrayPtr != 0) {
        RiveWasm.freeTextRunsArray.callAsFunction(null, arrayPtr.toJS);
      }
      return [];
    }

    final textRuns = <TextValueRunRuntime>[];
    for (int i = 0; i < count; i++) {
      final textRunPtr = (RiveWasm.getTextRunFromArray
              .callAsFunction(null, arrayPtr.toJS, i.toJS) as js.JSNumber)
          .toDartInt;
      if (textRunPtr != 0) {
        textRuns.add(WebTextValueRun(textRunPtr));
      }
    }

    RiveWasm.freeTextRunsArray.callAsFunction(null, arrayPtr.toJS);
    return textRuns;
  }

  @override
  void buildFocusTreeWithParent(focus.FocusNode? parentNode) {
    int nodePtr = 0;
    if (parentNode is NativeFocusNodeWasmWrapper) {
      nodePtr = parentNode.nativePtr;
    } else if (parentNode is FocusNodeWasm) {
      nodePtr = parentNode.nativePtr;
    }
    RiveWasm.artboardBuildFocusTreeWithParent
        .callAsFunction(null, pointer.toJS, nodePtr.toJS);
  }
}

bool _wasmBool(js.JSAny? value) => (value as js.JSNumber).toDartInt == 1;
js.JSNumber _boolWasm(bool value) => (value ? 1 : 0).toJS;

class WebBindableArtboard extends BindableArtboard {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteBindableArtboard.callAsFunction(null, pointer),
  );

  int get pointer => _pointer;
  int _pointer;

  /// Strong reference to avoid GC/finalization of the associated VMI while
  /// this bindable artboard is still in use.
  WebViewModelInstanceRuntime? _viewModelInstance;

  int get viewModelInstancePointer => _viewModelInstance?.pointer ?? 0;

  WebBindableArtboard(
    this._pointer, {
    WebViewModelInstanceRuntime? viewModelInstance,
  }) : _viewModelInstance = viewModelInstance {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    _viewModelInstance = null;
    final pointer = _pointer;
    _pointer = 0;
    _finalizer.detach(this);
    RiveWasm.deleteBindableArtboard.callAsFunction(null, pointer.toJS);
  }
}

class WebStateMachine extends StateMachine
    with EventListenerMixin, AdvanceRequestMixin {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteStateMachineInstance.callAsFunction(null, pointer),
  );

  int get pointer => _pointer;
  int _pointer;

  WebStateMachine(this._pointer) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  String get name => RiveWasm.toDartString(
        (RiveWasm.stateMachineInstanceName.callAsFunction(null, pointer.toJS)
                as js.JSNumber)
            .toDartInt,
        deleteNative: true,
      );

  @override
  bool advance(double elapsedSeconds, bool newFrame) => _wasmBool(
        RiveWasm.stateMachineInstanceAdvance.callAsFunction(
          null,
          pointer.toJS,
          elapsedSeconds.toJS,
          newFrame.toJS,
        ),
      );

  final _stateChangedListeners = <void Function(String stateName)>{};

  @override
  bool advanceAndApply(double elapsedSeconds) {
    _handleEvents();
    final result = _wasmBool(
      RiveWasm.stateMachineInstanceAdvanceAndApply.callAsFunction(
        null,
        pointer.toJS,
        elapsedSeconds.toJS,
      ),
    );
    boundRuntimeViewModelInstance?.handleCallbacks();
    if (_stateChangedListeners.isNotEmpty) {
      final count = (RiveWasm.stateMachineInstanceStateChangedCount
              .callAsFunction(null, pointer.toJS) as js.JSNumber)
          .toDartInt;
      for (var i = 0; i < count; i++) {
        final namePtr = (RiveWasm.stateMachineInstanceStateChangedNameByIndex
                .callAsFunction(null, pointer.toJS, i.toJS) as js.JSNumber)
            .toDartInt;
        final stateName = RiveWasm.toDartString(namePtr, deleteNative: true);
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
    if (_pointer == 0) {
      return;
    }
    RiveWasm.deleteStateMachineInstance.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
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
    RiveWasm.setStateMachineInputChangedCallback.callAsFunction(
      null,
      _pointer.toJS,
      callback.toJS,
    );
    return ClosureCallbackHandler(() {
      RiveWasm.setStateMachineInputChangedCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  int _inputWrapper(js.JSFunction nativeFunction, String name,
          {String? path}) =>
      RiveWasm.toNativeString(
        name,
        (namePointer) {
          final wasmPath = path?.toWasmUtf8();
          final ptr = (nativeFunction.callAsFunction(
            null,
            _pointer.toJS,
            namePointer,
            wasmPath?.pointer,
          ) as js.JSNumber)
              .toDartInt;

          wasmPath?.dispose();
          return ptr;
        },
      );

  @override
  BooleanInput? boolean(String name, {String? path}) {
    final ptr =
        _inputWrapper(RiveWasm.stateMachineInstanceBoolean, name, path: path);
    return ptr == 0 ? null : WebBooleanInput(ptr, this);
  }

  @override
  NumberInput? number(String name, {String? path}) {
    final ptr =
        _inputWrapper(RiveWasm.stateMachineInstanceNumber, name, path: path);
    return ptr == 0 ? null : WebNumberInput(ptr, this);
  }

  @override
  TriggerInput? trigger(String name, {String? path}) {
    final ptr =
        _inputWrapper(RiveWasm.stateMachineInstanceTrigger, name, path: path);
    return ptr == 0 ? null : WebTriggerInput(ptr, this);
  }

  @override
  Input? inputAt(int index) {
    var inputPointer = (RiveWasm.stateMachineInput
            .callAsFunction(null, _pointer.toJS, index.toJS) as js.JSNumber)
        .toDartInt;
    if (inputPointer == 0) {
      return null;
    }
    switch (RiveWasm.stateMachineInputType
        .callAsFunction(null, inputPointer.toJS)) {
      case 56:
        return WebNumberInput(inputPointer, this);
      case 58:
        return WebTriggerInput(inputPointer, this);
      case 59:
        return WebBooleanInput(inputPointer, this);
      default:
        return null;
    }
  }

  @override
  bool get isDone => _wasmBool(
      RiveWasm.stateMachineInstanceDone.callAsFunction(null, _pointer.toJS));

  @override
  bool hitTest(Vec2D position) => _wasmBool(RiveWasm.stateMachineInstanceHitTest
      .callAsFunction(null, _pointer.toJS, position.x.toJS, position.y.toJS));

  @override
  HitResult pointerDown(Vec2D position, {int pointerId = 0}) {
    return HitResult.values[(RiveWasm.stateMachineInstancePointerDown
            .callAsFunction(null, _pointer.toJS, position.x.toJS,
                position.y.toJS, pointerId.toJS) as js.JSNumber)
        .toDartInt];
  }

  @override
  HitResult pointerExit(Vec2D position, {int pointerId = 0}) =>
      HitResult.values[(RiveWasm.stateMachineInstancePointerExit.callAsFunction(
              null,
              _pointer.toJS,
              position.x.toJS,
              position.y.toJS,
              pointerId.toJS) as js.JSNumber)
          .toDartInt];

  @override
  HitResult pointerMove(Vec2D position,
          {double? timeStamp, int pointerId = 0}) =>
      HitResult.values[(RiveWasm.stateMachineInstancePointerMove.callAsFunction(
              null,
              _pointer.toJS,
              position.x.toJS,
              position.y.toJS,
              (timeStamp ?? 0).toJS,
              pointerId.toJS) as js.JSNumber)
          .toDartInt];

  @override
  HitResult pointerUp(Vec2D position, {int pointerId = 0}) =>
      HitResult.values[(RiveWasm.stateMachineInstancePointerUp.callAsFunction(
              null,
              _pointer.toJS,
              position.x.toJS,
              position.y.toJS,
              pointerId.toJS) as js.JSNumber)
          .toDartInt];

  @override
  HitResult dragStart(Vec2D position, {double? timeStamp}) =>
      HitResult.values[(RiveWasm.stateMachineInstanceDragStart.callAsFunction(
              null,
              _pointer.toJS,
              position.x.toJS,
              position.y.toJS,
              (timeStamp ?? 0).toJS) as js.JSNumber)
          .toDartInt];

  @override
  HitResult dragEnd(Vec2D position, {double? timeStamp}) =>
      HitResult.values[(RiveWasm.stateMachineInstanceDragEnd.callAsFunction(
              null,
              _pointer.toJS,
              position.x.toJS,
              position.y.toJS,
              (timeStamp ?? 0).toJS) as js.JSNumber)
          .toDartInt];

  @override
  bool submitGamepadsFromBuffer(Uint8List buffer) {
    if (buffer.isEmpty) {
      return false;
    }
    final wasmBuffer = WasmBuffer.fromBytes(buffer);
    try {
      return _wasmBool(
        RiveWasm.stateMachineInstanceSubmitGamepadsFromBuffer.callAsFunctionEx(
          null,
          _pointer.toJS,
          wasmBuffer.pointer,
          _jsBigInt(buffer.lengthInBytes.toJS),
        ),
      );
    } finally {
      wasmBuffer.dispose();
    }
  }

  @override
  void dispatchGamepadInvocation(GamepadInvocationHandle handle) {
    final webHandle = handle as WebGamepadInvocationHandle;
    final native = webHandle._pointer;
    if (native == null) {
      return;
    }
    RiveWasm.stateMachineInstanceDispatchGamepadInvocation.callAsFunction(
      null,
      _pointer.toJS,
      native,
    );
  }

  @override
  void enableSemantics() {
    SemanticsWasm.enableSemantics(_pointer);
  }

  @override
  SemanticsDiff drainSemanticsDiff() => SemanticsWasm.drainDiff(_pointer);

  @override
  bool focusSemanticNode(int semanticNodeId) =>
      SemanticsWasm.requestFocus(_pointer, semanticNodeId);

  @override
  void fireSemanticAction(int semanticNodeId, SemanticActionType actionType) {
    SemanticsWasm.fireAction(_pointer, semanticNodeId, actionType.index);
  }

  @override
  void internalBindViewModelInstance(InternalViewModelInstance instance) {
    RiveWasm.stateMachineDataContextFromInstance.callAsFunction(
        null,
        _pointer.toJS,
        (instance as WebRiveInternalViewModelInstance).pointer.toJS);
  }

  @override
  void internalDataContext(InternalDataContext dataContext) {
    RiveWasm.stateMachineDataContext.callAsFunction(
        null, _pointer.toJS, (dataContext as WebRiveDataContext).pointer.toJS);
  }

  @override
  CallbackHandler onDataBindChanged(void Function() callback) {
    RiveWasm.setStateMachineDataBindChangedCallback.callAsFunction(
      null,
      _pointer.toJS,
      callback.toJS,
    );

    return ClosureCallbackHandler(() {
      RiveWasm.setStateMachineDataBindChangedCallback.callAsFunction(
        null,
        _pointer.toJS,
        null,
      );
    });
  }

  @override
  void bindViewModelInstance(
      covariant WebViewModelInstanceRuntime viewModelInstance) {
    super.bindViewModelInstance(viewModelInstance);
    RiveWasm.stateMachineSetVMIRuntime.callAsFunction(
      null,
      _pointer.toJS,
      viewModelInstance.pointer.toJS,
    );
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
    final count = (RiveWasm.stateMachineGetReportedEventCount
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    List<Event> events = [];
    for (var index = 0; index < count; index++) {
      final eventReportObject = RiveWasm.stateMachineReportedEventAt
          .callAsFunction(null, _pointer.toJS, index.toJS) as js.JSObject;
      ReportedEventWeb eventReport = ReportedEventWeb(
        (eventReportObject.getProperty('event'.toJS) as js.JSNumber).toDartInt,
        (eventReportObject.getProperty('secondsDelay'.toJS) as js.JSNumber)
            .toDartDouble,
        (eventReportObject.getProperty('type'.toJS) as js.JSNumber).toDartInt,
      );
      final eventType = EventType.from[eventReport.type];
      if (eventType == null) {
        // An event of this type is not handled at runtime, immediately dispose
        // native resources and continue to the next event.
        RiveWasm.deleteEvent
            .callAsFunction(null, eventReport.eventPointer.toJS);
        continue;
      }
      Event event = switch (eventType) {
        EventType.general => WebGeneralEvent(eventReport),
        EventType.openURL => WebOpenURLEvent(eventReport),
        EventType.audio => WebAudioRuntimeEvent(eventReport),
      };
      events.add(event);
    }
    return events;
  }

  @override
  focus.FocusManager? get focusManager {
    final ptr = (RiveWasm.stateMachineGetFocusManager
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (ptr == 0) {
      return null;
    }
    return NativeFocusManagerWasmWrapper(ptr);
  }

  @override
  void setExternalFocusManager(int? pointerAddress) {
    final ptr = pointerAddress ?? 0;
    RiveWasm.stateMachineSetExternalFocusManager
        .callAsFunction(null, _pointer.toJS, ptr.toJS);
  }
}

/// Web-backed implementation of [GamepadInvocationHandle]. Owns the JS
/// pointer returned by `_makeGamepadInvocation`.
class WebGamepadInvocationHandle implements GamepadInvocationHandle {
  js.JSAny? _pointer;
  WebGamepadInvocationHandle._(this._pointer);

  @override
  void dispose() {
    final ptr = _pointer;
    if (ptr == null) {
      return;
    }
    RiveWasm.deleteGamepadInvocation.callAsFunction(null, ptr);
    _pointer = null;
  }
}

/// Top-level factory for [GamepadInvocationHandle] resolved via the
/// conditional import in `rive.dart`. Copies button/axis lists into
/// transient [WasmBuffer]s, hands them to `_makeGamepadInvocation`, then
/// disposes the buffers (the C++ side copies into its own `std::vector`).
WebGamepadInvocationHandle makeGamepadInvocationHandle({
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
    final native = RiveWasm.makeGamepadInvocation.callAsFunctionEx(
      null,
      kind.toJS,
      deviceId.toJS,
      _jsBigInt(buttonMask.toJS),
      buttonBuffer?.pointer ?? 0.toJS,
      _jsBigInt(buttonF32.length.toJS),
      axesBuffer?.pointer ?? 0.toJS,
      _jsBigInt(axesF32.length.toJS),
      mapping.toJS,
      changeKind.toJS,
      changeIndex.toJS,
      changeValue.toJS,
    );
    return WebGamepadInvocationHandle._(native);
  } finally {
    buttonBuffer?.dispose();
    axesBuffer?.dispose();
  }
}

final class ReportedEventWeb {
  int eventPointer;
  final double secondsDelay;
  final int type;

  ReportedEventWeb(this.eventPointer, this.secondsDelay, this.type);
}

final class CustomPropertyWeb {
  int propertyPointer;
  final int namePointer;
  final int type;

  CustomPropertyWeb(this.propertyPointer, this.namePointer, this.type);
}

sealed class WebEvent with EventPropertyMixin implements EventInterface {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) => RiveWasm.deleteEvent.callAsFunction(null, pointer),
  );
  final ReportedEventWeb _native;
  WebEvent._(this._native) {
    _finalizer.attach(this, pointer.toJS, detach: this);
  }

  int get pointer => _native.eventPointer;

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
    final count = (RiveWasm.getEventCustomPropertyCount
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    for (var index = 0; index < count; index++) {
      final propertyObject = RiveWasm.getEventCustomProperty
          .callAsFunction(null, pointer.toJS, index.toJS) as js.JSObject;
      final propertyStruct = CustomPropertyWeb(
        (propertyObject.getProperty('property'.toJS) as js.JSNumber).toDartInt,
        (propertyObject.getProperty('name'.toJS) as js.JSNumber).toDartInt,
        (propertyObject.getProperty('type'.toJS) as js.JSNumber).toDartInt,
      );
      final propertyType = CustomPropertyType.from[propertyStruct.type];
      CustomProperty? property = switch (propertyType) {
        null => null,
        CustomPropertyType.number => WebCustomNumberProperty(propertyStruct),
        CustomPropertyType.boolean => WebCustomBooleanProperty(propertyStruct),
        CustomPropertyType.string => WebCustomStringProperty(propertyStruct),
      };
      if (property != null) {
        _cachedProperties![property.name] = property;
      }
    }
  }

  @override
  String get name {
    final stringPointer = (RiveWasm.getEventName
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  double get secondsDelay => _native.secondsDelay;

  @override
  EventType get type => EventType.from[_native.type] ?? EventType.general;

  @override
  void dispose() {
    if (pointer == 0) {
      return;
    }
    RiveWasm.deleteEvent.callAsFunction(null, pointer.toJS);
    _native.eventPointer = 0;
    _finalizer.detach(this);
  }
}

class WebGeneralEvent extends WebEvent implements GeneralEvent {
  WebGeneralEvent(super._native) : super._();

  @override
  String toString() {
    return 'GeneralEvent{type: $type, name: $name, properties: $properties}';
  }
}

class WebOpenURLEvent extends WebEvent implements OpenUrlEvent {
  WebOpenURLEvent(super._native) : super._();

  @override
  OpenUrlTarget get target {
    final targetInt = (RiveWasm.getOpenUrlEventTarget
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    final value = OpenUrlTarget.from[targetInt];
    return value ?? OpenUrlTarget.blank;
  }

  @override
  String get url {
    final stringPointer = (RiveWasm.getOpenUrlEventUrl
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  String toString() {
    return 'OpenURLEvent{type: $type, name: $name, url: $url, target: $target, properties: $properties}';
  }
}

class WebAudioRuntimeEvent extends WebEvent implements AudioRuntimeEvent {
  WebAudioRuntimeEvent(super._native) : super._();

  @override
  int get assetId =>
      (RiveWasm.getAudioEventAssetId.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  String get assetName {
    final stringPointer = (RiveWasm.getAudioEventAssetName
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  double get volume =>
      (RiveWasm.getAudioEventVolume.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  String toString() {
    return 'AudioRuntimeEvent{type: $type, name: $name, assetId: $assetId, '
        'assetName: $assetName, volume: $volume, properties: $properties}';
  }
}

sealed class WebCustomProperty<T> implements CustomPropertyInterface<T> {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteCustomProperty.callAsFunction(null, pointer),
  );

  final CustomPropertyWeb _native;
  WebCustomProperty(this._native) {
    _finalizer.attach(this, pointer.toJS, detach: this);
  }

  int get pointer => _native.propertyPointer;

  @override
  String get name {
    final stringPointer = _native.namePointer;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  CustomPropertyType get type => CustomPropertyType.from[_native.type]!;

  @override
  String toString() {
    return 'CustomProperty{type: $type, name: $name, value: $value}';
  }

  @override
  void dispose() {
    if (_native.propertyPointer == 0) {
      return;
    }
    RiveWasm.deleteCustomProperty.callAsFunction(null, pointer.toJS);
    _native.propertyPointer = 0;
    _finalizer.detach(this);
  }
}

class WebCustomNumberProperty extends WebCustomProperty<double>
    implements CustomNumberProperty {
  WebCustomNumberProperty(super._native);
  @override
  double get value =>
      (RiveWasm.getCustomPropertyNumber.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;
}

class WebCustomBooleanProperty extends WebCustomProperty<bool>
    implements CustomBooleanProperty {
  WebCustomBooleanProperty(super._native);
  @override
  bool get value => _wasmBool(
      RiveWasm.getCustomPropertyBoolean.callAsFunction(null, pointer.toJS));
}

class WebCustomStringProperty extends WebCustomProperty<String>
    implements CustomStringProperty {
  WebCustomStringProperty(super._native);
  @override
  String get value {
    final stringPointer = (RiveWasm.getCustomPropertyString
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }
}

abstract class WebInput extends Input {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) => RiveWasm.deleteInput.callAsFunction(null, pointer),
  );

  final WebStateMachine _stateMachine;

  int get pointer => _pointer;
  int _pointer;

  WebInput(this._pointer, this._stateMachine) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    RiveWasm.deleteInput.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
    _finalizer.detach(this);
  }

  @override
  String get name {
    var stringPointer = (RiveWasm.stateMachineInputName
            .callAsFunction(null, pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  StateMachine get internalStateMachine => _stateMachine;
}

class WebNumberInput extends WebInput implements NumberInput {
  WebNumberInput(super.pointer, super._stateMachine);

  @override
  double get value =>
      (RiveWasm.getNumberValue.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set value(double value) {
    RiveWasm.setNumberValue.callAsFunction(null, pointer.toJS, value.toJS);
    internalStateMachine.requestAdvance();
  }
}

class WebTriggerInput extends WebInput implements TriggerInput {
  WebTriggerInput(super.pointer, super._stateMachine);

  @override
  void fire() {
    RiveWasm.fireTrigger.callAsFunction(null, pointer.toJS);
    internalStateMachine.requestAdvance();
  }
}

class WebBooleanInput extends WebInput implements BooleanInput {
  WebBooleanInput(super.pointer, super._stateMachine);

  @override
  bool get value =>
      _wasmBool(RiveWasm.getBooleanValue.callAsFunction(null, pointer.toJS));

  @override
  set value(bool value) {
    RiveWasm.setBooleanValue.callAsFunction(null, pointer.toJS, value.toJS);
    internalStateMachine.requestAdvance();
  }
}

class WebComponent extends Component {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteComponent.callAsFunction(null, pointer),
  );

  int get pointer => _pointer;
  int _pointer;

  WebComponent(this._pointer) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    RiveWasm.deleteComponent.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
    _finalizer.detach(this);
  }

  @override
  AABB get localBounds {
    RiveWasm.componentGetLocalBounds.callAsFunction(
      null,
      pointer.toJS,
      RiveWasm.scratchBufferPtr,
    );
    final floats = RiveWasm.scratchBufferFloat;
    return AABB.fromLTRB(floats[0], floats[1], floats[2], floats[3]);
  }

  @override
  Mat2D get worldTransform {
    RiveWasm.componentGetWorldTransform.callAsFunction(
      null,
      pointer.toJS,
      RiveWasm.scratchBufferPtr,
    );
    final floats = RiveWasm.scratchBufferFloat;

    return Mat2D()
      ..values[0] = floats[0]
      ..values[1] = floats[1]
      ..values[2] = floats[2]
      ..values[3] = floats[3]
      ..values[4] = floats[4]
      ..values[5] = floats[5];
  }

  @override
  set worldTransform(Mat2D value) =>
      RiveWasm.componentSetWorldTransform.callAsFunctionEx(
        null,
        pointer.toJS,
        value[0].toJS,
        value[1].toJS,
        value[2].toJS,
        value[3].toJS,
        value[4].toJS,
        value[5].toJS,
      );

  @override
  double get scaleX =>
      (RiveWasm.componentGetScaleX.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set scaleX(double value) => RiveWasm.componentSetScaleX
      .callAsFunction(null, pointer.toJS, value.toJS);

  @override
  double get scaleY =>
      (RiveWasm.componentGetScaleY.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set rotation(double value) => RiveWasm.componentSetRotation
      .callAsFunction(null, pointer.toJS, value.toJS);

  @override
  double get rotation =>
      (RiveWasm.componentGetRotation.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set scaleY(double value) => RiveWasm.componentSetScaleY
      .callAsFunction(null, pointer.toJS, value.toJS);

  @override
  double get x =>
      (RiveWasm.componentGetX.callAsFunction(null, pointer.toJS) as js.JSNumber)
          .toDartDouble;

  @override
  set x(double value) =>
      RiveWasm.componentSetX.callAsFunction(null, pointer.toJS, value.toJS);

  @override
  double get y =>
      (RiveWasm.componentGetY.callAsFunction(null, pointer.toJS) as js.JSNumber)
          .toDartDouble;

  @override
  set y(double value) =>
      RiveWasm.componentSetY.callAsFunction(null, pointer.toJS, value.toJS);

  @override
  void setLocalFromWorld(Mat2D worldTransform) =>
      RiveWasm.componentSetLocalFromWorld.callAsFunctionEx(
        null,
        pointer.toJS,
        worldTransform[0].toJS,
        worldTransform[1].toJS,
        worldTransform[2].toJS,
        worldTransform[3].toJS,
        worldTransform[4].toJS,
        worldTransform[5].toJS,
      );
}

class WebTextValueRun extends TextValueRunRuntime {
  static final _finalizer = Finalizer(
    (js.JSAny pointer) =>
        RiveWasm.deleteTextValueRun.callAsFunction(null, pointer),
  );

  int get pointer => _pointer;
  int _pointer;

  WebTextValueRun(this._pointer) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  String get name {
    final stringPointer = (RiveWasm.textValueRunName
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  String get text {
    final stringPointer = (RiveWasm.textValueRunText
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  String get path {
    final stringPointer = (RiveWasm.textValueRunPath
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    if (stringPointer == 0) {
      return '';
    }
    return RiveWasm.toDartString(stringPointer);
  }

  @override
  set text(String value) => RiveWasm.toNativeString(
        value,
        (valuePointer) {
          RiveWasm.textValueRunSetText
              .callAsFunction(null, _pointer.toJS, valuePointer);
        },
      );

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    final pointer = _pointer;
    _pointer = 0;
    _finalizer.detach(this);
    RiveWasm.deleteTextValueRun.callAsFunction(null, pointer.toJS);
  }
}

class WebAnimation extends Animation {
  static final _finalizer = Finalizer((js.JSAny pointer) =>
      RiveWasm.animationInstanceDelete.callAsFunction(null, pointer));

  int get pointer => _pointer;
  int _pointer;

  WebAnimation(this._pointer) {
    _finalizer.attach(this, _pointer.toJS, detach: this);
  }

  @override
  String get name => RiveWasm.toDartString(
        (RiveWasm.animationInstanceName.callAsFunction(null, pointer.toJS)
                as js.JSNumber)
            .toDartInt,
        deleteNative: true,
      );

  @override
  double get time =>
      (RiveWasm.animationInstanceGetTime.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  double get duration =>
      (RiveWasm.animationInstanceGetDuration.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartDouble;

  @override
  set time(double value) => RiveWasm.animationInstanceSetTime
      .callAsFunction(null, pointer.toJS, value.toJS);

  @override
  bool advance(double elapsedSeconds) =>
      _wasmBool(RiveWasm.animationInstanceAdvance
          .callAsFunction(null, pointer.toJS, elapsedSeconds.toJS));

  @override
  bool advanceAndApply(double elapsedSeconds) =>
      _wasmBool(RiveWasm.animationInstanceAdvanceAndApply
          .callAsFunction(null, pointer.toJS, elapsedSeconds.toJS));

  @override
  void apply({double mix = 1.0}) => RiveWasm.animationInstanceApply
      .callAsFunction(null, pointer.toJS, mix.toJS);

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    RiveWasm.animationInstanceDelete.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
    _finalizer.detach(this);
  }

  @override
  double globalToLocalTime(double seconds) =>
      (RiveWasm.animationInstanceGetLocalSeconds
              .callAsFunction(null, pointer.toJS, seconds.toJS) as js.JSNumber)
          .toDartDouble;
}

class WebRiveDataContext extends InternalDataContext {
  static final _finalizer = Finalizer((js.JSAny pointer) =>
      RiveWasm.deleteDataContext.callAsFunction(null, pointer));
  int get pointer => _pointer;
  int _pointer;
  WebRiveDataContext(this._pointer);

  @override
  InternalViewModelInstance get viewModelInstance {
    var ptr = toPointer(RiveWasm.riveDataContextViewModelInstance
        .callAsFunction(null, _pointer.toJS));
    return WebRiveInternalViewModelInstance(ptr);
  }

  @override
  InternalViewModelInstance? viewModelInstanceAt(int index) {
    var ptr = toPointer(RiveWasm.dataContextViewModelInstanceAt
        .callAsFunction(null, _pointer.toJS, index.toJS));
    if (ptr == 0) return null;
    return WebRiveInternalViewModelInstance(ptr);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    RiveWasm.deleteDataContext.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
    _finalizer.detach(this);
  }
}

class WebInternalViewModelInstanceValue<T>
    extends InternalViewModelInstanceValue<T> {
  static final _finalizer = Finalizer((js.JSAny pointer) =>
      RiveWasm.deleteViewModelInstanceValue.callAsFunction(null, pointer));

  int get pointer => _pointer;
  int _pointer;
  void Function(T value)? _callback;

  WebInternalViewModelInstanceValue(this._pointer) {
    _finalizer.attach(this, _pointer.toJS, detach: this);

    instancePointerAddress = getInstancePointer();
    WebRiveFile.internalRegisterViewModelInstance(instancePointerAddress, this);
  }
  @override
  void onChanged(void Function(T value) callback) {
    _callback = callback;
  }

  int getInstancePointer() {
    return 0;
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    RiveWasm.deleteViewModelInstanceValue.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
    _finalizer.detach(this);
  }

  @override
  advanced() {
    RiveWasm.setViewModelInstanceAdvanced.callAsFunction(null, _pointer.toJS);
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

class WebRiveInternalViewModelInstance extends InternalViewModelInstance {
  static final _finalizer = Finalizer((js.JSAny pointer) =>
      RiveWasm.deleteViewModelInstance.callAsFunction(null, pointer));
  int get pointer => _pointer;
  int _pointer;
  WebRiveInternalViewModelInstance(this._pointer);

  int _propertyFromNameAndType(int index, String name, int type) {
    return RiveWasm.toNativeString(
      name,
      (namePointer) {
        final ptr = (RiveWasm.viewModelInstancePropertyValue.callAsFunction(
                    null, _pointer.toJS, index.toJS, namePointer, type.toJS)
                as js.JSNumber)
            .toDartInt;

        if (ptr == 0) {
          return 0;
        }

        return ptr;
      },
    );
  }

  @override
  InternalViewModelInstanceViewModel propertyViewModel(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebRiveInternalViewModelInstanceViewModel(ptr);
  }

  @override
  InternalViewModelInstanceNumber propertyNumber(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceNumber(ptr);
  }

  @override
  InternalViewModelInstanceBoolean propertyBoolean(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceBoolean(ptr);
  }

  @override
  InternalViewModelInstanceColor propertyColor(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceColor(ptr);
  }

  @override
  InternalViewModelInstanceString propertyString(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceString(ptr);
  }

  @override
  InternalViewModelInstanceTrigger propertyTrigger(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceTrigger(ptr);
  }

  @override
  InternalViewModelInstanceEnum propertyEnum(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceEnum(ptr);
  }

  @override
  InternalViewModelInstanceList propertyList(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceList(ptr);
  }

  @override
  InternalViewModelInstanceSymbolListIndex propertySymbolListIndex(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceSymbolListIndex(ptr);
  }

  @override
  InternalViewModelInstanceAsset propertyAsset(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceAsset(ptr);
  }

  @override
  InternalViewModelInstanceArtboard propertyArtboard(
      int index, String name, int propertyType) {
    var ptr = _propertyFromNameAndType(index, name, propertyType);
    return WebInternalViewModelInstanceArtboard(ptr);
  }

  @override
  void pruneToProperties(List<int> keepPropertyIds) {
    if (_pointer == 0) {
      return;
    }
    final count = keepPropertyIds.length;
    if (count == 0) {
      RiveWasm.pruneViewModelInstanceToProperties
          .callAsFunction(null, _pointer.toJS, 0.toJS, 0.toJS);
      return;
    }
    const int u32Size = 4;
    final buf = (RiveWasm.allocateBuffer
            .callAsFunction(null, (count * u32Size).toJS) as js.JSNumber)
        .toDartInt;
    final view = RiveWasm.heapViewU32(buf, count);
    for (var i = 0; i < count; i++) {
      view[i] = keepPropertyIds[i];
    }
    RiveWasm.pruneViewModelInstanceToProperties
        .callAsFunction(null, _pointer.toJS, buf.toJS, count.toJS);
    RiveWasm.deleteBuffer.callAsFunction(null, buf.toJS);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    RiveWasm.deleteViewModelInstance.callAsFunction(null, _pointer.toJS);
    _pointer = 0;
    _finalizer.detach(this);
  }

  @override
  String uniqueId() {
    return _pointer.toString();
  }
}

class WebRiveInternalViewModelInstanceViewModel
    extends WebInternalViewModelInstanceValue<InternalViewModelInstance?>
    implements InternalViewModelInstanceViewModel {
  WebRiveInternalViewModelInstanceViewModel(super.pointer);

  @override
  InternalViewModelInstance get referenceViewModelInstance {
    var ptr = toPointer(RiveWasm.viewModelInstanceReferenceViewModel
        .callAsFunction(null, _pointer.toJS));
    return WebRiveInternalViewModelInstance(ptr);
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
  void applyValue(InternalViewModelInstance? val) {
    if (val != null) {
      RiveWasm.setViewModelInstanceViewModelValue.callAsFunction(
          null,
          _pointer.toJS,
          (val as WebRiveInternalViewModelInstance).pointer.toJS);
    }
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceViewModelCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceNumber
    extends WebInternalViewModelInstanceValue<double>
    implements InternalViewModelInstanceNumber {
  WebInternalViewModelInstanceNumber(super.pointer);

  @override
  applyValue(double val) {
    RiveWasm.setViewModelInstanceNumberValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceNumberCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceColor
    extends WebInternalViewModelInstanceValue<int>
    implements InternalViewModelInstanceColor {
  WebInternalViewModelInstanceColor(super.pointer);

  @override
  applyValue(int val) {
    RiveWasm.setViewModelInstanceColorValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceColorCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceString
    extends WebInternalViewModelInstanceValue<String>
    implements InternalViewModelInstanceString {
  WebInternalViewModelInstanceString(super.pointer);

  @override
  applyValue(String val) => RiveWasm.toNativeString(
        val,
        (valPointer) {
          RiveWasm.setViewModelInstanceStringValue
              .callAsFunction(null, _pointer.toJS, valPointer);
        },
      );

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceStringCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceBoolean
    extends WebInternalViewModelInstanceValue<bool>
    implements InternalViewModelInstanceBoolean {
  WebInternalViewModelInstanceBoolean(super.pointer);

  @override
  applyValue(bool val) {
    RiveWasm.setViewModelInstanceBooleanValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceBooleanCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceTrigger
    extends WebInternalViewModelInstanceValue<int>
    implements InternalViewModelInstanceTrigger {
  WebInternalViewModelInstanceTrigger(super.pointer);

  @override
  applyValue(int val) {
    RiveWasm.setViewModelInstanceTriggerValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceTriggerCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceEnum
    extends WebInternalViewModelInstanceValue<int>
    implements InternalViewModelInstanceEnum {
  WebInternalViewModelInstanceEnum(super.pointer);

  @override
  applyValue(int val) {
    RiveWasm.setViewModelInstanceEnumValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceEnumCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceSymbolListIndex
    extends WebInternalViewModelInstanceValue<int>
    implements InternalViewModelInstanceSymbolListIndex {
  WebInternalViewModelInstanceSymbolListIndex(super.pointer);

  @override
  applyValue(int val) {
    RiveWasm.setViewModelInstanceSymbolListIndexValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceSymbolListIndexCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceList
    extends WebInternalViewModelInstanceValue<List<InternalViewModelInstance>?>
    implements InternalViewModelInstanceList {
  WebInternalViewModelInstanceList(super.pointer);

  @override
  InternalViewModelInstance referenceViewModelInstance(int index) {
    var ptr = toPointer(RiveWasm.viewModelInstanceListItemViewModel
        .callAsFunction(null, _pointer.toJS, index.toJS));
    return WebRiveInternalViewModelInstance(ptr);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceListCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
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
  int size() {
    final listSize = (RiveWasm.viewModelInstanceListSize
            .callAsFunction(null, _pointer.toJS) as js.JSNumber)
        .toDartInt;
    return listSize;
  }

  @override
  void applyValue(List<InternalViewModelInstance>? val) {
    if (val == null || val.isEmpty) {
      RiveWasm.setViewModelInstanceListValue
          .callAsFunction(null, _pointer.toJS, 0.toJS, 0.toJS);
      return;
    }
    // WASM-heap buffer: allocate in WASM, bulk-write pointer list, call native, free.
    const int pointerSizeBytes = 4; // 32-bit pointers in WASM
    final bufferPtr = (RiveWasm.allocateBuffer.callAsFunction(
            null, (val.length * pointerSizeBytes).toJS) as js.JSNumber)
        .toDartInt;
    final view = RiveWasm.heapViewU32(bufferPtr, val.length);
    for (var i = 0; i < val.length; i++) {
      view[i] = (val[i] as WebRiveInternalViewModelInstance).pointer;
    }
    RiveWasm.setViewModelInstanceListValue
        .callAsFunction(null, _pointer.toJS, bufferPtr.toJS, val.length.toJS);
    RiveWasm.deleteBuffer.callAsFunction(null, bufferPtr.toJS);
  }
}

class WebInternalViewModelInstanceAsset
    extends WebInternalViewModelInstanceValue<int>
    implements InternalViewModelInstanceAsset {
  WebInternalViewModelInstanceAsset(super.pointer);

  @override
  applyValue(int val) {
    RiveWasm.setViewModelInstanceAssetValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceAssetCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebInternalViewModelInstanceArtboard
    extends WebInternalViewModelInstanceValue<int>
    implements InternalViewModelInstanceArtboard {
  WebInternalViewModelInstanceArtboard(super.pointer);

  @override
  applyValue(int val) {
    RiveWasm.setViewModelInstanceArtboardValue
        .callAsFunction(null, _pointer.toJS, val.toJS);
  }

  @override
  getInstancePointer() {
    return (RiveWasm.setViewModelInstanceArtboardCallback.callAsFunction(
      null,
      _pointer.toJS,
    ) as js.JSNumber)
        .toDartInt;
  }
}

class WebRiveInternalDataBind extends InternalDataBind {
  int get pointer => _pointer;
  int _pointer;
  WebRiveInternalDataBind(this._pointer);

  @override
  int get dirt => (RiveWasm.riveDataBindDirt.callAsFunction(null, pointer.toJS)
          as js.JSNumber)
      .toDartInt;

  @override
  set dirt(int value) => RiveWasm.riveDataBindSetDirt
      .callAsFunction(null, pointer.toJS, value.toJS);

  @override
  int get flags =>
      (RiveWasm.riveDataBindFlags.callAsFunction(null, pointer.toJS)
              as js.JSNumber)
          .toDartInt;

  @override
  void updateSourceBinding() {
    RiveWasm.riveDataBindUpdateSourceBinding.callAsFunction(null, pointer.toJS);
  }

  @override
  void update(int dirt) {
    RiveWasm.riveDataBindUpdate.callAsFunction(null, pointer.toJS, dirt.toJS);
  }

  @override
  void dispose() {
    if (_pointer == 0) {
      return;
    }
    _pointer = 0;
  }
}

/// Web implementation of [RiveProfiler].
class WebRiveProfiler extends RiveProfiler {
  static WebRiveProfiler? _instance;
  static WebRiveProfiler get instance => _instance ??= WebRiveProfiler._();
  WebRiveProfiler._();

  @override
  bool start() {
    final fn = RiveWasm.profilerStart;
    if (fn == null) return false;
    return (fn.callAsFunction(null) as js.JSBoolean).toDart;
  }

  @override
  bool stop() {
    final fn = RiveWasm.profilerStop;
    if (fn == null) return false;
    return (fn.callAsFunction(null) as js.JSBoolean).toDart;
  }

  @override
  bool get isActive {
    final fn = RiveWasm.profilerIsActive;
    if (fn == null) return false;
    return (fn.callAsFunction(null) as js.JSBoolean).toDart;
  }

  @override
  Uint8List? dump() {
    final dumpFn = RiveWasm.profilerDump;
    final ptrFn = RiveWasm.profilerGetBufferPtr;
    final freeFn = RiveWasm.profilerFreeBuffer;
    if (dumpFn == null || ptrFn == null || freeFn == null) return null;

    final size = (dumpFn.callAsFunction(null) as js.JSNumber).toDartInt;
    if (size == 0) return null;

    final ptr = (ptrFn.callAsFunction(null) as js.JSNumber).toDartInt;
    if (ptr == 0) return null;

    // Copy buffer then clear it on native side
    // First dump has HEADER, subsequent dumps have just FRAMES
    final data = Uint8List.fromList(RiveWasm.heap(ptr, size));
    freeFn.callAsFunction(null);
    return data;
  }

  @override
  void endFrame() {
    RiveWasm.profilerEndFrame?.callAsFunction(null);
  }
}

/// Returns the web profiler instance.
RiveProfiler getRiveProfiler() => WebRiveProfiler.instance;
