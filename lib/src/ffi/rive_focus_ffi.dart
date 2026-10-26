import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rive_native/focus.dart' as focus;
import 'package:rive_native/src/ffi/rive_ffi.dart';
import 'package:rive_native/src/focus/edge_behavior.dart';

// =============================================================================
// FocusNode FFI bindings
// =============================================================================

// Callback types for FocusNode
typedef _DartKeyInputCallbackNative = Bool Function(
  Pointer<Void> nodePtr,
  Uint16 key,
  Uint8 modifiers,
  Bool isPressed,
  Bool isRepeat,
);
typedef DartKeyInputCallbackPointer
    = Pointer<NativeFunction<_DartKeyInputCallbackNative>>;

typedef _DartTextInputCallbackNative = Bool Function(
  Pointer<Void> nodePtr,
  Pointer<Utf8> text,
);
typedef DartTextInputCallbackPointer
    = Pointer<NativeFunction<_DartTextInputCallbackNative>>;

typedef _DartFocusCallbackNative = Void Function(Pointer<Void> nodePtr);
typedef DartFocusCallbackPointer
    = Pointer<NativeFunction<_DartFocusCallbackNative>>;

// FocusNode creation/disposal
final Pointer<Void> Function(
  DartKeyInputCallbackPointer keyInput,
  DartTextInputCallbackPointer textInput,
  DartFocusCallbackPointer focused,
  DartFocusCallbackPointer blurred,
) _makeFocusNodeNative = nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(
              DartKeyInputCallbackPointer,
              DartTextInputCallbackPointer,
              DartFocusCallbackPointer,
              DartFocusCallbackPointer,
            )>>('makeFocusNode')
    .asFunction();

final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _disposeFocusNodeNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
  'disposeFocusNode',
);

final void Function(Pointer<Void> node) _disposeFocusNode =
    _disposeFocusNodeNative.asFunction();

// FocusNode properties
final void Function(Pointer<Void> node, bool value) _focusNodeSetCanFocus =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
          'focusNodeSetCanFocus',
        )
        .asFunction();

final bool Function(Pointer<Void> node) _focusNodeCanFocus = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>('focusNodeCanFocus')
    .asFunction();

final void Function(Pointer<Void> node, bool value) _focusNodeSetCanTouch =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
          'focusNodeSetCanTouch',
        )
        .asFunction();

final bool Function(Pointer<Void> node) _focusNodeCanTouch = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>('focusNodeCanTouch')
    .asFunction();

final void Function(Pointer<Void> node, bool value) _focusNodeSetCanTraverse =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
          'focusNodeSetCanTraverse',
        )
        .asFunction();

final bool Function(Pointer<Void> node) _focusNodeCanTraverse = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
      'focusNodeCanTraverse',
    )
    .asFunction();

final void Function(Pointer<Void> node, int value) _focusNodeSetTabIndex =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
          'focusNodeSetTabIndex',
        )
        .asFunction();

final int Function(Pointer<Void> node) _focusNodeTabIndex = nativeLib
    .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('focusNodeTabIndex')
    .asFunction();

final void Function(Pointer<Void> node, int edgeBehavior)
    _focusNodeSetEdgeBehavior = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint8)>>(
          'focusNodeSetEdgeBehavior',
        )
        .asFunction();

final int Function(Pointer<Void> node) _focusNodeGetEdgeBehavior = nativeLib
    .lookup<NativeFunction<Uint8 Function(Pointer<Void>)>>(
      'focusNodeGetEdgeBehavior',
    )
    .asFunction();

// FocusNode name (for debugging)
final Pointer<Utf8> Function(Pointer<Void> node) _focusNodeGetName = nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>(
      'focusNodeGetName',
    )
    .asFunction();

final void Function(Pointer<Void> node, Pointer<Utf8> name) _focusNodeSetName =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Utf8>)>>(
          'focusNodeSetName',
        )
        .asFunction();

final void Function(Pointer<Void> node, bool value) _focusNodeSetIsCollapsed =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Bool)>>(
          'focusNodeSetIsCollapsed',
        )
        .asFunction();

// FocusNode world bounds (for directional navigation)
// Bounds are stored directly on the native FocusNode
final void Function(
  Pointer<Void> node,
  double minX,
  double minY,
  double maxX,
  double maxY,
) _focusNodeSetWorldBounds = nativeLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<Void>,
              Float,
              Float,
              Float,
              Float,
            )>>('focusNodeSetWorldBounds')
    .asFunction();

final void Function(Pointer<Void> node) _focusNodeClearWorldBounds = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'focusNodeClearWorldBounds',
    )
    .asFunction();

// =============================================================================
// FocusManager FFI bindings
// =============================================================================

final Pointer<Void> Function() _makeFocusManagerNative = nativeLib
    .lookup<NativeFunction<Pointer<Void> Function()>>('makeFocusManager')
    .asFunction();

final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
    _disposeFocusManagerNative =
    nativeLib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
  'disposeFocusManager',
);

final void Function(Pointer<Void> manager) _disposeFocusManager =
    _disposeFocusManagerNative.asFunction();

// FocusManager - focus state
final Pointer<Void> Function(Pointer<Void> manager)
    _focusManagerGetPrimaryFocus = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
          'focusManagerGetPrimaryFocus',
        )
        .asFunction();

final bool Function(
  Pointer<Void> manager,
  Pointer<Float> outMinX,
  Pointer<Float> outMinY,
  Pointer<Float> outMaxX,
  Pointer<Float> outMaxY,
) _focusManagerGetPrimaryFocusBounds = nativeLib
    .lookup<
        NativeFunction<
            Bool Function(
              Pointer<Void>,
              Pointer<Float>,
              Pointer<Float>,
              Pointer<Float>,
              Pointer<Float>,
            )>>('focusManagerGetPrimaryFocusBounds')
    .asFunction();

final Pointer<Void> Function(Pointer<Void> manager)
    _focusManagerGetPrimaryFocusArtboard = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
          'focusManagerGetPrimaryFocusArtboard',
        )
        .asFunction();

final Pointer<Void> Function(Pointer<Void> manager)
    _focusManagerGetPrimaryFocusImmediateArtboard = nativeLib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>(
          'focusManagerGetPrimaryFocusImmediateArtboard',
        )
        .asFunction();

final bool Function(Pointer<Void> manager, Pointer<Void> artboard)
    _focusManagerIsFocusInArtboard = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Void>)>>(
          'focusManagerIsFocusInArtboard',
        )
        .asFunction();

final void Function(Pointer<Void> manager, Pointer<Void> node)
    _focusManagerSetFocus = nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
          'focusManagerSetFocus',
        )
        .asFunction();

final void Function(Pointer<Void> manager) _focusManagerClearFocus = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'focusManagerClearFocus',
    )
    .asFunction();

final bool Function(Pointer<Void> manager, Pointer<Void> node)
    _focusManagerHasFocus = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Void>)>>(
          'focusManagerHasFocus',
        )
        .asFunction();

final bool Function(Pointer<Void> manager, Pointer<Void> node)
    _focusManagerHasPrimaryFocus = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Void>)>>(
          'focusManagerHasPrimaryFocus',
        )
        .asFunction();

final void Function(Pointer<Void> manager) _dropFocusIfFocusTargetHidden =
    nativeLib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'dropFocusIfFocusTargetHidden',
        )
        .asFunction();

// FocusManager - hierarchy
final void Function(
        Pointer<Void> manager, Pointer<Void> parent, Pointer<Void> child)
    _focusManagerAddChild = nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                  Pointer<Void>,
                  Pointer<Void>,
                )>>('focusManagerAddChild')
        .asFunction();

final void Function(Pointer<Void> manager, Pointer<Void> child)
    _focusManagerRemoveChild = nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                  Pointer<Void>,
                )>>('focusManagerRemoveChild')
        .asFunction();

final void Function(Pointer<Void> manager, Pointer<Void> child)
    _focusManagerDetachChild = nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                  Pointer<Void>,
                  Pointer<Void>,
                )>>('focusManagerDetachChild')
        .asFunction();

// FocusManager - traversal
final bool Function(Pointer<Void> manager) _focusManagerFocusNext = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
      'focusManagerFocusNext',
    )
    .asFunction();

final bool Function(Pointer<Void> manager) _focusManagerFocusPrevious =
    nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
          'focusManagerFocusPrevious',
        )
        .asFunction();

// FocusManager - directional navigation
final bool Function(Pointer<Void> manager) _focusManagerFocusLeft = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
      'focusManagerFocusLeft',
    )
    .asFunction();

final bool Function(Pointer<Void> manager) _focusManagerFocusRight = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
      'focusManagerFocusRight',
    )
    .asFunction();

final bool Function(Pointer<Void> manager) _focusManagerFocusUp = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
      'focusManagerFocusUp',
    )
    .asFunction();

final bool Function(Pointer<Void> manager) _focusManagerFocusDown = nativeLib
    .lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
      'focusManagerFocusDown',
    )
    .asFunction();

// FocusManager - input routing
final bool Function(
  Pointer<Void> manager,
  int key,
  int modifiers,
  bool isPressed,
  bool isRepeat,
) _focusManagerKeyInput = nativeLib
    .lookup<
        NativeFunction<
            Bool Function(
              Pointer<Void>,
              Uint16,
              Uint8,
              Bool,
              Bool,
            )>>('focusManagerKeyInput')
    .asFunction();

final bool Function(Pointer<Void> manager, Pointer<Utf8> text)
    _focusManagerTextInput = nativeLib
        .lookup<NativeFunction<Bool Function(Pointer<Void>, Pointer<Utf8>)>>(
          'focusManagerTextInput',
        )
        .asFunction();

// FocusManager - focus changed callback
typedef _FocusChangedCallbackNative = Void Function();
typedef _FocusChangedCallbackPointer
    = Pointer<NativeFunction<_FocusChangedCallbackNative>>;

final void Function(
    Pointer<Void> manager,
    _FocusChangedCallbackPointer
        callback) _focusManagerSetFocusChangedCallback = nativeLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<Void>,
              _FocusChangedCallbackPointer,
            )>>('focusManagerSetFocusChangedCallback')
    .asFunction<void Function(Pointer<Void>, _FocusChangedCallbackPointer)>();

// FocusManager - scroll into view callback
// Called when focus changes to an element in a Dart-mounted artboard.
// Optional: symbol may be absent in runtime-only builds (WITH_RIVE_TOOLS / editor-only).
typedef _ScrollIntoViewCallbackNative = Void Function(
  Float minX,
  Float minY,
  Float maxX,
  Float maxY,
  Pointer<Void> rootArtboard,
);
typedef _ScrollIntoViewCallbackPointer
    = Pointer<NativeFunction<_ScrollIntoViewCallbackNative>>;

final void Function(
    Pointer<Void> manager,
    _ScrollIntoViewCallbackPointer
        callback) _focusManagerSetScrollIntoViewCallback = nativeLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<Void>,
              _ScrollIntoViewCallbackPointer,
            )>>('focusManagerSetScrollIntoViewCallback')
    .asFunction<void Function(Pointer<Void>, _ScrollIntoViewCallbackPointer)>();

// =============================================================================
// FocusNodeFFI - FFI implementation
// =============================================================================

/// FFI implementation of FocusNode.
final class FocusNodeFFI implements focus.FocusNode, Finalizable {
  static final _finalizer = NativeFinalizer(_disposeFocusNodeNative);

  // Static lookup for native callbacks to find Dart FocusNode
  static final Map<int, WeakReference<FocusNodeFFI>> _callbackLookup = {};

  // Static callback trampolines registered with FFI
  static bool _onKeyInputTrampoline(
    Pointer<Void> nodePtr,
    int key,
    int modifiers,
    bool isPressed,
    bool isRepeat,
  ) {
    final node = _callbackLookup[nodePtr.address]?.target;
    return node?._onKeyInput?.call(key, modifiers, isPressed, isRepeat) ??
        false;
  }

  static bool _onTextInputTrampoline(
    Pointer<Void> nodePtr,
    Pointer<Utf8> textPtr,
  ) {
    final node = _callbackLookup[nodePtr.address]?.target;
    if (node?._onTextInput == null) return false;
    final text = textPtr.toDartString();
    return node!._onTextInput!(text);
  }

  static void _onFocusedTrampoline(Pointer<Void> nodePtr) {
    final node = _callbackLookup[nodePtr.address]?.target;
    node?._onFocused?.call();
  }

  static void _onBlurredTrampoline(Pointer<Void> nodePtr) {
    final node = _callbackLookup[nodePtr.address]?.target;
    node?._onBlurred?.call();
  }

  // Static native function pointers (initialized once)
  static DartKeyInputCallbackPointer? _keyInputCallbackPtr;
  static DartTextInputCallbackPointer? _textInputCallbackPtr;
  static DartFocusCallbackPointer? _focusedCallbackPtr;
  static DartFocusCallbackPointer? _blurredCallbackPtr;

  static void _ensureCallbacksInitialized() {
    _keyInputCallbackPtr ??= Pointer.fromFunction<_DartKeyInputCallbackNative>(
        _onKeyInputTrampoline, false);
    _textInputCallbackPtr ??=
        Pointer.fromFunction<_DartTextInputCallbackNative>(
            _onTextInputTrampoline, false);
    _focusedCallbackPtr ??=
        Pointer.fromFunction<_DartFocusCallbackNative>(_onFocusedTrampoline);
    _blurredCallbackPtr ??=
        Pointer.fromFunction<_DartFocusCallbackNative>(_onBlurredTrampoline);
  }

  Pointer<Void> _pointer;

  /// The native pointer to the FocusNode.
  Pointer<Void> get pointer => _pointer;

  // User-provided callbacks
  final focus.KeyInputCallback? _onKeyInput;
  final focus.TextInputCallback? _onTextInput;
  final focus.FocusCallback? _onFocused;
  final focus.FocusCallback? _onBlurred;

  /// Create a FocusNode with optional input/lifecycle callbacks.
  FocusNodeFFI({
    focus.KeyInputCallback? onKeyInput,
    focus.TextInputCallback? onTextInput,
    focus.FocusCallback? onFocused,
    focus.FocusCallback? onBlurred,
  })  : _onKeyInput = onKeyInput,
        _onTextInput = onTextInput,
        _onFocused = onFocused,
        _onBlurred = onBlurred,
        _pointer = nullptr {
    final hasCallbacks = onKeyInput != null ||
        onTextInput != null ||
        onFocused != null ||
        onBlurred != null;

    if (hasCallbacks) {
      _ensureCallbacksInitialized();
      _pointer = _makeFocusNodeNative(
        _keyInputCallbackPtr!,
        _textInputCallbackPtr!,
        _focusedCallbackPtr!,
        _blurredCallbackPtr!,
      );
      _callbackLookup[_pointer.address] = WeakReference(this);
    } else {
      _pointer = _makeFocusNodeNative(
        nullptr,
        nullptr,
        nullptr,
        nullptr,
      );
    }
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  @override
  bool get canFocus => _focusNodeCanFocus(_pointer);
  @override
  set canFocus(bool value) => _focusNodeSetCanFocus(_pointer, value);

  @override
  bool get canTouch => _focusNodeCanTouch(_pointer);
  @override
  set canTouch(bool value) => _focusNodeSetCanTouch(_pointer, value);

  @override
  bool get canTraverse => _focusNodeCanTraverse(_pointer);
  @override
  set canTraverse(bool value) => _focusNodeSetCanTraverse(_pointer, value);

  @override
  int get tabIndex => _focusNodeTabIndex(_pointer);
  @override
  set tabIndex(int value) => _focusNodeSetTabIndex(_pointer, value);

  @override
  set isCollapsed(bool value) => _focusNodeSetIsCollapsed(_pointer, value);

  @override
  EdgeBehavior get edgeBehavior =>
      EdgeBehavior.fromValue(_focusNodeGetEdgeBehavior(_pointer));
  @override
  set edgeBehavior(EdgeBehavior value) =>
      _focusNodeSetEdgeBehavior(_pointer, value.value);

  @override
  String get name => _focusNodeGetName(_pointer).toDartString();
  @override
  set name(String value) {
    final namePtr = value.toNativeUtf8();
    try {
      _focusNodeSetName(_pointer, namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  @override
  void setWorldBounds(double minX, double minY, double maxX, double maxY) {
    _focusNodeSetWorldBounds(_pointer, minX, minY, maxX, maxY);
  }

  @override
  void clearWorldBounds() {
    _focusNodeClearWorldBounds(_pointer);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _finalizer.detach(this);
    _callbackLookup.remove(_pointer.address);
    _disposeFocusNode(_pointer);
    _pointer = nullptr;
  }
}

// =============================================================================
// FocusManagerFFI - FFI implementation
// =============================================================================

/// FFI implementation of FocusManager.
final class FocusManagerFFI implements focus.FocusManager, Finalizable {
  static final _finalizer = NativeFinalizer(_disposeFocusManagerNative);

  // Static lookup for native callbacks to find Dart FocusManager
  static final Map<int, WeakReference<FocusManagerFFI>> _callbackLookup = {};

  // Static callback trampoline for focus changed
  static void _onFocusChangedTrampoline() {
    // Iterate through all registered managers and call their callbacks
    for (final ref in _callbackLookup.values) {
      ref.target?._onChanged?.call();
    }
  }

  // Static callback trampoline for scroll into view
  static void _onScrollIntoViewTrampoline(
    double minX,
    double minY,
    double maxX,
    double maxY,
    Pointer<Void> rootArtboard,
  ) {
    // Iterate through all registered managers and call their callbacks
    for (final ref in _callbackLookup.values) {
      final callback = ref.target?._onScrollIntoView;
      if (callback != null) {
        callback(
          (minX: minX, minY: minY, maxX: maxX, maxY: maxY),
          rootArtboard.address,
        );
      }
    }
  }

  // Static native function pointers (initialized once)
  static _FocusChangedCallbackPointer? _focusChangedCallbackPtr;
  static _ScrollIntoViewCallbackPointer? _scrollIntoViewCallbackPtr;

  Pointer<Void> _pointer;
  focus.FocusCallback? _onChanged;
  focus.ScrollIntoViewCallback? _onScrollIntoView;

  /// The native pointer to the FocusManager.
  Pointer<Void> get pointer => _pointer;

  /// Create a new FocusManager.
  FocusManagerFFI() : _pointer = _makeFocusManagerNative() {
    _finalizer.attach(this, _pointer.cast(), detach: this);
  }

  /// Get the native pointer of the primary focused node, if any.
  Pointer<Void> get primaryFocusPtr => _focusManagerGetPrimaryFocus(_pointer);

  @override
  set changed(focus.FocusCallback? callback) {
    _onChanged = callback;
    if (callback != null) {
      // Register this manager for callbacks
      _callbackLookup[_pointer.address] = WeakReference(this);
      // Initialize and set the native callback
      _focusChangedCallbackPtr ??=
          Pointer.fromFunction<_FocusChangedCallbackNative>(
              _onFocusChangedTrampoline);
      _focusManagerSetFocusChangedCallback(_pointer, _focusChangedCallbackPtr!);
    } else {
      // Unregister and clear the native callback
      _callbackLookup.remove(_pointer.address);
      _focusManagerSetFocusChangedCallback(_pointer, nullptr);
    }
  }

  @override
  set scrollIntoView(focus.ScrollIntoViewCallback? callback) {
    _onScrollIntoView = callback;
    if (callback != null) {
      // Register this manager for callbacks
      _callbackLookup[_pointer.address] = WeakReference(this);
      // Initialize and set the native callback
      _scrollIntoViewCallbackPtr ??=
          Pointer.fromFunction<_ScrollIntoViewCallbackNative>(
              _onScrollIntoViewTrampoline);
      _focusManagerSetScrollIntoViewCallback(
          _pointer, _scrollIntoViewCallbackPtr!);
    } else {
      _focusManagerSetScrollIntoViewCallback(_pointer, nullptr);
    }
  }

  @override
  void setFocus(focus.FocusNode node) {
    _focusManagerSetFocus(_pointer, _getPointer(node)!);
  }

  @override
  void clearFocus() {
    _focusManagerClearFocus(_pointer);
  }

  @override
  bool hasFocus(focus.FocusNode node) {
    return _focusManagerHasFocus(_pointer, _getPointer(node)!);
  }

  @override
  bool hasPrimaryFocus(focus.FocusNode node) {
    return _focusManagerHasPrimaryFocus(_pointer, _getPointer(node)!);
  }

  @override
  void addChild(focus.FocusNode? parent, focus.FocusNode child) {
    _focusManagerAddChild(
      _pointer,
      _getPointer(parent) ?? nullptr,
      _getPointer(child)!,
    );
  }

  @override
  void removeChild(focus.FocusNode child) {
    _focusManagerRemoveChild(
      _pointer,
      _getPointer(child)!,
    );
  }

  @override
  void detachChild(focus.FocusNode child) {
    _focusManagerDetachChild(
      _pointer,
      _getPointer(child)!,
    );
  }

  /// Get the native pointer from a FocusNode (either FocusNodeFFI or
  /// NativeFocusNodeWrapper).
  static Pointer<Void>? _getPointer(focus.FocusNode? node) {
    if (node == null) {
      return nullptr;
    }
    if (node is FocusNodeFFI) {
      return node.pointer;
    }
    if (node is NativeFocusNodeWrapper) {
      return node.pointer;
    }
    throw ArgumentError('Unknown FocusNode type: ${node.runtimeType}. '
        'Expected FocusNodeFFI or NativeFocusNodeWrapper.');
  }

  @override
  bool focusNext() {
    return _focusManagerFocusNext(_pointer);
  }

  @override
  bool focusPrevious() {
    return _focusManagerFocusPrevious(_pointer);
  }

  @override
  bool focusLeft() {
    return _focusManagerFocusLeft(_pointer);
  }

  @override
  bool focusRight() {
    return _focusManagerFocusRight(_pointer);
  }

  @override
  bool focusUp() {
    return _focusManagerFocusUp(_pointer);
  }

  @override
  bool focusDown() {
    return _focusManagerFocusDown(_pointer);
  }

  @override
  bool keyInput(int key, int modifiers, bool isPressed, bool isRepeat) {
    return _focusManagerKeyInput(
      _pointer,
      key,
      modifiers,
      isPressed,
      isRepeat,
    );
  }

  @override
  bool textInput(String text) {
    final textPtr = text.toNativeUtf8();
    try {
      return _focusManagerTextInput(_pointer, textPtr);
    } finally {
      calloc.free(textPtr);
    }
  }

  @override
  ({double minX, double minY, double maxX, double maxY})? primaryFocusBounds() {
    final minX = calloc<Float>();
    final minY = calloc<Float>();
    final maxX = calloc<Float>();
    final maxY = calloc<Float>();
    try {
      final hasValue = _focusManagerGetPrimaryFocusBounds(
        _pointer,
        minX,
        minY,
        maxX,
        maxY,
      );
      if (!hasValue) {
        return null;
      }
      return (
        minX: minX.value,
        minY: minY.value,
        maxX: maxX.value,
        maxY: maxY.value,
      );
    } finally {
      calloc.free(minX);
      calloc.free(minY);
      calloc.free(maxX);
      calloc.free(maxY);
    }
  }

  @override
  int? primaryFocusArtboardPtr() {
    final ptr = _focusManagerGetPrimaryFocusArtboard(_pointer);
    return ptr == nullptr ? null : ptr.address;
  }

  @override
  int? primaryFocusImmediateArtboardPtr() {
    final ptr = _focusManagerGetPrimaryFocusImmediateArtboard(_pointer);
    return ptr == nullptr ? null : ptr.address;
  }

  @override
  bool isFocusInArtboard(int artboardPtr) {
    return _focusManagerIsFocusInArtboard(
      _pointer,
      Pointer<Void>.fromAddress(artboardPtr),
    );
  }

  @override
  int? get nativePointerAddress => _pointer.address;

  @override
  void dropFocusIfFocusTargetHidden() {
    _dropFocusIfFocusTargetHidden(_pointer);
  }

  @override
  void dispose() {
    if (_pointer == nullptr) {
      return;
    }
    _callbackLookup.remove(_pointer.address);
    _finalizer.detach(this);
    _disposeFocusManager(_pointer);
    _pointer = nullptr;
  }
}

// =============================================================================
// NativeFocusManagerWrapper - Wrapper for native FocusManager not owned by Dart
// =============================================================================

/// Wrapper for a FocusManager that is owned by a native StateMachineInstance.
/// Unlike FocusManagerFFI, this does NOT take ownership or dispose the native
/// manager.
final class NativeFocusManagerWrapper implements focus.FocusManager {
  Pointer<Void> _pointer;

  /// The native pointer to the FocusManager.
  Pointer<Void> get pointer => _pointer;

  /// Wrap an existing native FocusManager pointer.
  NativeFocusManagerWrapper(this._pointer);

  @override
  set changed(focus.FocusCallback? callback) {
    // Not supported for wrapped managers - the StateMachine owns the callbacks
    throw UnsupportedError(
        'Cannot set changed callback on wrapped FocusManager');
  }

  @override
  set scrollIntoView(focus.ScrollIntoViewCallback? callback) {
    // Not supported for wrapped managers - the StateMachine owns the callbacks
    throw UnsupportedError(
        'Cannot set scrollIntoView callback on wrapped FocusManager');
  }

  @override
  void setFocus(focus.FocusNode node) {
    _focusManagerSetFocus(_pointer, FocusManagerFFI._getPointer(node)!);
  }

  @override
  void clearFocus() {
    _focusManagerClearFocus(_pointer);
  }

  @override
  bool hasFocus(focus.FocusNode node) {
    return _focusManagerHasFocus(_pointer, FocusManagerFFI._getPointer(node)!);
  }

  @override
  bool hasPrimaryFocus(focus.FocusNode node) {
    return _focusManagerHasPrimaryFocus(
        _pointer, FocusManagerFFI._getPointer(node)!);
  }

  @override
  void addChild(focus.FocusNode? parent, focus.FocusNode child) {
    _focusManagerAddChild(
      _pointer,
      FocusManagerFFI._getPointer(parent) ?? nullptr,
      FocusManagerFFI._getPointer(child)!,
    );
  }

  @override
  void removeChild(focus.FocusNode child) {
    _focusManagerRemoveChild(
      _pointer,
      FocusManagerFFI._getPointer(child)!,
    );
  }

  @override
  void detachChild(focus.FocusNode child) {
    _focusManagerDetachChild(
      _pointer,
      FocusManagerFFI._getPointer(child)!,
    );
  }

  @override
  bool focusNext() {
    return _focusManagerFocusNext(_pointer);
  }

  @override
  bool focusPrevious() {
    return _focusManagerFocusPrevious(_pointer);
  }

  @override
  bool focusLeft() {
    return _focusManagerFocusLeft(_pointer);
  }

  @override
  bool focusRight() {
    return _focusManagerFocusRight(_pointer);
  }

  @override
  bool focusUp() {
    return _focusManagerFocusUp(_pointer);
  }

  @override
  bool focusDown() {
    return _focusManagerFocusDown(_pointer);
  }

  @override
  bool keyInput(int key, int modifiers, bool isPressed, bool isRepeat) {
    return _focusManagerKeyInput(
      _pointer,
      key,
      modifiers,
      isPressed,
      isRepeat,
    );
  }

  @override
  bool textInput(String text) {
    final textPtr = text.toNativeUtf8();
    try {
      return _focusManagerTextInput(_pointer, textPtr);
    } finally {
      calloc.free(textPtr);
    }
  }

  @override
  ({double minX, double minY, double maxX, double maxY})? primaryFocusBounds() {
    final minX = calloc<Float>();
    final minY = calloc<Float>();
    final maxX = calloc<Float>();
    final maxY = calloc<Float>();
    try {
      final hasValue = _focusManagerGetPrimaryFocusBounds(
        _pointer,
        minX,
        minY,
        maxX,
        maxY,
      );
      if (!hasValue) {
        return null;
      }
      return (
        minX: minX.value,
        minY: minY.value,
        maxX: maxX.value,
        maxY: maxY.value,
      );
    } finally {
      calloc.free(minX);
      calloc.free(minY);
      calloc.free(maxX);
      calloc.free(maxY);
    }
  }

  @override
  int? primaryFocusArtboardPtr() {
    final ptr = _focusManagerGetPrimaryFocusArtboard(_pointer);
    return ptr == nullptr ? null : ptr.address;
  }

  @override
  int? primaryFocusImmediateArtboardPtr() {
    final ptr = _focusManagerGetPrimaryFocusImmediateArtboard(_pointer);
    return ptr == nullptr ? null : ptr.address;
  }

  @override
  bool isFocusInArtboard(int artboardPtr) {
    return _focusManagerIsFocusInArtboard(
      _pointer,
      Pointer<Void>.fromAddress(artboardPtr),
    );
  }

  @override
  int? get nativePointerAddress => _pointer.address;

  @override
  void dropFocusIfFocusTargetHidden() {
    _dropFocusIfFocusTargetHidden(_pointer);
  }

  @override
  void dispose() {
    // Do NOT dispose - we don't own this manager
    _pointer = nullptr;
  }
}

// =============================================================================
// NativeFocusNodeWrapper - Wrapper for native FocusNode not owned by Dart
// =============================================================================

/// Wrapper for a FocusNode that is owned by a native Artboard's FocusData.
/// Unlike FocusNodeFFI, this does NOT take ownership or dispose the native node.
/// Focus/blur callbacks are handled by the native FocusData internally.
class NativeFocusNodeWrapper implements focus.FocusNode {
  Pointer<Void> _pointer;

  NativeFocusNodeWrapper(this._pointer);

  /// The native pointer to the FocusNode.
  Pointer<Void> get pointer => _pointer;

  @override
  bool get canFocus => _focusNodeCanFocus(_pointer);
  @override
  set canFocus(bool value) => _focusNodeSetCanFocus(_pointer, value);

  @override
  bool get canTouch => _focusNodeCanTouch(_pointer);
  @override
  set canTouch(bool value) => _focusNodeSetCanTouch(_pointer, value);

  @override
  bool get canTraverse => _focusNodeCanTraverse(_pointer);
  @override
  set canTraverse(bool value) => _focusNodeSetCanTraverse(_pointer, value);

  @override
  int get tabIndex => _focusNodeTabIndex(_pointer);
  @override
  set tabIndex(int value) => _focusNodeSetTabIndex(_pointer, value);

  @override
  EdgeBehavior get edgeBehavior =>
      EdgeBehavior.fromValue(_focusNodeGetEdgeBehavior(_pointer));
  @override
  set edgeBehavior(EdgeBehavior value) =>
      _focusNodeSetEdgeBehavior(_pointer, value.value);

  @override
  set isCollapsed(bool value) => _focusNodeSetIsCollapsed(_pointer, value);

  @override
  String get name => _focusNodeGetName(_pointer).toDartString();
  @override
  set name(String value) {
    final namePtr = value.toNativeUtf8();
    try {
      _focusNodeSetName(_pointer, namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  @override
  void setWorldBounds(double minX, double minY, double maxX, double maxY) {
    // Native-owned FocusNodes typically get their bounds set by the native
    // component (e.g., TextInput), but we can also set them from Dart
    _focusNodeSetWorldBounds(_pointer, minX, minY, maxX, maxY);
  }

  @override
  void clearWorldBounds() {
    _focusNodeClearWorldBounds(_pointer);
  }

  @override
  void dispose() {
    // Do NOT call native dispose - the native FocusData owns this node
    _pointer = nullptr;
  }
}

// =============================================================================
// Factory functions (called from focus.dart via conditional import)
// =============================================================================

focus.FocusNode makeFocusNode({
  focus.KeyInputCallback? onKeyInput,
  focus.TextInputCallback? onTextInput,
  focus.FocusCallback? onFocused,
  focus.FocusCallback? onBlurred,
}) {
  return FocusNodeFFI(
    onKeyInput: onKeyInput,
    onTextInput: onTextInput,
    onFocused: onFocused,
    onBlurred: onBlurred,
  );
}

focus.FocusManager makeFocusManager() {
  return FocusManagerFFI();
}
