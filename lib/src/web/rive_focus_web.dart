import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';

import 'package:rive_native/focus.dart' as focus;
import 'package:rive_native/src/focus/edge_behavior.dart';
import 'package:rive_native/src/rive_native_web.dart'
    show RiveWasm, RiveNativeJsExtension;

// =============================================================================
// WASM function bindings
// =============================================================================

late js.JSFunction _makeFocusNodeSimple;
js.JSFunction? _makeFocusNodeWasm;
late js.JSFunction _disposeFocusNode;
js.JSFunction? _disposeFocusNodeWasm;
late js.JSFunction _focusNodeSetCanFocus;
late js.JSFunction _focusNodeCanFocus;
late js.JSFunction _focusNodeSetCanTouch;
late js.JSFunction _focusNodeCanTouch;
late js.JSFunction _focusNodeSetCanTraverse;
late js.JSFunction _focusNodeCanTraverse;
late js.JSFunction _focusNodeSetTabIndex;
late js.JSFunction _focusNodeTabIndex;
late js.JSFunction? _focusNodeSetIsCollapsed;
late js.JSFunction _focusNodeSetEdgeBehavior;
late js.JSFunction _focusNodeGetEdgeBehavior;
late js.JSFunction _focusNodeGetName;
late js.JSFunction _focusNodeSetName;
late js.JSFunction _focusNodeSetWorldBounds;
late js.JSFunction _focusNodeClearWorldBounds;

late js.JSFunction _makeFocusManager;
late js.JSFunction _disposeFocusManager;
late js.JSFunction _focusManagerGetPrimaryFocus;
late js.JSFunction _focusManagerSetFocus;
late js.JSFunction _focusManagerClearFocus;
late js.JSFunction _focusManagerHasFocus;
late js.JSFunction _focusManagerHasPrimaryFocus;
late js.JSFunction _focusManagerAddChild;
late js.JSFunction _focusManagerRemoveChild;
late js.JSFunction _focusManagerDetachChild;
late js.JSFunction _focusManagerFocusNext;
late js.JSFunction _focusManagerFocusPrevious;
late js.JSFunction _focusManagerFocusLeft;
late js.JSFunction _focusManagerFocusRight;
late js.JSFunction _focusManagerFocusUp;
late js.JSFunction _focusManagerFocusDown;
late js.JSFunction _focusManagerKeyInput;
late js.JSFunction _focusManagerTextInput;
// These require WITH_RIVE_TOOLS (editor builds only via EMSCRIPTEN_BINDINGS)
js.JSFunction? _focusManagerGetPrimaryFocusBounds;
late js.JSFunction _focusManagerGetPrimaryFocusArtboard;
late js.JSFunction _focusManagerGetPrimaryFocusImmediateArtboard;
late js.JSFunction _focusManagerIsFocusInArtboard;
late js.JSFunction _dropFocusIfFocusTargetHidden;
js.JSFunction? _focusManagerSetFocusChangedCallback;
js.JSFunction? _focusManagerSetScrollIntoViewCallback;

// WASM returns int (0/1) for bool, not JS boolean.
// This helper converts the result to Dart bool.
bool _wasmBool(js.JSAny? result) => (result as js.JSNumber).toDartInt != 0;

// WASM EXPORT functions expect i32 (0/1) for bool parameters, not JS boolean.
// This helper converts Dart bool to JSNumber for passing to WASM.
js.JSNumber _boolWasm(bool value) => (value ? 1 : 0).toJS;

// =============================================================================
// FocusNodeWasm - WASM implementation
// =============================================================================

/// WASM implementation of FocusNode.
class FocusNodeWasm implements focus.FocusNode {
  int nativePtr;
  final bool _hasCallbacks;

  final focus.KeyInputCallback? onKeyInput;
  final focus.TextInputCallback? onTextInput;
  final focus.FocusCallback? onFocused;
  final focus.FocusCallback? onBlurred;

  FocusNodeWasm({
    this.onKeyInput,
    this.onTextInput,
    this.onFocused,
    this.onBlurred,
  })  : _hasCallbacks = onKeyInput != null ||
            onTextInput != null ||
            onFocused != null ||
            onBlurred != null,
        nativePtr = 0 {
    if (_hasCallbacks && _makeFocusNodeWasm != null) {
      nativePtr = (_makeFocusNodeWasm!.callAsFunction(
        null,
        onKeyInput != null
            ? ((int key, int modifiers, bool isPressed, bool isRepeat) {
                return onKeyInput!(key, modifiers, isPressed, isRepeat);
              }).toJS
            : null,
        onTextInput != null
            ? ((String text) {
                return onTextInput!(text);
              }).toJS
            : null,
        onFocused != null ? (() => onFocused!()).toJS : null,
        onBlurred != null ? (() => onBlurred!()).toJS : null,
      ) as js.JSNumber)
          .toDartInt;
    } else {
      nativePtr =
          (_makeFocusNodeSimple.callAsFunction(null) as js.JSNumber).toDartInt;
    }
  }

  @override
  bool get canFocus =>
      _wasmBool(_focusNodeCanFocus.callAsFunction(null, nativePtr.toJS));

  @override
  set canFocus(bool value) => _focusNodeSetCanFocus.callAsFunction(
      null, nativePtr.toJS, _boolWasm(value));

  @override
  bool get canTouch =>
      _wasmBool(_focusNodeCanTouch.callAsFunction(null, nativePtr.toJS));

  @override
  set canTouch(bool value) => _focusNodeSetCanTouch.callAsFunction(
      null, nativePtr.toJS, _boolWasm(value));

  @override
  bool get canTraverse =>
      _wasmBool(_focusNodeCanTraverse.callAsFunction(null, nativePtr.toJS));

  @override
  set canTraverse(bool value) => _focusNodeSetCanTraverse.callAsFunction(
      null, nativePtr.toJS, _boolWasm(value));

  @override
  int get tabIndex =>
      (_focusNodeTabIndex.callAsFunction(null, nativePtr.toJS) as js.JSNumber)
          .toDartInt;

  @override
  set tabIndex(int value) =>
      _focusNodeSetTabIndex.callAsFunction(null, nativePtr.toJS, value.toJS);

  @override
  set isCollapsed(bool value) => _focusNodeSetIsCollapsed?.callAsFunction(
      null, nativePtr.toJS, value.toJS);

  @override
  EdgeBehavior get edgeBehavior => EdgeBehavior.fromValue(
        (_focusNodeGetEdgeBehavior.callAsFunction(null, nativePtr.toJS)
                as js.JSNumber)
            .toDartInt,
      );

  @override
  set edgeBehavior(EdgeBehavior value) => _focusNodeSetEdgeBehavior
      .callAsFunction(null, nativePtr.toJS, value.value.toJS);

  @override
  String get name => RiveWasm.toDartString(
      (_focusNodeGetName.callAsFunction(null, nativePtr.toJS) as js.JSNumber)
          .toDartInt);

  @override
  set name(String value) => RiveWasm.toNativeString(value, (namePointer) {
        _focusNodeSetName.callAsFunction(null, nativePtr.toJS, namePointer);
      });

  @override
  void setWorldBounds(double minX, double minY, double maxX, double maxY) {
    _focusNodeSetWorldBounds.callAsFunctionEx(
      null,
      nativePtr.toJS,
      minX.toJS,
      minY.toJS,
      maxX.toJS,
      maxY.toJS,
    );
  }

  @override
  void clearWorldBounds() {
    _focusNodeClearWorldBounds.callAsFunction(null, nativePtr.toJS);
  }

  @override
  void dispose() {
    if (nativePtr == 0) return;
    if (_hasCallbacks && _disposeFocusNodeWasm != null) {
      _disposeFocusNodeWasm!.callAsFunction(null, nativePtr.toJS);
    } else {
      _disposeFocusNode.callAsFunction(null, nativePtr.toJS);
    }
    nativePtr = 0;
  }
}

// =============================================================================
// NativeFocusNodeWasmWrapper - Wraps native-owned FocusNode pointers
// =============================================================================

/// Wraps a native-owned FocusNode pointer for WASM.
/// This is used for FocusNodes returned from artboard queries that are owned
/// by native FocusData components (not Dart-created).
class NativeFocusNodeWasmWrapper implements focus.FocusNode {
  int nativePtr;

  NativeFocusNodeWasmWrapper(this.nativePtr);

  @override
  bool get canFocus =>
      _wasmBool(_focusNodeCanFocus.callAsFunction(null, nativePtr.toJS));

  @override
  set canFocus(bool value) => _focusNodeSetCanFocus.callAsFunction(
      null, nativePtr.toJS, _boolWasm(value));

  @override
  bool get canTouch =>
      _wasmBool(_focusNodeCanTouch.callAsFunction(null, nativePtr.toJS));

  @override
  set canTouch(bool value) => _focusNodeSetCanTouch.callAsFunction(
      null, nativePtr.toJS, _boolWasm(value));

  @override
  bool get canTraverse =>
      _wasmBool(_focusNodeCanTraverse.callAsFunction(null, nativePtr.toJS));

  @override
  set canTraverse(bool value) => _focusNodeSetCanTraverse.callAsFunction(
      null, nativePtr.toJS, _boolWasm(value));

  @override
  int get tabIndex =>
      (_focusNodeTabIndex.callAsFunction(null, nativePtr.toJS) as js.JSNumber)
          .toDartInt;

  @override
  set tabIndex(int value) =>
      _focusNodeSetTabIndex.callAsFunction(null, nativePtr.toJS, value.toJS);

  @override
  set isCollapsed(bool value) => _focusNodeSetIsCollapsed?.callAsFunction(
      null, nativePtr.toJS, value.toJS);

  @override
  EdgeBehavior get edgeBehavior => EdgeBehavior.fromValue(
        (_focusNodeGetEdgeBehavior.callAsFunction(null, nativePtr.toJS)
                as js.JSNumber)
            .toDartInt,
      );

  @override
  set edgeBehavior(EdgeBehavior value) => _focusNodeSetEdgeBehavior
      .callAsFunction(null, nativePtr.toJS, value.value.toJS);

  @override
  String get name => RiveWasm.toDartString(
      (_focusNodeGetName.callAsFunction(null, nativePtr.toJS) as js.JSNumber)
          .toDartInt);

  @override
  set name(String value) => RiveWasm.toNativeString(value, (namePointer) {
        _focusNodeSetName.callAsFunction(null, nativePtr.toJS, namePointer);
      });

  @override
  void setWorldBounds(double minX, double minY, double maxX, double maxY) {
    _focusNodeSetWorldBounds.callAsFunctionEx(
      null,
      nativePtr.toJS,
      minX.toJS,
      minY.toJS,
      maxX.toJS,
      maxY.toJS,
    );
  }

  @override
  void clearWorldBounds() {
    _focusNodeClearWorldBounds.callAsFunction(null, nativePtr.toJS);
  }

  @override
  void dispose() {
    // Do NOT call native dispose - the native FocusData owns this node
    nativePtr = 0;
  }
}

// =============================================================================
// NativeFocusManagerWasmWrapper - Wraps native-owned FocusManager pointers
// =============================================================================

/// Wraps a native-owned FocusManager pointer for WASM.
/// This is used for FocusManagers returned from state machine queries that are
/// owned by the native StateMachineInstance (not Dart-created).
class NativeFocusManagerWasmWrapper implements focus.FocusManager {
  int nativePtr;

  NativeFocusManagerWasmWrapper(this.nativePtr);

  static int? _getNodePointer(focus.FocusNode? node) {
    if (node is NativeFocusNodeWasmWrapper) {
      return node.nativePtr;
    } else if (node is FocusNodeWasm) {
      return node.nativePtr;
    }
    return null;
  }

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
    final nodePtr = _getNodePointer(node);
    if (nodePtr != null) {
      _focusManagerSetFocus.callAsFunction(null, nativePtr.toJS, nodePtr.toJS);
    }
  }

  @override
  void clearFocus() {
    _focusManagerClearFocus.callAsFunction(null, nativePtr.toJS);
  }

  @override
  bool hasFocus(focus.FocusNode node) {
    final nodePtr = _getNodePointer(node);
    if (nodePtr == null) return false;
    return _wasmBool(_focusManagerHasFocus.callAsFunction(
        null, nativePtr.toJS, nodePtr.toJS));
  }

  @override
  bool hasPrimaryFocus(focus.FocusNode node) {
    final nodePtr = _getNodePointer(node);
    if (nodePtr == null) return false;
    return _wasmBool(_focusManagerHasPrimaryFocus.callAsFunction(
        null, nativePtr.toJS, nodePtr.toJS));
  }

  @override
  void addChild(focus.FocusNode? parent, focus.FocusNode child) {
    final parentPtr = _getNodePointer(parent) ?? 0;
    final childPtr = _getNodePointer(child);
    if (childPtr != null) {
      _focusManagerAddChild.callAsFunction(
        null,
        nativePtr.toJS,
        parentPtr.toJS,
        childPtr.toJS,
      );
    }
  }

  @override
  void removeChild(focus.FocusNode child) {
    final childPtr = _getNodePointer(child);
    if (childPtr != null) {
      _focusManagerRemoveChild.callAsFunction(
        null,
        nativePtr.toJS,
        childPtr.toJS,
      );
    }
  }

  @override
  void detachChild(focus.FocusNode child) {
    final childPtr = _getNodePointer(child);
    if (childPtr != null) {
      _focusManagerDetachChild.callAsFunction(
        null,
        nativePtr.toJS,
        childPtr.toJS,
      );
    }
  }

  @override
  bool focusNext() {
    return _wasmBool(
        _focusManagerFocusNext.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusPrevious() {
    return _wasmBool(
        _focusManagerFocusPrevious.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusLeft() {
    return _wasmBool(
        _focusManagerFocusLeft.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusRight() {
    return _wasmBool(
        _focusManagerFocusRight.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusUp() {
    return _wasmBool(_focusManagerFocusUp.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusDown() {
    return _wasmBool(
        _focusManagerFocusDown.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool keyInput(int key, int modifiers, bool isPressed, bool isRepeat) {
    return _wasmBool(_focusManagerKeyInput.callAsFunctionEx(
      null,
      nativePtr.toJS,
      key.toJS,
      modifiers.toJS,
      _boolWasm(isPressed),
      _boolWasm(isRepeat),
    ));
  }

  @override
  bool textInput(String text) {
    return RiveWasm.toNativeString(text, (textPointer) {
      return _wasmBool(_focusManagerTextInput.callAsFunction(
          null, nativePtr.toJS, textPointer));
    });
  }

  @override
  ({double minX, double minY, double maxX, double maxY})? primaryFocusBounds() {
    final fn = _focusManagerGetPrimaryFocusBounds;
    if (fn == null) return null;
    // WASM returns a struct {valid, minX, minY, maxX, maxY}
    final rawResult = fn.callAsFunction(
      null,
      nativePtr.toJS,
    );
    if (rawResult == null) return null;
    final result = rawResult as js.JSObject;
    final valid = (result.getProperty('valid'.toJS) as js.JSNumber).toDartInt;
    if (valid == 0) return null;
    return (
      minX: (result.getProperty('minX'.toJS) as js.JSNumber).toDartDouble,
      minY: (result.getProperty('minY'.toJS) as js.JSNumber).toDartDouble,
      maxX: (result.getProperty('maxX'.toJS) as js.JSNumber).toDartDouble,
      maxY: (result.getProperty('maxY'.toJS) as js.JSNumber).toDartDouble,
    );
  }

  @override
  int? primaryFocusArtboardPtr() {
    final ptr = (_focusManagerGetPrimaryFocusArtboard.callAsFunction(
      null,
      nativePtr.toJS,
    ) as js.JSNumber)
        .toDartInt;
    return ptr == 0 ? null : ptr;
  }

  @override
  int? primaryFocusImmediateArtboardPtr() {
    final ptr = (_focusManagerGetPrimaryFocusImmediateArtboard.callAsFunction(
      null,
      nativePtr.toJS,
    ) as js.JSNumber)
        .toDartInt;
    return ptr == 0 ? null : ptr;
  }

  @override
  bool isFocusInArtboard(int artboardPtr) {
    return _wasmBool(_focusManagerIsFocusInArtboard.callAsFunction(
      null,
      nativePtr.toJS,
      artboardPtr.toJS,
    ));
  }

  @override
  int? get nativePointerAddress => nativePtr == 0 ? null : nativePtr;

  @override
  void dropFocusIfFocusTargetHidden() {
    _dropFocusIfFocusTargetHidden.callAsFunction(null, nativePtr.toJS);
  }

  @override
  void dispose() {
    // Do NOT dispose - we don't own this manager
    nativePtr = 0;
  }
}

// =============================================================================
// FocusManagerWasm - WASM implementation
// =============================================================================

/// WASM implementation of FocusManager.
class FocusManagerWasm implements focus.FocusManager {
  int nativePtr;
  FocusManagerWasm()
      : nativePtr =
            (_makeFocusManager.callAsFunction(null) as js.JSNumber).toDartInt;

  int get primaryFocusPtr =>
      (_focusManagerGetPrimaryFocus.callAsFunction(null, nativePtr.toJS)
              as js.JSNumber)
          .toDartInt;

  /// Helper to get the native pointer from either FocusNodeWasm or
  /// NativeFocusNodeWasmWrapper.
  static int? _getNodePointer(focus.FocusNode? node) {
    if (node is NativeFocusNodeWasmWrapper) {
      return node.nativePtr;
    } else if (node is FocusNodeWasm) {
      return node.nativePtr;
    }
    return null;
  }

  @override
  set changed(focus.FocusCallback? callback) {
    final fn = _focusManagerSetFocusChangedCallback;
    if (fn == null) return;
    if (callback != null) {
      fn.callAsFunction(
        null,
        nativePtr.toJS,
        (() {
          callback();
        }).toJS,
      );
    } else {
      fn.callAsFunction(
        null,
        nativePtr.toJS,
        null,
      );
    }
  }

  @override
  set scrollIntoView(focus.ScrollIntoViewCallback? callback) {
    final fn = _focusManagerSetScrollIntoViewCallback;
    if (fn == null) return;
    if (callback != null) {
      fn.callAsFunction(
        null,
        nativePtr.toJS,
        ((double minX, double minY, double maxX, double maxY, int artboardPtr) {
          callback(
            (minX: minX, minY: minY, maxX: maxX, maxY: maxY),
            artboardPtr,
          );
        }).toJS,
      );
    } else {
      fn.callAsFunction(
        null,
        nativePtr.toJS,
        null,
      );
    }
  }

  @override
  void setFocus(focus.FocusNode node) {
    final nodePtr = _getNodePointer(node);
    if (nodePtr != null) {
      _focusManagerSetFocus.callAsFunction(null, nativePtr.toJS, nodePtr.toJS);
    }
  }

  @override
  void clearFocus() {
    _focusManagerClearFocus.callAsFunction(null, nativePtr.toJS);
  }

  @override
  bool hasFocus(focus.FocusNode node) {
    final nodePtr = _getNodePointer(node);
    if (nodePtr == null) return false;
    return _wasmBool(_focusManagerHasFocus.callAsFunction(
        null, nativePtr.toJS, nodePtr.toJS));
  }

  @override
  bool hasPrimaryFocus(focus.FocusNode node) {
    final nodePtr = _getNodePointer(node);
    if (nodePtr == null) return false;
    return _wasmBool(_focusManagerHasPrimaryFocus.callAsFunction(
        null, nativePtr.toJS, nodePtr.toJS));
  }

  @override
  void addChild(focus.FocusNode? parent, focus.FocusNode child) {
    final parentPtr = _getNodePointer(parent) ?? 0;
    final childPtr = _getNodePointer(child);
    if (childPtr != null) {
      _focusManagerAddChild.callAsFunction(
        null,
        nativePtr.toJS,
        parentPtr.toJS,
        childPtr.toJS,
      );
    }
  }

  @override
  void removeChild(focus.FocusNode child) {
    final childPtr = _getNodePointer(child);
    if (childPtr != null) {
      _focusManagerRemoveChild.callAsFunction(
        null,
        nativePtr.toJS,
        childPtr.toJS,
      );
    }
  }

  @override
  void detachChild(focus.FocusNode child) {
    final childPtr = _getNodePointer(child);
    if (childPtr != null) {
      _focusManagerDetachChild.callAsFunction(
        null,
        nativePtr.toJS,
        childPtr.toJS,
      );
    }
  }

  @override
  bool focusNext() {
    return _wasmBool(
        _focusManagerFocusNext.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusPrevious() {
    return _wasmBool(
        _focusManagerFocusPrevious.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusLeft() {
    return _wasmBool(
        _focusManagerFocusLeft.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusRight() {
    return _wasmBool(
        _focusManagerFocusRight.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusUp() {
    return _wasmBool(_focusManagerFocusUp.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool focusDown() {
    return _wasmBool(
        _focusManagerFocusDown.callAsFunction(null, nativePtr.toJS));
  }

  @override
  bool keyInput(int key, int modifiers, bool isPressed, bool isRepeat) {
    return _wasmBool(_focusManagerKeyInput.callAsFunctionEx(
      null,
      nativePtr.toJS,
      key.toJS,
      modifiers.toJS,
      _boolWasm(isPressed),
      _boolWasm(isRepeat),
    ));
  }

  @override
  bool textInput(String text) {
    return RiveWasm.toNativeString(text, (textPointer) {
      return _wasmBool(_focusManagerTextInput.callAsFunction(
          null, nativePtr.toJS, textPointer));
    });
  }

  @override
  ({double minX, double minY, double maxX, double maxY})? primaryFocusBounds() {
    final fn = _focusManagerGetPrimaryFocusBounds;
    if (fn == null) return null;
    // WASM returns a struct {valid, minX, minY, maxX, maxY}
    final rawResult = fn.callAsFunction(
      null,
      nativePtr.toJS,
    );
    if (rawResult == null) return null;
    final result = rawResult as js.JSObject;
    final valid = (result.getProperty('valid'.toJS) as js.JSNumber).toDartInt;
    if (valid == 0) return null;
    return (
      minX: (result.getProperty('minX'.toJS) as js.JSNumber).toDartDouble,
      minY: (result.getProperty('minY'.toJS) as js.JSNumber).toDartDouble,
      maxX: (result.getProperty('maxX'.toJS) as js.JSNumber).toDartDouble,
      maxY: (result.getProperty('maxY'.toJS) as js.JSNumber).toDartDouble,
    );
  }

  @override
  int? primaryFocusArtboardPtr() {
    final ptr = (_focusManagerGetPrimaryFocusArtboard.callAsFunction(
      null,
      nativePtr.toJS,
    ) as js.JSNumber)
        .toDartInt;
    return ptr == 0 ? null : ptr;
  }

  @override
  int? primaryFocusImmediateArtboardPtr() {
    final ptr = (_focusManagerGetPrimaryFocusImmediateArtboard.callAsFunction(
      null,
      nativePtr.toJS,
    ) as js.JSNumber)
        .toDartInt;
    return ptr == 0 ? null : ptr;
  }

  @override
  bool isFocusInArtboard(int artboardPtr) {
    return _wasmBool(_focusManagerIsFocusInArtboard.callAsFunction(
      null,
      nativePtr.toJS,
      artboardPtr.toJS,
    ));
  }

  @override
  int? get nativePointerAddress => nativePtr == 0 ? null : nativePtr;

  @override
  void dropFocusIfFocusTargetHidden() {
    _dropFocusIfFocusTargetHidden.callAsFunction(null, nativePtr.toJS);
  }

  @override
  void dispose() {
    if (nativePtr == 0) return;
    _disposeFocusManager.callAsFunction(null, nativePtr.toJS);
    nativePtr = 0;
  }

  static void link(js.JSObject module) {
    // Most functions use raw EXPORT (underscore prefix) - they don't need
    // EMSCRIPTEN_BINDINGS. Only focusManagerSetScrollIntoViewCallback (takes
    // emscripten::val callback) and focusManagerGetPrimaryFocusBounds (returns
    // value_object struct) use EMSCRIPTEN_BINDINGS (no underscore).
    _makeFocusNodeSimple = module['_makeFocusNodeSimple'] as js.JSFunction;
    _makeFocusNodeWasm = module['makeFocusNodeWasm'] as js.JSFunction?;
    _disposeFocusNode = module['_disposeFocusNode'] as js.JSFunction;
    _disposeFocusNodeWasm = module['disposeFocusNodeWasm'] as js.JSFunction?;
    _focusNodeSetCanFocus = module['_focusNodeSetCanFocus'] as js.JSFunction;
    _focusNodeCanFocus = module['_focusNodeCanFocus'] as js.JSFunction;
    _focusNodeSetCanTouch = module['_focusNodeSetCanTouch'] as js.JSFunction;
    _focusNodeCanTouch = module['_focusNodeCanTouch'] as js.JSFunction;
    _focusNodeSetCanTraverse =
        module['_focusNodeSetCanTraverse'] as js.JSFunction;
    _focusNodeCanTraverse = module['_focusNodeCanTraverse'] as js.JSFunction;
    _focusNodeSetTabIndex = module['_focusNodeSetTabIndex'] as js.JSFunction;
    _focusNodeTabIndex = module['_focusNodeTabIndex'] as js.JSFunction;
    _focusNodeSetIsCollapsed =
        module['_focusNodeSetIsCollapsed'] as js.JSFunction?;
    _focusNodeSetEdgeBehavior =
        module['_focusNodeSetEdgeBehavior'] as js.JSFunction;
    _focusNodeGetEdgeBehavior =
        module['_focusNodeGetEdgeBehavior'] as js.JSFunction;
    _focusNodeGetName = module['_focusNodeGetName'] as js.JSFunction;
    _focusNodeSetName = module['_focusNodeSetName'] as js.JSFunction;
    _focusNodeSetWorldBounds =
        module['_focusNodeSetWorldBounds'] as js.JSFunction;
    _focusNodeClearWorldBounds =
        module['_focusNodeClearWorldBounds'] as js.JSFunction;

    _makeFocusManager = module['_makeFocusManager'] as js.JSFunction;
    _disposeFocusManager = module['_disposeFocusManager'] as js.JSFunction;
    _focusManagerGetPrimaryFocus =
        module['_focusManagerGetPrimaryFocus'] as js.JSFunction;
    _focusManagerSetFocus = module['_focusManagerSetFocus'] as js.JSFunction;
    _focusManagerClearFocus =
        module['_focusManagerClearFocus'] as js.JSFunction;
    _focusManagerHasFocus = module['_focusManagerHasFocus'] as js.JSFunction;
    _focusManagerHasPrimaryFocus =
        module['_focusManagerHasPrimaryFocus'] as js.JSFunction;
    _focusManagerAddChild = module['_focusManagerAddChild'] as js.JSFunction;
    _focusManagerRemoveChild =
        module['_focusManagerRemoveChild'] as js.JSFunction;
    _focusManagerDetachChild =
        module['_focusManagerDetachChild'] as js.JSFunction;
    _focusManagerFocusNext = module['_focusManagerFocusNext'] as js.JSFunction;
    _focusManagerFocusPrevious =
        module['_focusManagerFocusPrevious'] as js.JSFunction;
    _focusManagerFocusLeft = module['_focusManagerFocusLeft'] as js.JSFunction;
    _focusManagerFocusRight =
        module['_focusManagerFocusRight'] as js.JSFunction;
    _focusManagerFocusUp = module['_focusManagerFocusUp'] as js.JSFunction;
    _focusManagerFocusDown = module['_focusManagerFocusDown'] as js.JSFunction;
    _focusManagerKeyInput = module['_focusManagerKeyInput'] as js.JSFunction;
    _focusManagerTextInput = module['_focusManagerTextInput'] as js.JSFunction;
    _focusManagerGetPrimaryFocusArtboard =
        module['_focusManagerGetPrimaryFocusArtboard'] as js.JSFunction;
    _focusManagerGetPrimaryFocusImmediateArtboard =
        module['_focusManagerGetPrimaryFocusImmediateArtboard']
            as js.JSFunction;
    _focusManagerIsFocusInArtboard =
        module['_focusManagerIsFocusInArtboard'] as js.JSFunction;
    _dropFocusIfFocusTargetHidden =
        module['_dropFocusIfFocusTargetHidden'] as js.JSFunction;

    // These use EMSCRIPTEN_BINDINGS (no underscore) and are only available
    // in editor builds (WITH_RIVE_TOOLS). Runtime builds use the fully native
    // focus implementation without Dart-side callbacks.
    _focusManagerGetPrimaryFocusBounds =
        module['focusManagerGetPrimaryFocusBounds'] as js.JSFunction?;
    _focusManagerSetFocusChangedCallback =
        module['focusManagerSetFocusChangedCallback'] as js.JSFunction?;
    _focusManagerSetScrollIntoViewCallback =
        module['focusManagerSetScrollIntoViewCallback'] as js.JSFunction?;
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
  return FocusNodeWasm(
    onKeyInput: onKeyInput,
    onTextInput: onTextInput,
    onFocused: onFocused,
    onBlurred: onBlurred,
  );
}

focus.FocusManager makeFocusManager() {
  return FocusManagerWasm();
}
