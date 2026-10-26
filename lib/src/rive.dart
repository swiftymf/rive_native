import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Color, VoidCallback;

import 'package:flutter/services.dart'
    show AssetBundle, LogicalKeyboardKey, rootBundle;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:rive_native/focus.dart' as focus;
import 'package:rive_native/rive_luau.dart';
import 'package:rive_native/semantics.dart';

import '../rive_native.dart';
import 'ffi/rive_ffi.dart' if (dart.library.js_interop) 'web/rive_web.dart';

export 'package:rive_native/src/callback_handler.dart';

const _useDataBindingDeprecationMessageTextRuns =
    'Use Data Binding instead to dynamically update text runs';
const _useDataBindingDeprecationMessageSMInput =
    'Use Data Binding instead of state machine inputs for better editor and runtime control';

@internal
typedef ViewModelInstanceCreateCallback = void Function(
    InternalViewModelInstance, Uint8List);

class Rive {
  /// Advances multiple state machines in a single batch operation.
  ///
  /// More efficient than advancing each state machine individually when
  /// rendering multiple Rive animations.
  ///
  /// WARNING: Not supported on the web
  static void batchAdvance(
          Iterable<StateMachine> stateMachines, double elapsedSeconds) =>
      batchAdvanceStateMachines(stateMachines, elapsedSeconds);

  /// Advances and renders multiple state machines in a single batch operation.
  ///
  /// Combines advancing and rendering for better performance when displaying
  /// multiple Rive animations simultaneously.
  ///
  /// WARNING: Not supported on the web
  static void batchAdvanceAndRender(Iterable<StateMachine> stateMachines,
          double elapsedSeconds, Renderer renderer) =>
      batchAdvanceAndRenderStateMachines(
          stateMachines, elapsedSeconds, renderer);
}

/// Factory for creating Rive rendering objects.
///
/// - Use [Factory.rive] for the Rive renderer (recommended) for best performance and full rendering support.
/// - Use [Factory.flutter] for the built-in Flutter renderer for smaller graphics that need to integrate with other Flutter rendering.
///
/// See the [documentation](https://rive.app/docs/runtimes/flutter/flutter#specifying-a-renderer) on specifying a renderer.
abstract class Factory {
  /// Whether this factory is supported on the current platform.
  bool get isSupported => true;

  /// Returns the native pointer address for this factory, or 0 if not
  /// backed by a native factory.
  int get nativePointerAddress => 0;

  /// Decodes image bytes into a [RenderImage] for use with Rive.
  Future<RenderImage?> decodeImage(Uint8List bytes);

  /// Decodes font bytes into a [Font] for use with Rive text.
  Future<Font?> decodeFont(Uint8List bytes);

  /// Decodes audio bytes into an [AudioSource] for Rive audio playback.
  Future<AudioSource?> decodeAudio(Uint8List bytes);

  /// Returns the Flutter-based factory using Skia/Impeller for rendering.
  static Factory get flutter => getFlutterFactory();

  /// Returns the Rive factory (recommended).
  static Factory get rive {
    return getRiveFactory();
  }

  /// Checks if the given [renderer] is compatible with this factory.
  bool isValidRenderer(Renderer renderer);

  /// Creates a new [RenderPath] for use with Rive.
  RenderPath makePath([bool initEmpty = false]);

  /// Creates a new [RenderPaint] for use with Rive.
  RenderPaint makePaint();

  /// Creates a new [RenderText] for use with Rive.
  RenderText makeText();

  /* INTERNAL */

  @internal
  Future<void> completedDecodingFile(bool success);

  @internal
  VertexRenderBuffer? makeVertexBuffer(int elementCount);

  @internal
  IndexRenderBuffer? makeIndexBuffer(int elementCount);
}

/// Extension providing convenience accessors for [FileAsset] properties.
extension FileAssetExtension on FileAsset {
  /// Returns a unique filename combining the asset name, ID, and extension.
  String get uniqueFilename {
    return '$assetUniqueName.$fileExtension';
  }

  /// Returns a unique name combining the asset name and ID.
  String get assetUniqueName => '$name-$assetId';

  /// Returns the full CDN URL for this asset.
  String get url => '$cdnBaseUrl/$cdnUuid';
}

/// Callback for custom asset loading.
///
/// Return `true` if the asset was handled, `false` to use default loading.
/// The [bytes] parameter contains embedded asset data, or `null` if the asset
/// should be loaded from CDN.
typedef AssetLoaderCallback = bool Function(
    FileAsset fileAsset, Uint8List? bytes);

/// Interface for Rive file assets (images, fonts, audio).
abstract interface class FileAssetInterface {
  /// The unique identifier for this asset within the file.
  int get assetId;

  /// The name of this asset as defined in the Rive editor.
  String get name;

  /// The file extension for this asset type (e.g., "png", "ttf").
  String get fileExtension;

  /// The base URL for Rive's CDN.
  String get cdnBaseUrl;

  /// The unique CDN identifier for this asset.
  String get cdnUuid;

  /// Releases resources associated with this asset.
  void dispose();

  /* INTERNAL */

  @internal
  Factory get riveFactory;
}

/// Base class for all file assets in a Rive file.
///
/// See also: [ImageAsset], [FontAsset], [AudioAsset]
sealed class FileAsset implements FileAssetInterface {
  /// Decodes the asset from the provided [bytes].
  ///
  /// Returns `true` if decoding succeeded.
  Future<bool> decode(Uint8List bytes);
}

/// An image asset embedded in or referenced by a Rive file.
abstract class ImageAsset extends FileAsset {
  /// The width of the image in pixels.
  double get width;

  /// The height of the image in pixels.
  double get height;

  /// Sets the render image for this asset. Returns `true` if successful.
  bool renderImage(RenderImage renderImage);

  static const int coreType = 105;
}

/// A font asset embedded in or referenced by a Rive file.
abstract class FontAsset extends FileAsset {
  /// Sets the font for this asset. Returns `true` if successful.
  bool font(Font font);

  static const int coreType = 141;
}

/// An audio asset embedded in or referenced by a Rive file.
abstract class AudioAsset extends FileAsset {
  /// Sets the audio source for this asset. Returns `true` if successful.
  bool audio(AudioSource audioSource);

  static const int coreType = 406;
}

/// An unrecognized asset type in a Rive file.
abstract class UnknownAsset extends FileAsset {}

/// A loaded Rive file containing artboards, animations, and view models.
///
/// Use the static methods [File.asset], [File.url], [File.path], or
/// [File.decode] to load a Rive file.
abstract class File {
  /// Releases all resources associated with this file.
  ///
  /// Call this when you're done using the file to free memory.
  void dispose();

  /// Returns the default artboard from this file, or `null` if none exists.
  ///
  /// Set [frameOrigin] to `false` to position the artboard at its original
  /// coordinates rather than centering it at (0, 0).
  Artboard? defaultArtboard({bool frameOrigin = true});

  /// Returns the artboard with the given [name], or `null` if not found.
  ///
  /// Set [frameOrigin] to `false` to position the artboard at its original
  /// coordinates rather than centering it at (0, 0).
  Artboard? artboard(String name, {bool frameOrigin = true});

  /// Returns the artboard at the given [index], or `null` if out of bounds.
  ///
  /// Set [frameOrigin] to `false` to position the artboard at its original
  /// coordinates rather than centering it at (0, 0).
  Artboard? artboardAt(int index, {bool frameOrigin = true});

  /// Returns a bindable artboard reference for use with data binding.
  ///
  /// Use this to set an artboard property on a [ViewModelInstanceArtboard].
  ///
  /// If [viewModelInstance] is provided, the artboard will be bound to the
  /// given view model instance instead of the default one.
  ///
  /// The provided [viewModelInstance] must remain alive and valid for at least
  /// as long as the returned [BindableArtboard] is in use (for example, until
  /// it has been assigned to its target and is no longer referenced). Letting
  /// [viewModelInstance] be garbage collected, finalized, or otherwise
  /// disposed while the binding is still active may result in undefined
  /// behavior or runtime errors in the underlying native implementation.
  BindableArtboard? artboardToBind(
    String name, {
    ViewModelInstance? viewModelInstance,
  });

  /// This method is used internally and should not be called directly.
  @internal
  InternalDataContext? internalDataContext(
      int viewModelIndex, int instanceIndex);

  /// Creates a DataContext with multiple VM instances in one call.
  @internal
  InternalDataContext? internalDataContextFromInstances(
      List<int> viewModelIndices, List<int> instanceIndices);

  /// Creates a DataContext from already-created native VM instances,
  /// optionally with a parent DataContext.
  @internal
  InternalDataContext? internalDataContextFromNativeInstances(
      List<InternalViewModelInstance> instances,
      {InternalDataContext? parent});

  @internal
  InternalViewModelInstance? copyViewModelInstance(
      int viewModelIndex, int instanceIndex);

  /// Requests serialized bytes for a native view model instance (e.g. when not
  /// yet in the editor's viewModelInstanceMap). Returns null if not found.
  @internal
  Uint8List? requestSerializedViewModelInstance(
      InternalViewModelInstance instance);

  @internal
  void clearViewModelInstances();

  /// Resolves the runtime file asset index for a [ViewModelInstanceAssetImage]
  /// when its bound render image matches a file [ImageAsset].
  ///
  /// [coreAddress] is [InternalViewModelInstanceValue.instancePointerAddress]
  /// for the property (the native `ViewModelInstanceAssetImage*`).
  ///
  /// Returns `null` when unresolved (including `UINT32_MAX`).
  @internal
  int? resolveViewModelInstanceAssetImageRuntimeIndex(int coreAddress);

  /// Resolve the runtime file asset index for a data-bound font property.
  ///
  /// [coreAddress] is [InternalViewModelInstanceValue.instancePointerAddress]
  /// for the property (the native `ViewModelInstanceAssetFont*`).
  ///
  /// Returns `null` when unresolved (including `UINT32_MAX`).
  @internal
  int? resolveViewModelInstanceAssetFontRuntimeIndex(int coreAddress);

  /// Updates the scripting state (Lua VM) associated with this file.
  /// This allows reusing an existing file with a new VM without regenerating it.
  @internal
  void setScriptingState(LuauState vm);

  /// The number of view models in the Rive file
  int get viewModelCount;

  /// Returns the view model at [index], or `null` if out of bounds.
  ViewModel? viewModelByIndex(int index);

  /// Returns the view model with the given [name], or `null` if not found.
  ViewModel? viewModelByName(String name);

  /// Returns the default view model for the given [artboard].
  ViewModel? defaultArtboardViewModel(Artboard artboard);

  /// Decodes a Rive file from raw [bytes].
  ///
  /// The [riveFactory] determines the rendering backend.
  ///
  /// Provide an [assetLoader] callback to handle embedded assets manually.
  static Future<File?> decode(
    Uint8List bytes, {
    required Factory riveFactory,
    AssetLoaderCallback? assetLoader,
    LuauState? vm,
  }) async {
    final initialized = await RiveNative.init();
    assert(initialized,
        'RiveNative could not be initialized, be sure to call `await RiveNative.init()` before decoding a file.');
    return decodeRiveFile(bytes, riveFactory, assetLoader: assetLoader, vm: vm);
  }

  /// Loads a Rive file from a Flutter asset bundle.
  static Future<File?> asset(
    String bundleKey, {
    required Factory riveFactory,
    AssetBundle? bundle,
    AssetLoaderCallback? assetLoader,
  }) async {
    final bytes = await (bundle ?? rootBundle).load(
      bundleKey,
    );

    final file = await decode(
      bytes.buffer.asUint8List(),
      riveFactory: riveFactory,
      assetLoader: assetLoader,
    );
    return file;
  }

  /// Loads a Rive file from a local file system [path].
  static Future<File?> path(
    String path, {
    required Factory riveFactory,
    AssetLoaderCallback? assetLoader,
  }) async {
    final bytes = await localFileBytes(path);
    if (bytes == null) {
      return null;
    }
    return decode(
      bytes,
      riveFactory: riveFactory,
      assetLoader: assetLoader,
    );
  }

  /// Loads a Rive file from a network [url].
  ///
  /// Optional [headers] can be provided for authentication or other needs.
  static Future<File?> url(
    String url, {
    required Factory riveFactory,
    Map<String, String>? headers,
    AssetLoaderCallback? assetLoader,
  }) async {
    final res = await http.get(Uri.parse(url), headers: headers);

    return decode(
      res.bodyBytes,
      riveFactory: riveFactory,
      assetLoader: assetLoader,
    );
  }

  /// Returns a list of [DataEnum]s contained in the file.
  List<DataEnum> get enums;

  @internal
  void advanceFrameId();
}

/// A view model enum that represents a list of values.
///
/// - [name] is the name of the enum.
/// - [values] is a string list of possible enum values.
class DataEnum {
  final String name;
  final List<String> values;

  const DataEnum(this.name, this.values);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DataEnum) return false;
    return name == other.name && _listEquals(values, other.values);
  }

  @override
  int get hashCode => Object.hash(name, Object.hashAll(values));

  bool _listEquals(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  @override
  String toString() {
    return 'DataEnum{name: $name, values: $values}';
  }
}

/// The type of data that a view model property can hold.
enum DataType {
  /// None
  none,

  /// String
  string,

  /// Number
  number,

  /// Boolean
  boolean,

  /// Color
  color,

  /// List
  list,

  /// Enum
  enumType,

  /// Trigger
  trigger,

  /// View Model
  viewModel,

  /// Integer
  integer,

  /// Symbol list index
  symbolListIndex,

  /// Asset Image
  image,

  /// Artboard
  artboard,
}

/// A representation of a property in a Rive view model.
///
/// - [name] is the name of the property.
/// - [type] is the [DataType] of the property.
class ViewModelProperty {
  final String name;
  final DataType type;

  const ViewModelProperty(this.name, this.type);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ViewModelProperty) return false;
    return name == other.name && type == other.type;
  }

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() {
    return 'ViewModelProperty{name: $name, type: $type}';
  }
}

/// A Rive View Model as created in the Rive editor.
///
/// Docs: https://rive.app/docs/runtimes/data-binding
abstract interface class ViewModel {
  /// The number of properties in the view model
  int get propertyCount;

  /// The number of view model instances in the view model
  int get instanceCount;

  /// The name of the view model
  String get name;

  /// A list of [ViewModelProperty] that makes up the view model
  List<ViewModelProperty> get properties;

  /// Returns a view model instance by the given [index]
  ViewModelInstance? createInstanceByIndex(int index);

  /// Returns a view model instance by the given [name]
  ViewModelInstance? createInstanceByName(String name);

  /// Return the default view model instance
  ViewModelInstance? createDefaultInstance();

  /// Returns an empty/new view model instance
  ViewModelInstance? createInstance();

  /// Disposes of the view model and cleans up underlying native resources
  void dispose();
}

/// An instance of a Rive [ViewModel] that can be used to access and modify
/// properties in the view model.
///
/// Docs: https://rive.app/docs/runtimes/data-binding
abstract interface class ViewModelInstance
    implements ViewModelInstanceCallbacks, AdvanceRequestInterface {
  /// The name of the view model instance
  String get name;

  /// A list of [ViewModelProperty] that makes up the view model instance
  List<ViewModelProperty> get properties;

  /// Access a property instance of type [ViewModelInstance]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@template property_path}
  /// The [path] is a forward-slash-separated "/" string representing the path
  /// to the property instance.
  /// {@endtemplate}
  ViewModelInstance? viewModel(String path);

  /// Access a property instance of type [ViewModelInstanceNumber]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceNumber? number(String path);

  /// Access a property instance of type [ViewModelInstanceBoolean]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceBoolean? boolean(String path);

  /// Access a property instance of type [ViewModelInstanceColor]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ///
  ViewModelInstanceColor? color(String path);

  /// Access a property instance of type [ViewModelInstanceString]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceString? string(String path);

  /// Access a property instance of type [ViewModelInstanceTrigger]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceTrigger? trigger(String path);

  /// Access a property instance of type [ViewModelInstanceEnum]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceEnum? enumerator(String path);

  /// Access a property instance of type [ViewModelInstanceAssetImage]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceAssetImage? image(String path);

  /// Access a property instance of type [ViewModelInstanceAssetFont]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceAssetFont? font(String path);

  /// Access a property instance of type [ViewModelInstanceList]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceList? list(String path);

  /// Access a property instance of type [ViewModelInstanceArtboard]
  /// belonging to the view model instance or to a nested view model instance.
  ///
  /// {@macro property_path}
  ViewModelInstanceArtboard? artboard(String path);

  /// Disposes of the view model instance. This removes all listeners/callbacks
  /// and cleans up all underlying resources.
  ///
  /// Do not call this method if you have active view model property listeners,
  /// as these will be removed when the view model instance is disposed.
  void dispose();

  /// Indicates whether the view model instance has been disposed.
  ///
  /// After disposal, the view model instance and its associated properties
  /// become unusable.
  bool get isDisposed;
}

@protected
abstract interface class ViewModelInstanceCallbacks {
  /// Processes all callbacks for properties with attached listeners.
  ///
  /// Listeners can be attached to a [ViewModelInstanceObservableValue]
  /// property using the [addListener] method.
  ///
  /// This method should be invoked once per advance of the underlying
  /// state machine and artboard where the view model instance is bound.
  ///
  /// Typically, this method is called automatically within certain
  /// painters/widgets and should not be manually invoked in most cases.
  /// However, if you are constructing your own render loop or overriding the
  /// default behavior, ensure this is called to trigger the view model
  /// properties' listeners.
  ///
  /// To simulate certain test scenarios, you may also
  /// want to manually invoke this method in testing environments.
  void handleCallbacks();

  /* INTERNAL */

  /// This method is used internally to add a property instance to the list of
  /// properties that have listeners attached to them.
  ///
  /// This method should not be called directly, but rather through the
  /// [addListener] method of the [ViewModelInstanceObservableValue].
  @internal
  void addCallback(ViewModelInstanceObservableValue instance);

  /// This method is used internally to remove a property instance from the list
  /// of properties that have listeners attached to them.
  ///
  /// This method should not be called directly, but rather through the
  /// [removeListener] method of the [ViewModelInstanceObservableValue].
  @internal
  void removeCallback(ViewModelInstanceObservableValue instance);

  /// This method is used internally to clear all properties that have listeners
  /// attached to them.
  ///
  /// This method should not be called directly.
  @internal
  void clearCallbacks();

  /// The number of properties that have listeners attached to them.
  /// This is useful for testing purposes.
  @visibleForTesting
  int get numberOfCallbacks;
}

@protected
mixin ViewModelInstanceCallbackMixin implements ViewModelInstanceCallbacks {
  final List<ViewModelInstanceObservableValue> _propertiesWithCallbacks = [];

  @override
  void handleCallbacks() {
    for (var property in List.of(_propertiesWithCallbacks, growable: false)) {
      property.handleListeners();
    }
  }

  @override
  void addCallback(ViewModelInstanceObservableValue instance) {
    if (!_propertiesWithCallbacks.contains(instance)) {
      _propertiesWithCallbacks.add(instance);
    }
  }

  @override
  void removeCallback(ViewModelInstanceObservableValue instance) {
    _propertiesWithCallbacks.remove(instance);
  }

  @override
  void clearCallbacks() {
    final callbacksCopy = List.of(_propertiesWithCallbacks);
    _propertiesWithCallbacks.clear();
    for (final element in callbacksCopy) {
      element.clearListeners();
    }
  }

  @override
  int get numberOfCallbacks => _propertiesWithCallbacks.length;
}

@protected
abstract interface class ViewModelInstanceValue {
  @protected
  ViewModelInstance get rootViewModelInstance;
  void dispose();
}

@protected
abstract interface class ViewModelInstanceObservableValue<T>
    implements ViewModelInstanceValue {
  /// Gets the value of the property
  T get value;

  /// Sets the value of the property
  set value(T value);

  /// Returns a stream that emits the value of the property.
  ///
  /// The current value is emitted immediately when the first subscription is
  /// added (or when the first subscription is added after all previous
  /// subscriptions were cancelled). Subsequent subscribers do not receive the
  /// current value - they only receive future changes.
  ///
  /// This stream is broadcast, meaning multiple listeners can be attached
  /// and the stream will emit changes to all of them.
  ///
  /// The stream will be closed when [clearListeners] is called.
  Stream<T> get valueStream;

  /// Adds a listener/callback that will be called when the  property value
  /// changes
  void addListener(void Function(T value) callback);

  /// Removes a listener/callback from the property
  void removeListener(void Function(T value) callback);

  /// Clears all listeners from the property
  void clearListeners();

  /// Disposes of the property. This removes all listeners and cleans up all
  /// underlying resources.
  @override
  void dispose();

  /* INTERNAL */

  /// Gets the native value of the property
  ///
  /// This method is used internally and should not be called directly.
  /// Use get [value] instead.
  @internal
  T get nativeValue;

  /// Sets the native value of the property
  ///
  /// This method is used internally and should not be called directly.
  /// Use set [value] instead.
  @internal
  set nativeValue(T value);

  /// Handles all listeners attached to the property.
  ///
  /// This method should be called once per frame to ensure that the listeners
  /// are called when the property value changes.
  ///
  /// This method is used internally and should not be called directly.
  @internal
  void handleListeners();

  /// Returns whether the property value has changed since the last time the
  /// [clearChanges] method was called
  ///
  /// This method is used internally to determine whether to call the listeners
  /// attached to the property.
  @internal
  bool get hasChanged;

  /// Clears the changed flag for the property. This method should be called
  /// after the listeners have been called to ensure that the listeners are
  /// only called once per change.
  ///
  /// This method is used internally and should not be called directly.
  @internal
  void clearChanges();

  /// The number of listeners attached to the property.
  /// This is useful for testing purposes.
  @visibleForTesting
  int get numberOfListeners;
}

/// A mixin that implements the [ViewModelInstanceObservableValue] interface
/// and provides the basic functionality for handling listeners (observables)
/// and notifying them of changes. This allows users to observe changes to the
/// underlying Rive property value.
@protected
mixin ViewModelInstanceObservableValueMixin<T>
    implements ViewModelInstanceObservableValue<T> {
  List<void Function(T value)> listeners = [];
  StreamController<T>? _streamController;

  @override
  @mustCallSuper
  set value(T value) {
    nativeValue = value;
    rootViewModelInstance.requestAdvance();
  }

  @override
  @mustCallSuper
  T get value {
    return nativeValue;
  }

  @override
  Stream<T> get valueStream {
    _streamController ??= StreamController<T>.broadcast(
      onListen: _onStreamListen,
      onCancel: _onStreamCancel,
    );
    return _streamController!.stream;
  }

  /// Called when the first subscription is added to the stream.
  /// If a listener is added again later, after [_onStreamCancel] was called,
  /// this method will be called again.
  void _onStreamListen() {
    _ensureRegistered();
    // Emit current value to the first subscriber(s)
    if (_streamController != null && !_streamController!.isClosed) {
      _streamController!.add(value);
    }
  }

  /// Called when the last subscription is cancelled from the stream
  void _onStreamCancel() {
    _checkUnregister();
  }

  /// Ensures we're registered for callbacks if we have any listeners
  void _ensureRegistered() {
    final hasStreamListeners = _streamController != null &&
        !_streamController!.isClosed &&
        _streamController!.hasListener;
    final hasCallbacks = listeners.isNotEmpty;

    if (hasCallbacks || hasStreamListeners) {
      // Since we don't clean the changed flag for properties that don't have
      // listeners, we clean it the first time we add a listener to it
      clearChanges();
      rootViewModelInstance.addCallback(this);
    }
  }

  /// Checks if we should unregister from callbacks
  void _checkUnregister() {
    final hasStreamListeners = _streamController != null &&
        !_streamController!.isClosed &&
        _streamController!.hasListener;
    final hasCallbacks = listeners.isNotEmpty;

    if (!hasCallbacks && !hasStreamListeners) {
      rootViewModelInstance.removeCallback(this);
    }
  }

  @override
  void addListener(void Function(T value) callback) {
    if (listeners.contains(callback)) {
      return;
    }
    final wasEmpty = listeners.isEmpty;
    listeners.add(callback);
    if (wasEmpty) {
      _ensureRegistered();
    }
  }

  @override
  void removeListener(void Function(T value) callback) {
    listeners.remove(callback);
    _checkUnregister();
  }

  @override
  void handleListeners() {
    if (hasChanged) {
      final currentValue = value;
      clearChanges();
      // Copy the list to avoid concurrent modification if a callback removes itself
      for (var callback in List.of(listeners, growable: false)) {
        callback(currentValue);
      }
      // Emit to stream if it exists and isn't closed
      // Broadcast streams will safely ignore add() if there are no listeners
      if (_streamController != null && !_streamController!.isClosed) {
        _streamController!.add(currentValue);
      }
    }
  }

  @override
  void clearListeners() {
    listeners.clear();
    // Close and clean up stream controller
    if (_streamController != null && !_streamController!.isClosed) {
      _streamController!.close();
      _streamController = null;
    }
    rootViewModelInstance.removeCallback(this);
  }

  @override
  int get numberOfListeners => listeners.length;
}

/// A Rive view model property of type [double] that represents a number value.
abstract interface class ViewModelInstanceNumber
    implements ViewModelInstanceObservableValue<double> {}

/// A Rive view model property of type [String] that represents a string value.
abstract interface class ViewModelInstanceString
    implements ViewModelInstanceObservableValue<String> {}

/// A Rive view model property of type [bool] that represents a boolean value.
abstract interface class ViewModelInstanceBoolean
    implements ViewModelInstanceObservableValue<bool> {}

/// A Rive view model property of type [Color] that represents a color value.
abstract interface class ViewModelInstanceColor
    implements ViewModelInstanceObservableValue<Color> {}

/// A Rive view model property of type [String] that represents an enumerator
/// value.
abstract interface class ViewModelInstanceEnum
    implements ViewModelInstanceObservableValue<String> {
  /// The name of the enum (not the property name)
  String get enumType;
}

/// A Rive view model property of type [bool] that represents a trigger value.
///
/// Note the `bool` value will always be false, and is only used to represent
/// the underlying type. The property is fired by calling the [trigger] method,
/// or by setting the [value] to `true`, which will call [trigger] and
/// immediately set back to `false`.
abstract interface class ViewModelInstanceTrigger
    implements ViewModelInstanceObservableValue<bool> {
  /// Invokes the trigger for the property
  void trigger();
}

/// A Rive view model property of type [RenderImage] that represents an asset
/// image value.
abstract interface class ViewModelInstanceAssetImage
    implements ViewModelInstanceValue {
  /// Sets the value of the property.
  ///
  /// To create a [RenderImage] use the [Factory.decodeImage]
  /// method.
  ///
  /// #### Example
  ///
  /// ```dart
  /// final bytes = await rootBundle.load("assets/your_image.png");
  /// final renderImage = await rive.Factory.rive
  ///     .decodeImage(bytes.buffer.asUint8List());
  /// ```
  set value(RenderImage? value);
}

/// A Rive view model property of type [Font] that represents an asset
/// font value.
abstract interface class ViewModelInstanceAssetFont
    implements ViewModelInstanceValue {
  /// Sets the value of the property.
  ///
  /// To create a [Font] use the [Factory.decodeFont] method.
  ///
  /// #### Example
  ///
  /// ```dart
  /// final bytes = await rootBundle.load("assets/your_font.ttf");
  /// final font = await rive.Factory.rive
  ///     .decodeFont(bytes.buffer.asUint8List());
  /// ```
  set value(Font? value);
}

/// A Rive view model property of type [List<ViewModelInstance>] that represents
/// a list of view model instances.
abstract interface class ViewModelInstanceList
    implements ViewModelInstanceValue {
  /// Returns the number of view model instances in the list.
  int get length;

  /// Adds a [ViewModelInstance] to the end of the list.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// list.add(instance);
  /// ```
  ///
  /// Throws a [RangeError] if the [index] is out of bounds.
  void add(ViewModelInstance instance);

  /// Inserts a [ViewModelInstance] at the specified [index] in the list.
  ///
  /// Returns true if the instance was inserted, false if the index was out of bounds.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// list.insert(2, instance);
  /// ```
  ///
  /// Throws a [RangeError] if the [index] is out of bounds.
  bool insert(
    int index,
    ViewModelInstance instance,
  );

  /// Removes the specified [ViewModelInstance] from the list.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// list.remove(instance);
  /// ```
  ///
  /// Throws a [RangeError] if the [instance] is not in the list.
  void remove(ViewModelInstance instance);

  /// Removes the view model instance at the specified [index] from the list.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// list.removeAt(2);
  /// ```
  ///
  /// Throws a [RangeError] if the [index] is out of bounds.
  void removeAt(int index);

  /// Returns the view model instance at the specified [index] in the list.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// final instance = list.instanceAt(2);
  /// ```
  ///
  /// Throws a [RangeError] if the [index] is out of bounds.
  ViewModelInstance instanceAt(int index);

  /// Swaps the positions of two view model instances in the list at indices [a] and [b].
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// list.swap(2, 3);
  /// ```
  ///
  /// Throws a [RangeError] if the [a] or [b] is out of bounds.
  void swap(int a, int b);

  /// Returns the first view model instance in the list.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// final instance = list.first();
  /// ```
  ///
  /// Throws a [RangeError] if the list is empty.
  ViewModelInstance first();

  /// Returns the last view model instance in the list.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// final instance = list.last();
  /// ```
  ///
  /// Throws a [RangeError] if the list is empty.
  ViewModelInstance last();

  /// Returns the first view model instance in the list, or null if the list is empty.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// final instance = list.firstOrNull();
  /// ```
  ViewModelInstance? firstOrNull();

  /// Returns the last view model instance in the list, or null if the list is empty.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// final instance = list.lastOrNull();
  /// ```
  ViewModelInstance? lastOrNull();

  /// Returns the view model instance at the specified [index] in the list.
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// final instance = list[2];
  /// ```
  ///
  /// Throws a [RangeError] if the [index] is out of bounds.
  ViewModelInstance operator [](int index);

  /// Sets the view model instance at the specified [index] in the list to [value].
  ///
  /// Example:
  /// ```dart
  /// final list = viewModelInstance.list("list");
  /// list[2] = instance;
  /// ```
  ///
  /// Throws a [RangeError] if the [index] is out of bounds.
  void operator []=(int index, ViewModelInstance value);
}

/// A Rive view model property that holds a reference to an artboard.
abstract interface class ViewModelInstanceArtboard
    implements ViewModelInstanceValue {
  /// Sets the artboard value for this property.
  ///
  /// Use [File.artboardToBind] to obtain a [BindableArtboard].
  ///
  /// Example:
  /// ```dart
  /// final bindableArtboard = riveFile.artboardToBind("ArtboardB");
  /// final artboardProperty = viewModelInstance.artboard("artboardProperty");
  /// artboardProperty.value = bindableArtboard;
  /// ```
  set value(BindableArtboard value);
}

/// A Rive view model property of type [int] that represents the list index.
abstract interface class ViewModelInstanceSymbolListIndex
    implements ViewModelInstanceObservableValue<int> {}

/// A Rive artboard containing animations, state machines, and components.
///
/// Artboards are the root containers for Rive content. Use [File.artboard],
/// [File.artboardAt], or [File.defaultArtboard] to obtain an artboard instance.
abstract class Artboard {
  /// The name of this artboard as defined in the Rive editor.
  String get name;

  /// The bounding box of this artboard in its local coordinate space.
  AABB get bounds;

  /// The bounding box after layout has been applied.
  AABB get layoutBounds;

  /// The bounding box in world coordinates.
  AABB get worldBounds;

  /// Runs the GPU canvas pre-pass for this artboard and all nested artboards.
  /// Must be called after advance() and before draw() to prevent ore render
  /// passes from interleaving with the active 2D render pass (critical on
  /// Metal tile-based GPUs). No-op when no drawCanvas scripts are present.
  void drawCanvases();

  /// Returns the [LuauState] for the first drawCanvas scripted object found
  /// in this artboard or any nested artboard (recursive). Returns null when
  /// no drawCanvas scripts exist. Used to open the GPU frame before calling
  /// [drawCanvases].
  LuauState? get drawCanvasState;

  /// Draws this artboard using the provided [renderer].
  void draw(Renderer renderer);

  /// Advances the static frame ID counter. Must be called once per frame
  /// before [drawInternal] when not using [draw] (which increments it
  /// automatically). The frame ID is used by scripted paths to detect
  /// modifications between draws in the same frame.
  void advanceFrameId();

  /// Returns the default state machine, or `null` if none is set.
  StateMachine? defaultStateMachine();

  /// Returns the state machine with the given [name], or `null` if not found.
  StateMachine? stateMachine(String name);

  /// Returns the state machine at [index], or `null` if out of bounds.
  StateMachine? stateMachineAt(int index);

  /// Returns the component with the given [name], or `null` if not found.
  Component? component(String name);

  /// Returns the number of animations in this artboard.
  int animationCount();

  /// Returns the number of state machines in this artboard.
  int stateMachineCount();

  /// Get count of root FocusData nodes in this artboard.
  /// Root FocusData nodes are those without a parent FocusData within this
  /// artboard.
  int get rootFocusDataCount;

  /// Get the FocusNode for root FocusData at index.
  /// Returns null if index is out of bounds.
  focus.FocusNode? rootFocusNodeAt(int index);

  /// Set an external parent FocusNode for this artboard's root-level focus
  /// nodes. This is used when the artboard is nested inside another artboard
  /// that has a FocusData in its hierarchy. The external parent allows focus
  /// nodes in this artboard to be children of a FocusData in the host
  /// artboard, even across artboard boundaries.
  void setExternalParentFocusNode(focus.FocusNode? node);

  /// Build the focus tree for this artboard using a parent FocusNode.
  /// The FocusManager is derived from the parent node's manager() reference.
  /// This is a convenience method for nested artboards - pass the parent's
  /// FocusNode and the artboard will automatically register its focus nodes
  /// with the correct manager.
  void buildFocusTreeWithParent(focus.FocusNode? parentNode);

  /// Get all root FocusNodes from this artboard.
  /// These are FocusNodes from FocusData objects that don't have a parent
  /// FocusData within this artboard.
  List<focus.FocusNode> getRootFocusNodes() {
    final nodes = <focus.FocusNode>[];
    for (int i = 0; i < rootFocusDataCount; i++) {
      final node = rootFocusNodeAt(i);
      if (node != null) {
        nodes.add(node);
      }
    }
    return nodes;
  }

  /// Whether the artboard origin is at frame center (true) or original
  /// position.
  bool get frameOrigin;

  /// Sets whether the artboard origin is at frame center or original position.
  set frameOrigin(bool value);

  /// Returns the animation at [index].
  Animation animationAt(int index);

  /// Returns the animation with the given [name], or `null` if not found.
  Animation? animationNamed(String name);

  /// Releases all resources associated with this artboard.
  void dispose();

  /// Get a text run value with [runName] at optional [path].
  @Deprecated(_useDataBindingDeprecationMessageTextRuns)
  String getText(String runName, {String? path});

  /// Set a text run value with [runName] at optional [path] to [value].
  @Deprecated(_useDataBindingDeprecationMessageTextRuns)
  bool setText(String runName, String value, {String? path});

  /// Get all text runs in the artboard - including nested artboards (components)
  ///
  /// {@template unsafeApiWarning}
  /// **WARNING: This API could be unsafe to use and will be removed in a
  /// future version.** Use with caution. Replace with [Data Binding](https://rive.app/docs/runtimes/data-binding).
  /// {@endtemplate}
  @Deprecated(_useDataBindingDeprecationMessageTextRuns)
  List<TextValueRunRuntime> get textRuns;

  /// The transformation matrix applied when rendering.
  Mat2D get renderTransform;

  /// Sets the render transformation matrix.
  set renderTransform(Mat2D value);

  /// Advances the artboard animation by [seconds].
  ///
  /// Use [flags] to control advance behavior (defaults to advancing nested
  /// artboards and marking as new frame).
  bool advance(double seconds, {int flags = 9});

  /// The opacity of the artboard (0.0 to 1.0).
  double get opacity;

  /// Sets the opacity of the artboard (0.0 to 1.0).
  set opacity(double value);

  /// Sets an opacity imposed by a host (e.g. a nested-artboard host) on this
  /// instance. Kept separate from [opacity] so the artboard's own (animated /
  /// data-bound) opacity is preserved; the two are multiplied together when the
  /// artboard propagates opacity to its contents.
  set hostOpacity(double value);

  /// The width from bounds. See [bounds].
  double get widthBounds => bounds.width;

  /// The height from bounds. See [bounds].
  double get heightBounds => bounds.height;

  /// The current width of the artboard.
  double get width;

  /// The current height of the artboard.
  double get height;

  /// The original width of the artboard as defined in the editor.
  double get widthOriginal;

  /// The original height of the artboard as defined in the editor.
  double get heightOriginal;

  /// Sets the width of the artboard.
  set width(double value);

  /// Sets the height of the artboard.
  set height(double value);

  /// The artboard's origin X factor (0-1). For a mounted nested artboard this
  /// can be overridden to reposition its origin.
  double get originX;

  /// Sets the artboard's origin X factor (0-1).
  set originX(double value);

  /// The artboard's origin Y factor (0-1).
  double get originY;

  /// Sets the artboard's origin Y factor (0-1).
  set originY(double value);

  /// Resets the artboard size to its original dimensions.
  void resetArtboardSize();

  /// Binds the provided [viewModelInstance] to the artboard
  ///
  /// Docs: https://rive.app/docs/runtimes/data-binding
  void bindViewModelInstance(ViewModelInstance viewModelInstance);

  /// The factory that was used to load this artboard.
  Factory? get riveFactory;

  /* INTERNAL */

  @internal
  void drawInternal(Renderer renderer);
  @internal
  void addToRenderPath(RenderPath renderPath, Mat2D transform);
  @internal
  void reset();
  @internal
  void widthOverride(double width, int widthUnitValue, bool isRow);
  @internal
  void heightOverride(double height, int heightUnitValue, bool isRow);
  @internal
  void parentIsRow(bool isRow);
  @internal
  void widthIntrinsicallySizeOverride(bool intrinsic);
  @internal
  void heightIntrinsicallySizeOverride(bool intrinsic);
  @internal
  void updateLayoutBounds(bool animate);
  @internal
  void cascadeLayoutStyle(
      int direction,
      int interpolationType,
      double interpolationTime,
      int interpolatorTypeKey,
      double p0,
      double p1,
      double p2,
      double p3);

  /// Applies [cascadeLayoutStyle] to every artboard in [artboards] in a single
  /// FFI/WASM round trip. The implementation packs native pointers into a
  /// scratch buffer (reused across calls) and crosses the boundary once.
  @internal
  void cascadeLayoutStyleBatch(
      List<Artboard> artboards,
      int direction,
      int interpolationType,
      double interpolationTime,
      int interpolatorTypeKey,
      double p0,
      double p1,
      double p2,
      double p3);

  @internal
  void cascadeCollapse(bool collapse);

  /// Applies [cascadeCollapse] to every artboard in [artboards] in a single
  /// FFI/WASM round trip. The implementation packs native pointers into a
  /// scratch buffer (reused across calls) and crosses the boundary once.
  @internal
  void cascadeCollapseBatch(List<Artboard> artboards, bool collapse);

  @internal
  bool updatePass();
  @internal
  bool hasComponentDirt();

  @useResult
  @internal
  CallbackHandler onLayoutChanged(void Function() callback);

  @useResult
  @internal
  CallbackHandler onEvent(void Function(int) callback);

  @useResult
  @internal
  CallbackHandler onTestBounds(int Function(Vec2D pos, bool skip) callback);

  @useResult
  @internal
  CallbackHandler onIsAncestor(int Function(int artboardId) callback);

  @useResult
  @internal
  CallbackHandler onRootTransform(
      double Function(Vec2D pos, bool xAxis) callback);

  /// Callback for when a layout style of a nested artboard has changed.
  @useResult
  @internal
  CallbackHandler onLayoutDirty(void Function() callback);

  /// Callback for when a layout style of a nested artboard has changed.
  @useResult
  @internal
  CallbackHandler onTransformDirty(void Function() callback);

  @internal
  dynamic takeLayoutNode();
  @internal
  void syncStyleChanges();
  void addedToHost();

  /// This method is used internally and should not be called directly.
  /// Instead, use the [bindViewModelInstance] method.
  @internal
  void internalBindViewModelInstance(InternalViewModelInstance instance,
      InternalDataContext? dataContext, bool isRoot);

  /// This method is used internally and should not be called directly.
  /// Instead, use the [bindViewModelInstance] method.
  @internal
  void internalSetDataContext(InternalDataContext dataContext);

  /// This method is used internally and should not be called directly.
  @internal
  InternalDataContext? get internalGetDataContext;

  /// This method is used internally and should not be called directly.
  @internal
  void internalClearDataContext();

  /// This method is used internally and should not be called directly.
  @internal
  void internalUnbind();

  /// This method is used internally and should not be called directly.
  @internal
  void internalUpdateDataBinds();

  /// Get the native pointer address for this artboard.
  /// Used internally for comparing artboard identity across FFI boundaries.
  /// Returns null on platforms that don't support this (e.g., web).
  @internal
  int? get nativePointerAddress;

  /// Get a unique identifier for this artboard instance.
  /// Used for matching artboards across FFI boundaries (e.g., in scroll-into-view
  /// callbacks from native code).
  /// Returns null on platforms that don't support this.
  @internal
  int? get artboardUniqueId;
}

/// A reference to an artboard that can be bound to a view model property.
///
/// Obtain via [File.artboardToBind] and assign to [ViewModelInstanceArtboard.value].
abstract class BindableArtboard {
  /// Releases native resources associated with this bindable artboard.
  void dispose();
}

/// This class is used internally and should not be used directly.
@internal
abstract class InternalDataBind {
  void update(int dirt);
  void updateSourceBinding();
  int get dirt;
  set dirt(int value);
  int get flags;
  void dispose();
}

/// This class is used internally and should not be used directly.
@internal
abstract class InternalDataContext {
  InternalViewModelInstance get viewModelInstance;
  InternalViewModelInstance? viewModelInstanceAt(int index);
  void dispose();
}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceValue] instead.
@internal
abstract class InternalViewModelInstanceValue<T> {
  int instancePointerAddress = 0;
  bool suppressCallback = false;
  void dispose();
  void advanced();
  set value(T val);
  set nativeValue(T val);
  void onChanged(void Function(T value) callback);
}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceNumber] instead.
@internal
abstract interface class InternalViewModelInstanceNumber
    extends InternalViewModelInstanceValue<double> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceBoolean] instead.
@internal
abstract interface class InternalViewModelInstanceBoolean
    extends InternalViewModelInstanceValue<bool> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceColor] instead.
@internal
abstract interface class InternalViewModelInstanceColor
    extends InternalViewModelInstanceValue<int> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceString] instead.
@internal
abstract interface class InternalViewModelInstanceString
    extends InternalViewModelInstanceValue<String> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceTrigger] instead.
@internal
abstract interface class InternalViewModelInstanceTrigger
    extends InternalViewModelInstanceValue<int> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceInteger] instead.
@internal
abstract interface class InternalViewModelInstanceEnum
    extends InternalViewModelInstanceValue<int> {}

/// This class is used internally and should not be used directly.
@internal
abstract interface class InternalViewModelInstanceAsset
    extends InternalViewModelInstanceValue<int> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceArtboard] instead.
@internal
abstract interface class InternalViewModelInstanceArtboard
    extends InternalViewModelInstanceValue<int> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstance] instead.
@internal
abstract interface class InternalViewModelInstanceViewModel
    implements InternalViewModelInstanceValue<InternalViewModelInstance?> {
  InternalViewModelInstance get referenceViewModelInstance;
}

/// This class is used internally and should not be used directly.
@internal
abstract interface class InternalViewModelInstanceList
    implements
        InternalViewModelInstanceValue<List<InternalViewModelInstance>?> {
  InternalViewModelInstance referenceViewModelInstance(int index);
  int size();
}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstanceSymbolListIndex] instead.
@internal
abstract interface class InternalViewModelInstanceSymbolListIndex
    extends InternalViewModelInstanceValue<int> {}

/// This class is used internally and should not be used directly.
///
/// Use [ViewModelInstance] instead.
@internal
abstract class InternalViewModelInstance {
  InternalViewModelInstanceViewModel propertyViewModel(
      int index, String name, int propertyType);
  InternalViewModelInstanceNumber propertyNumber(
      int index, String name, int propertyType);
  InternalViewModelInstanceBoolean propertyBoolean(
      int index, String name, int propertyType);
  InternalViewModelInstanceColor propertyColor(
      int index, String name, int propertyType);
  InternalViewModelInstanceString propertyString(
      int index, String name, int propertyType);
  InternalViewModelInstanceTrigger propertyTrigger(
      int index, String name, int propertyType);
  InternalViewModelInstanceEnum propertyEnum(
      int index, String name, int propertyType);
  InternalViewModelInstanceList propertyList(
      int index, String name, int propertyType);
  InternalViewModelInstanceSymbolListIndex propertySymbolListIndex(
      int index, String name, int propertyType);
  InternalViewModelInstanceAsset propertyAsset(
      int index, String name, int propertyType);
  InternalViewModelInstanceArtboard propertyArtboard(
      int index, String name, int propertyType);

  /// Prunes this instance down to only the given runtime property ids, removing
  /// every other property value. Used to turn a full copy of a nested-artboard
  /// override instance into a sparse instance containing only the
  /// explicitly-overridden properties.
  void pruneToProperties(List<int> keepPropertyIds);

  String uniqueId();
  void dispose();
}

/// A Rive animation that can be played on an artboard.
///
/// Use [Artboard.animationAt] or [Artboard.animationNamed] to obtain an
/// animation instance.
abstract class Animation {
  /// The name of this animation.
  String get name;

  /// Advances the animation by [elapsedSeconds].
  ///
  /// Returns `true` if the animation is still playing.
  bool advance(double elapsedSeconds);

  /// Advances the animation and applies it to the artboard.
  ///
  /// Returns `true` if the animation is still playing.
  bool advanceAndApply(double elapsedSeconds);

  /// Applies the animation to the artboard with the given [mix] factor.
  ///
  /// A [mix] of 1.0 fully applies the animation, while 0.0 has no effect.
  void apply({double mix = 1.0});

  /// Releases resources associated with this animation.
  void dispose();

  /// The current playback time in seconds.
  double get time;

  /// The total duration of the animation in seconds.
  double get duration;

  /// Sets the playback time in seconds.
  set time(double value);

  /// Converts a global time to the animation's local time.
  double globalToLocalTime(double seconds);
}

/// Result of a hit test or pointer event on a state machine.
enum HitResult {
  /// No interactive element was hit.
  none,

  /// A transparent interactive element was hit.
  hit,

  /// An opaque interactive element was hit.
  hitOpaque,
}

/// Keyboard modifier keys for input events.
enum KeyModifiers {
  /// Shift key modifier.
  shift,

  /// Control key modifier.
  ctrl,

  /// Alt/Option key modifier.
  alt,

  /// Meta/Command key modifier.
  meta,
}

/// Keyboard key codes for input events.
enum Key {
  space(32),
  apostrophe(39),
  comma(44),
  minus(45),
  period(46),
  slash(47),
  key0(48),
  key1(49),
  key2(50),
  key3(51),
  key4(52),
  key5(53),
  key6(54),
  key7(55),
  key8(56),
  key9(57),
  semicolon(59),
  equal(61),
  a(65),
  b(66),
  c(67),
  d(68),
  e(69),
  f(70),
  g(71),
  h(72),
  i(73),
  j(74),
  k(75),
  l(76),
  m(77),
  n(78),
  o(79),
  p(80),
  q(81),
  r(82),
  s(83),
  t(84),
  u(85),
  v(86),
  w(87),
  x(88),
  y(89),
  z(90),
  leftBracket(91),
  backslash(92),
  rightBracket(93),
  graveAccent(96),
  world1(161),
  world2(162),
  escape(256),
  enter(257),
  tab(258),
  backspace(259),
  insert(260),
  deleteKey(261),
  right(262),
  left(263),
  down(264),
  up(265),
  pageUp(266),
  pageDown(267),
  home(268),
  end(269),
  capsLock(280),
  scrollLock(281),
  numLock(282),
  printScreen(283),
  pause(284),
  f1(290),
  f2(291),
  f3(292),
  f4(293),
  f5(294),
  f6(295),
  f7(296),
  f8(297),
  f9(298),
  f10(299),
  f11(300),
  f12(301),
  f13(302),
  f14(303),
  f15(304),
  f16(305),
  f17(306),
  f18(307),
  f19(308),
  f20(309),
  f21(310),
  f22(311),
  f23(312),
  f24(313),
  f25(314),
  kp0(320),
  kp1(321),
  kp2(322),
  kp3(323),
  kp4(324),
  kp5(325),
  kp6(326),
  kp7(327),
  kp8(328),
  kp9(329),
  kpDecimal(330),
  kpDivide(331),
  kpMultiply(332),
  kpSubtract(333),
  kpAdd(334),
  kpEnter(335),
  kpEqual(336),
  leftShift(340),
  leftControl(341),
  leftAlt(342),
  leftSuper(343),
  rightShift(344),
  rightControl(345),
  rightAlt(346),
  rightSuper(347),
  menu(348);

  final int value;
  const Key(this.value);

  static final from = {
    32: space,
    39: apostrophe,
    44: comma,
    45: minus,
    46: period,
    47: slash,
    48: key0,
    49: key1,
    50: key2,
    51: key3,
    52: key4,
    53: key5,
    54: key6,
    55: key7,
    56: key8,
    57: key9,
    59: semicolon,
    61: equal,
    65: a,
    66: b,
    67: c,
    68: d,
    69: e,
    70: f,
    71: g,
    72: h,
    73: i,
    74: j,
    75: k,
    76: l,
    77: m,
    78: n,
    79: o,
    80: p,
    81: q,
    82: r,
    83: s,
    84: t,
    85: u,
    86: v,
    87: w,
    88: x,
    89: y,
    90: z,
    91: leftBracket,
    92: backslash,
    93: rightBracket,
    96: graveAccent,
    161: world1,
    162: world2,
    256: escape,
    257: enter,
    258: tab,
    259: backspace,
    260: insert,
    261: deleteKey,
    262: right,
    263: left,
    264: down,
    265: up,
    266: pageUp,
    267: pageDown,
    268: home,
    269: end,
    280: capsLock,
    281: scrollLock,
    282: numLock,
    283: printScreen,
    284: pause,
    290: f1,
    291: f2,
    292: f3,
    293: f4,
    294: f5,
    295: f6,
    296: f7,
    297: f8,
    298: f9,
    299: f10,
    300: f11,
    301: f12,
    302: f13,
    303: f14,
    304: f15,
    305: f16,
    306: f17,
    307: f18,
    308: f19,
    309: f20,
    310: f21,
    311: f22,
    312: f23,
    313: f24,
    314: f25,
    320: kp0,
    321: kp1,
    322: kp2,
    323: kp3,
    324: kp4,
    325: kp5,
    326: kp6,
    327: kp7,
    328: kp8,
    329: kp9,
    330: kpDecimal,
    331: kpDivide,
    332: kpMultiply,
    333: kpSubtract,
    334: kpAdd,
    335: kpEnter,
    336: kpEqual,
    340: leftShift,
    341: leftControl,
    342: leftAlt,
    343: leftSuper,
    344: rightShift,
    345: rightControl,
    346: rightAlt,
    347: rightSuper,
    348: menu,
  };

  static Key? fromLogicalKey(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.space:
        return Key.space;
      case LogicalKeyboardKey.quoteSingle:
        return Key.apostrophe;
      case LogicalKeyboardKey.comma:
        return Key.comma;
      case LogicalKeyboardKey.minus:
        return Key.minus;
      case LogicalKeyboardKey.period:
        return Key.period;
      case LogicalKeyboardKey.slash:
        return Key.slash;
      case LogicalKeyboardKey.digit0:
        return Key.key0;
      case LogicalKeyboardKey.digit1:
        return Key.key1;
      case LogicalKeyboardKey.digit2:
        return Key.key2;
      case LogicalKeyboardKey.digit3:
        return Key.key3;
      case LogicalKeyboardKey.digit4:
        return Key.key4;
      case LogicalKeyboardKey.digit5:
        return Key.key5;
      case LogicalKeyboardKey.digit6:
        return Key.key6;
      case LogicalKeyboardKey.digit7:
        return Key.key7;
      case LogicalKeyboardKey.digit8:
        return Key.key8;
      case LogicalKeyboardKey.digit9:
        return Key.key9;
      case LogicalKeyboardKey.semicolon:
        return Key.semicolon;
      case LogicalKeyboardKey.equal:
        return Key.equal;
      case LogicalKeyboardKey.keyA:
        return Key.a;
      case LogicalKeyboardKey.keyB:
        return Key.b;
      case LogicalKeyboardKey.keyC:
        return Key.c;
      case LogicalKeyboardKey.keyD:
        return Key.d;
      case LogicalKeyboardKey.keyE:
        return Key.e;
      case LogicalKeyboardKey.keyF:
        return Key.f;
      case LogicalKeyboardKey.keyG:
        return Key.g;
      case LogicalKeyboardKey.keyH:
        return Key.h;
      case LogicalKeyboardKey.keyI:
        return Key.i;
      case LogicalKeyboardKey.keyJ:
        return Key.j;
      case LogicalKeyboardKey.keyK:
        return Key.k;
      case LogicalKeyboardKey.keyL:
        return Key.l;
      case LogicalKeyboardKey.keyM:
        return Key.m;
      case LogicalKeyboardKey.keyN:
        return Key.n;
      case LogicalKeyboardKey.keyO:
        return Key.o;
      case LogicalKeyboardKey.keyP:
        return Key.p;
      case LogicalKeyboardKey.keyQ:
        return Key.q;
      case LogicalKeyboardKey.keyR:
        return Key.r;
      case LogicalKeyboardKey.keyS:
        return Key.s;
      case LogicalKeyboardKey.keyT:
        return Key.t;
      case LogicalKeyboardKey.keyU:
        return Key.u;
      case LogicalKeyboardKey.keyV:
        return Key.v;
      case LogicalKeyboardKey.keyW:
        return Key.w;
      case LogicalKeyboardKey.keyX:
        return Key.x;
      case LogicalKeyboardKey.keyY:
        return Key.y;
      case LogicalKeyboardKey.keyZ:
        return Key.z;
      case LogicalKeyboardKey.bracketLeft:
        return Key.leftBracket;
      case LogicalKeyboardKey.backslash:
        return Key.backslash;
      case LogicalKeyboardKey.bracketRight:
        return Key.rightBracket;
      case LogicalKeyboardKey.backquote:
        return Key.graveAccent;
      // case LogicalKeyboardKey.unknown:
      //   return Key.world1;
      // case LogicalKeyboardKey.unknown:
      //   return Key.world2;
      case LogicalKeyboardKey.escape:
        return Key.escape;
      case LogicalKeyboardKey.enter:
        return Key.enter;
      case LogicalKeyboardKey.tab:
        return Key.tab;
      case LogicalKeyboardKey.backspace:
        return Key.backspace;
      case LogicalKeyboardKey.insert:
        return Key.insert;
      case LogicalKeyboardKey.delete:
        return Key.deleteKey;
      case LogicalKeyboardKey.arrowRight:
        return Key.right;
      case LogicalKeyboardKey.arrowLeft:
        return Key.left;
      case LogicalKeyboardKey.arrowDown:
        return Key.down;
      case LogicalKeyboardKey.arrowUp:
        return Key.up;
      case LogicalKeyboardKey.pageUp:
        return Key.pageUp;
      case LogicalKeyboardKey.pageDown:
        return Key.pageDown;
      case LogicalKeyboardKey.home:
        return Key.home;
      case LogicalKeyboardKey.end:
        return Key.end;
      case LogicalKeyboardKey.capsLock:
        return Key.capsLock;
      case LogicalKeyboardKey.scrollLock:
        return Key.scrollLock;
      case LogicalKeyboardKey.numLock:
        return Key.numLock;
      case LogicalKeyboardKey.printScreen:
        return Key.printScreen;
      case LogicalKeyboardKey.pause:
        return Key.pause;
      case LogicalKeyboardKey.f1:
        return Key.f1;
      case LogicalKeyboardKey.f2:
        return Key.f2;
      case LogicalKeyboardKey.f3:
        return Key.f3;
      case LogicalKeyboardKey.f4:
        return Key.f4;
      case LogicalKeyboardKey.f5:
        return Key.f5;
      case LogicalKeyboardKey.f6:
        return Key.f6;
      case LogicalKeyboardKey.f7:
        return Key.f7;
      case LogicalKeyboardKey.f8:
        return Key.f8;
      case LogicalKeyboardKey.f9:
        return Key.f9;
      case LogicalKeyboardKey.f10:
        return Key.f10;
      case LogicalKeyboardKey.f11:
        return Key.f11;
      case LogicalKeyboardKey.f12:
        return Key.f12;
      case LogicalKeyboardKey.f13:
        return Key.f13;
      case LogicalKeyboardKey.f14:
        return Key.f14;
      case LogicalKeyboardKey.f15:
        return Key.f15;
      case LogicalKeyboardKey.f16:
        return Key.f16;
      case LogicalKeyboardKey.f17:
        return Key.f17;
      case LogicalKeyboardKey.f18:
        return Key.f18;
      case LogicalKeyboardKey.f19:
        return Key.f19;
      case LogicalKeyboardKey.f20:
        return Key.f20;
      case LogicalKeyboardKey.f21:
        return Key.f21;
      case LogicalKeyboardKey.f22:
        return Key.f22;
      case LogicalKeyboardKey.f23:
        return Key.f23;
      case LogicalKeyboardKey.f24:
        return Key.f24;
      // case LogicalKeyboardKey.f25:
      //   return Key.f25;
      case LogicalKeyboardKey.numpad0:
        return Key.kp0;
      case LogicalKeyboardKey.numpad1:
        return Key.kp1;
      case LogicalKeyboardKey.numpad2:
        return Key.kp2;
      case LogicalKeyboardKey.numpad3:
        return Key.kp3;
      case LogicalKeyboardKey.numpad4:
        return Key.kp4;
      case LogicalKeyboardKey.numpad5:
        return Key.kp5;
      case LogicalKeyboardKey.numpad6:
        return Key.kp6;
      case LogicalKeyboardKey.numpad7:
        return Key.kp7;
      case LogicalKeyboardKey.numpad8:
        return Key.kp8;
      case LogicalKeyboardKey.numpad9:
        return Key.kp9;
      case LogicalKeyboardKey.numpadDecimal:
        return Key.kpDecimal;
      case LogicalKeyboardKey.numpadDivide:
        return Key.kpDivide;
      case LogicalKeyboardKey.numpadMultiply:
        return Key.kpMultiply;
      case LogicalKeyboardKey.numpadSubtract:
        return Key.kpSubtract;
      case LogicalKeyboardKey.numpadAdd:
        return Key.kpAdd;
      case LogicalKeyboardKey.numpadEnter:
        return Key.kpEnter;
      case LogicalKeyboardKey.numpadEqual:
        return Key.kpEqual;
      case LogicalKeyboardKey.shiftLeft:
        return Key.leftShift;
      case LogicalKeyboardKey.controlLeft:
        return Key.leftControl;
      case LogicalKeyboardKey.altLeft:
        return Key.leftAlt;
      case LogicalKeyboardKey.metaLeft:
        return Key.leftSuper;
      case LogicalKeyboardKey.shiftRight:
        return Key.rightShift;
      case LogicalKeyboardKey.controlRight:
        return Key.rightControl;
      case LogicalKeyboardKey.altRight:
        return Key.rightAlt;
      case LogicalKeyboardKey.metaRight:
        return Key.rightSuper;
      case LogicalKeyboardKey.mediaTopMenu:
        return Key.menu;
      default:
        return null;
    }
  }
}

/// Semantic action types that can be fired on a semantic node.
/// Values match the C++ SemanticActionType enum.
///
/// Order must match the C++ SemanticActionType enum (index).
enum SemanticActionType {
  tap,
  increase,
  decrease,
}

/// Opaque handle to a runtime-owned `ListenerInvocation` built from a
/// single gamepad record. Use this to dispatch the same invocation to
/// multiple [StateMachine] instances without rebuilding it each time.
///
/// The handle owns native memory — call [dispose] exactly once after the
/// final dispatch in a batch. `dispose()` is idempotent.
abstract class GamepadInvocationHandle {
  /// Create a handle from raw fields. [kind] is 0 (connected), 1 (event),
  /// or 2 (disconnected). [changeKind], [changeIndex], and [changeValue]
  /// are only consumed when [kind] is 1.
  static GamepadInvocationHandle make({
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
    return makeGamepadInvocationHandle(
      kind: kind,
      deviceId: deviceId,
      buttonMask: buttonMask,
      buttonValues: buttonValues,
      axes: axes,
      mapping: mapping,
      changeKind: changeKind,
      changeIndex: changeIndex,
      changeValue: changeValue,
    );
  }

  void dispose();
}

/// A Rive state machine that drives animations based on inputs and logic.
///
/// State machines provide interactive control over animations. Obtain via
/// [Artboard.stateMachine], [Artboard.stateMachineAt], or
/// [Artboard.defaultStateMachine].
abstract class StateMachine
    implements EventListenerInterface, AdvanceRequestInterface {
  ViewModelInstance? _boundRuntimeViewModelInstance;

  /// The name of this state machine.
  String get name;

  /// Advances the state machine by [elapsedSeconds].
  ///
  /// Set [newFrame] to `true` when this is a new render frame.
  /// Returns `true` if the state machine needs further advances.
  bool advance(double elapsedSeconds, bool newFrame);

  /// Advances the state machine and applies changes to the artboard.
  ///
  /// Returns `true` if the state machine needs further advances.
  bool advanceAndApply(double elapsedSeconds);

  /// Releases resources associated with this state machine.
  @mustCallSuper
  void dispose() {
    _boundRuntimeViewModelInstance
        ?.removeAdvanceRequestListener(requestAdvance);
    removeAllAdvanceRequestListeners();
  }

  /// Get the focus manager for this state machine.
  /// Returns the active focus manager (external if set, internal otherwise).
  focus.FocusManager? get focusManager;

  /// Returns a list of all inputs in the state machine.
  @Deprecated(_useDataBindingDeprecationMessageSMInput)
  List<Input> get inputs {
    final inputs = <Input>[];
    for (var i = 0;; i++) {
      final input = inputAt(i);
      if (input == null) break;
      inputs.add(input);
    }
    return inputs;
  }

  /// Retrieve a number input from the state machine with the given [name].
  /// Get/set the [NumberInput.value] of the input.
  ///
  /// ```dart
  /// final number = stateMachine.number('numberInput');
  /// if (number != null) {
  ///  print(number.value);
  ///  number.value = 42;
  /// }
  /// ```
  /// {@template smi_input_template}
  /// Optionally provide a [path] to access a nested input.
  ///
  /// Docs: https://rive.app/docs/runtimes/state-machines
  /// {@endtemplate}
  @Deprecated(_useDataBindingDeprecationMessageSMInput)
  NumberInput? number(String name, {String? path});

  /// Retrieve a boolean input from the state machine with the given [name].
  /// Get/set the [BooleanInput.value] of the input.
  ///
  /// ```dart
  /// final boolean = stateMachine.boolean('booleanInput');
  /// if (boolean != null) {
  ///   print(boolean.value);
  ///   boolean.value = true;
  /// }
  /// ```
  ///
  /// {@macro smi_input_template}
  @Deprecated(_useDataBindingDeprecationMessageSMInput)
  BooleanInput? boolean(String name, {String? path});

  /// Retrieve a trigger input from the state machine with the given [name].
  /// Trigger the input by calling [TriggerInput.fire].
  ///
  /// ```dart
  /// final trigger = stateMachine.trigger('triggerInput');
  /// if (trigger != null) {
  ///  trigger.fire();
  /// }
  /// ```
  ///
  /// {@macro smi_input_template}
  @Deprecated(_useDataBindingDeprecationMessageSMInput)
  TriggerInput? trigger(String name, {String? path});
  @Deprecated(_useDataBindingDeprecationMessageSMInput)
  Input? inputAt(int index);

  /// The view model instance that is bound to the state machine.
  ViewModelInstance? get boundRuntimeViewModelInstance =>
      _boundRuntimeViewModelInstance;

  /// Returns a list of events that have been reported by the state machine.
  List<Event> reportedEvents();

  /// Tests if the given [position] hits any interactive element.
  ///
  /// Returns `true` if the given [position] hits any interactive element.
  bool hitTest(Vec2D position);

  /// Notifies the state machine of a pointer down event at [position].
  HitResult pointerDown(Vec2D position, {int pointerId = 0});

  /// Notifies the state machine of a pointer move event at [position].
  HitResult pointerMove(Vec2D position, {double? timeStamp, int pointerId = 0});

  /// Notifies the state machine of a pointer up event at [position].
  HitResult pointerUp(Vec2D position, {int pointerId = 0});

  /// Notifies the state machine that the pointer exited at [position].
  HitResult pointerExit(Vec2D position, {int pointerId = 0});

  /// Notifies the state machine of a drag start event at [position].
  HitResult dragStart(Vec2D position, {double? timeStamp});

  /// Notifies the state machine of a drag end event at [position].
  HitResult dragEnd(Vec2D position, {double? timeStamp});

  /// Submit a binary batch of gamepad records (connected/update/disconnected)
  /// using the wire format defined in `gamepad_batch.hpp`. Returns `false`
  /// if the batch is malformed or rejected by the runtime.
  bool submitGamepadsFromBuffer(Uint8List buffer);

  /// Dispatch a pre-built gamepad invocation to this state machine. The
  /// embedder owns [handle] — dispose it after dispatching to every target
  /// in the batch.
  void dispatchGamepadInvocation(GamepadInvocationHandle handle);

  /// Enable semantics for this state machine. Creates the internal semantic
  /// manager and builds the semantic tree. No-op if already enabled.
  @experimental
  @internal
  void enableSemantics();

  /// Returns the semantic diff since the last call.
  /// Returns an empty diff if semantics is not enabled or nothing changed.
  @experimental
  @internal
  SemanticsDiff drainSemanticsDiff();

  /// Request focus on the FocusData sibling of the SemanticData that owns
  /// the given semantic node ID. Returns true if focus was set.
  @experimental
  @internal
  bool focusSemanticNode(int semanticNodeId);

  /// Fires a semantic action on the semantic node with the given
  /// [semanticNodeId].
  void fireSemanticAction(int semanticNodeId, SemanticActionType actionType);

  /// Binds the provided [viewModelInstance] to the state machine
  ///
  /// Docs: https://rive.app/docs/runtimes/data-binding
  @mustCallSuper
  void bindViewModelInstance(ViewModelInstance viewModelInstance) {
    _boundRuntimeViewModelInstance
        ?.removeAdvanceRequestListener(requestAdvance);
    _boundRuntimeViewModelInstance = viewModelInstance;
    viewModelInstance.addAdvanceRequestListener(requestAdvance);
  }

  /// Registers a callback that is invoked when a layer state change occurs
  /// during [advanceAndApply].
  ///
  /// The callback receives the state name (animation name for animation
  /// states, or a type label such as "entry", "exit", "any", "blend", etc.).
  ///
  /// Returns a [CallbackHandler] that removes this listener when closed.
  ///
  /// This functionality is deprecated and will be removed in a future version.
  /// It is only exposed to facilitate the transition to data binding.
  @useResult
  @internal
  @Deprecated('Use data binding instead')
  CallbackHandler onStateChanged(void Function(String stateName) callback);

  /* INTERNAL */

  @internal
  CallbackHandler onDataBindChanged(Function() callback);
  @useResult
  @internal
  CallbackHandler onInputChanged(Function(int index) callback);
  @internal
  bool get isDone;

  /// This method is used internally and should not be called directly.
  /// Instead, use the [bindViewModelInstance] method.
  @internal
  void internalBindViewModelInstance(InternalViewModelInstance instance);

  /// This method is used internally and should not be called directly.
  /// Instead, use the [bindViewModelInstance] method.
  @internal
  void internalDataContext(InternalDataContext dataContext);

  /// Set an external focus manager for this state machine via native pointer address.
  /// This allows the state machine to use a focus manager owned by a parent
  /// artboard/state machine, enabling unified focus management across nested
  /// artboards.
  /// Pass null to clear the external focus manager.
  @internal
  void setExternalFocusManager(int? pointerAddress);
}

/// Interface for requesting advance/repaint from a higher-level controller.
///
/// Used by [ViewModelInstance] and [StateMachine] to signal that their
/// state has changed and rendering should be updated.
abstract interface class AdvanceRequestInterface {
  /// Notifies all listeners that an advance/repaint is needed.
  void requestAdvance();

  /// Adds a listener to be notified when advance is requested.
  void addAdvanceRequestListener(VoidCallback callback);

  /// Removes a previously added advance request listener.
  void removeAdvanceRequestListener(VoidCallback callback);

  /// Removes all advance request listeners.
  void removeAllAdvanceRequestListeners();

  /// The number of registered advance request listeners.
  @visibleForTesting
  int get numberOfAdvanceRequestListeners;
}

/// Shared implementation of [AdvanceRequestInterface].
mixin AdvanceRequestMixin implements AdvanceRequestInterface {
  final _listeners = <VoidCallback>{};

  @override
  void requestAdvance() {
    for (var listener in _listeners) {
      listener();
    }
  }

  @override
  void addAdvanceRequestListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  @override
  void removeAdvanceRequestListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  @override
  void removeAllAdvanceRequestListeners() {
    _listeners.clear();
  }

  @override
  int get numberOfAdvanceRequestListeners => _listeners.length;
}

/// Interface for listening to Rive events from a state machine.
abstract interface class EventListenerInterface {
  /// Adds a listener to receive Rive events.
  void addEventListener(OnRiveEvent callback);

  /// Removes a previously added event listener.
  void removeEventListener(OnRiveEvent callback);

  /// Removes all registered event listeners.
  void removeAllEventListeners();

  /* INTERNAL */

  /// The number of registered event listeners.
  @visibleForTesting
  int get eventListenerCount;

  /// The set of registered event listeners.
  @internal
  Set<void Function(Event)> get eventListeners;
}

mixin EventListenerMixin implements EventListenerInterface {
  final _eventListeners = <OnRiveEvent>{};

  @override
  Set<void Function(Event)> get eventListeners => _eventListeners;

  @override
  void addEventListener(OnRiveEvent callback) => _eventListeners.add(callback);

  @override
  void removeEventListener(OnRiveEvent callback) =>
      _eventListeners.remove(callback);

  @override
  void removeAllEventListeners() {
    _eventListeners.clear();
  }

  @override
  int get eventListenerCount => _eventListeners.length;
}

/// A Rive event listener callback
typedef OnRiveEvent = void Function(Event event);

/// The type of a Rive event.
enum EventType {
  /// A general purpose event.
  general(128),

  /// An event to open a URL.
  openURL(131),

  /// An event that plays an audio asset.
  audio(407);

  final int value;
  const EventType(this.value);

  static final from = {
    128: general,
    131: openURL,
    407: audio,
  };
}

/// The type of a custom property on an event.
enum CustomPropertyType {
  /// A numeric property.
  number(127),

  /// A boolean property.
  boolean(129),

  /// A string property.
  string(130);

  final int value;
  const CustomPropertyType(this.value);

  static final from = {
    127: number,
    129: boolean,
    130: string,
  };
}

/// The browser target for opening a URL from an [OpenUrlEvent].
enum OpenUrlTarget {
  /// Open in a new window/tab.
  blank(0),

  /// Open in the parent frame.
  parent(1),

  /// Open in the same frame.
  self(2),

  /// Open in the full body of the window.
  top(3);

  final int value;
  const OpenUrlTarget(this.value);

  static final from = {
    0: blank,
    1: parent,
    2: self,
    3: top,
  };
}

/// Interface for Rive events emitted by state machines.
abstract interface class EventInterface {
  /// The name of this event as defined in the Rive editor.
  String get name;

  /// The time in seconds since this event was triggered.
  double get secondsDelay;

  /// The type of this event.
  EventType get type;

  /// Custom properties attached to this event, keyed by name.
  Map<String, CustomProperty> get properties;

  /// Retrieve a custom property from the event with the given [name].
  CustomProperty? property(String name);

  /// Retrieve a number property from the event with the given [name].
  CustomNumberProperty? numberProperty(String name);

  /// Retrieve a boolean property from the event with the given [name].
  CustomBooleanProperty? booleanProperty(String name);

  /// Retrieve a string property from the event with the given [name].
  CustomStringProperty? stringProperty(String name);

  /// Dispose the event.
  ///
  /// After calling dispose, the event should no longer be used.
  void dispose();
}

/// Mixin for implementing the [EventInterface] properties.
///
/// Provides access to the properties of the event.
mixin EventPropertyMixin implements EventInterface {
  @override
  CustomProperty? property(String name) {
    final property = properties[name];
    return property;
  }

  @override
  CustomNumberProperty? numberProperty(String name) {
    final property = properties[name];
    if (property is CustomNumberProperty) {
      return property;
    }
    return null;
  }

  @override
  CustomBooleanProperty? booleanProperty(String name) {
    final property = properties[name];
    if (property is CustomBooleanProperty) {
      return property;
    }
    return null;
  }

  @override
  CustomStringProperty? stringProperty(String name) {
    final property = properties[name];
    if (property is CustomStringProperty) {
      return property;
    }
    return null;
  }
}

/// A Rive event emitted by a state machine.
///
/// Events can be [GeneralEvent], [OpenUrlEvent], or [AudioRuntimeEvent].
/// Access via [StateMachine.reportedEvents] or listen via
/// [StateMachine.addEventListener].
sealed class Event implements EventInterface {}

/// A general purpose Rive event with optional custom properties.
abstract class GeneralEvent extends Event {}

/// A Rive event that requests opening a URL.
abstract class OpenUrlEvent extends Event {
  /// The URL to open.
  String get url;

  /// The browser target for opening the URL.
  OpenUrlTarget get target;
}

/// A Rive event that plays an audio asset at runtime.
abstract class AudioRuntimeEvent extends Event {
  /// The id of the audio asset referenced by this event.
  int get assetId;

  /// The name of the audio asset, as defined in the Rive editor.
  ///
  /// Returns an empty string when the asset cannot be resolved (for example
  /// when an out-of-band asset has not been loaded).
  String get assetName;

  /// The audio asset's volume multiplier (1.0 = unchanged).
  ///
  /// Returns 0.0 when the asset cannot be resolved.
  double get volume;
}

/// Interface for custom properties attached to Rive events.
abstract interface class CustomPropertyInterface<T> {
  /// The name of this property.
  String get name;

  /// The data type of this property.
  CustomPropertyType get type;

  /// The value of this property.
  T get value;

  /// Releases resources associated with this property.
  void dispose();
}

/// A custom property on a Rive event.
///
/// See also: [CustomNumberProperty], [CustomBooleanProperty],
/// [CustomStringProperty]
sealed class CustomProperty<T> implements CustomPropertyInterface<T> {}

/// A numeric custom property on a Rive event.
abstract class CustomNumberProperty extends CustomProperty<double> {}

/// A boolean custom property on a Rive event.
abstract class CustomBooleanProperty extends CustomProperty<bool> {}

/// A string custom property on a Rive event.
abstract class CustomStringProperty extends CustomProperty<String> {}

/// Base class for state machine inputs.
///
/// @Deprecated Use Data Binding instead of state machine inputs.
abstract class Input {
  /// The name of this input.
  String get name;

  /// Releases resources associated with this input.
  void dispose();

  /* INTERNAL */

  @internal
  StateMachine get internalStateMachine;
}

/// A numeric state machine input.
///
/// @Deprecated Use Data Binding instead of state machine inputs.
abstract class NumberInput extends Input {
  /// The current value of this input.
  double get value;

  /// Sets the value of this input.
  set value(double value);
}

/// A boolean state machine input.
///
/// @Deprecated Use Data Binding instead of state machine inputs.
abstract class BooleanInput extends Input {
  /// The current value of this input.
  bool get value;

  /// Sets the value of this input.
  set value(bool value);
}

/// A trigger state machine input.
///
/// @Deprecated Use Data Binding instead of state machine inputs.
abstract class TriggerInput extends Input {
  /// Fires the trigger.
  void fire();
}

/// A component within a Rive artboard (node, bone, shape, etc.).
///
/// Obtain via [Artboard.component].
abstract class Component {
  /// The world transformation matrix of this component.
  Mat2D get worldTransform;

  /// The local bounding box of this component.
  AABB get localBounds;

  /// Sets the world transformation matrix.
  set worldTransform(Mat2D value);

  /// The x position in local coordinates.
  double get x;

  /// Sets the x position in local coordinates.
  set x(double value);

  /// The y position in local coordinates.
  double get y;

  /// Sets the y position in local coordinates.
  set y(double value);

  /// The x scale factor.
  double get scaleX;

  /// Sets the x scale factor.
  set scaleX(double value);

  /// The y scale factor.
  double get scaleY;

  /// Sets the y scale factor.
  set scaleY(double value);

  /// The rotation angle in radians.
  double get rotation;

  /// Sets the rotation angle in radians.
  set rotation(double value);

  /// Sets the local transform to match the given world transform.
  void setLocalFromWorld(Mat2D worldTransform);

  /// Releases resources associated with this component.
  void dispose();
}

/// A text run value in a Rive artboard.
abstract class TextValueRunRuntime {
  /// The name of the text run - empty if not exported in the Rive Editor
  String get name;

  /// The text value of the text run
  String get text;

  /// Sets the text value of the text run
  set text(String value);

  /// The nested artboard path of the text run, relative to the artboard this
  // ignore: deprecated_member_use_from_same_package
  /// was retrieved from - see [Artboard.textRuns].
  String get path;

  /// Dispose the text run.
  ///
  /// After calling dispose, the text run should no longer be used.
  void dispose();
}

/// Profiler for capturing microprofile performance data.
///
/// Usage:
/// ```dart
/// final profiler = RiveProfiler.instance;
/// profiler.start();
/// // ... render frames ...
/// profiler.stop();
/// final data = profiler.dump(); // Get binary profile data after stop
/// ```
abstract class RiveProfiler {
  /// Returns the singleton profiler instance.
  static RiveProfiler get instance => getRiveProfiler();

  /// Start profiling. Returns false if already active.
  bool start();

  /// Stop profiling. Returns false if not active.
  bool stop();

  /// Check if profiling is currently active.
  bool get isActive;

  /// Dump profile data as binary blob.
  ///
  /// Automatically flushes any pending frame data before returning.
  /// Can be called while profiling is active (for streaming) or after [stop].
  /// Returns null if no data is available or profiling is not supported.
  /// Clears the internal buffer after returning data.
  Uint8List? dump();

  /// Mark the end of a frame for proper frame boundary tracking.
  ///
  /// Call this at the end of each render frame when profiling is active.
  /// This ensures proper frame timing in the profiler data.
  /// No-op if profiling is not active or not supported.
  void endFrame();
}
