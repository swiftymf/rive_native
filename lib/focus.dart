import 'src/focus/edge_behavior.dart';
import 'src/ffi/rive_focus_ffi.dart'
    if (dart.library.js_interop) 'src/web/rive_focus_web.dart';

export 'src/focus/edge_behavior.dart';

/// Callback type for key input handling.
typedef KeyInputCallback = bool Function(
  int key,
  int modifiers,
  bool isPressed,
  bool isRepeat,
);

/// Callback type for text input handling.
typedef TextInputCallback = bool Function(String text);

/// Callback type for focus lifecycle events.
typedef FocusCallback = void Function();

/// Callback type for scroll-into-view requests from Dart-mounted artboards.
/// Called when focus changes to an element in an artboard whose root
/// is mounted by Dart (has no native host).
/// Parameters:
/// - bounds: world bounds of the focused element to scroll into view
/// - artboardPtr: pointer to the artboard directly hosted by the Dart root
typedef ScrollIntoViewCallback = void Function(
  ({double minX, double minY, double maxX, double maxY}) bounds,
  int artboardPtr,
);

/// A focus node that stores properties and optionally delegates input/lifecycle
/// to callbacks.
abstract class FocusNode {
  /// Create a FocusNode with optional input/lifecycle callbacks.
  static FocusNode make({
    KeyInputCallback? onKeyInput,
    TextInputCallback? onTextInput,
    FocusCallback? onFocused,
    FocusCallback? onBlurred,
  }) {
    return makeFocusNode(
      onKeyInput: onKeyInput,
      onTextInput: onTextInput,
      onFocused: onFocused,
      onBlurred: onBlurred,
    );
  }

  /// Whether this node can receive focus at all.
  bool get canFocus;
  set canFocus(bool value);

  /// Whether this node can receive focus via pointer/touch click.
  bool get canTouch;
  set canTouch(bool value);

  /// Whether this node is included in tab traversal.
  bool get canTraverse;
  set canTraverse(bool value);

  /// The tab index for traversal ordering.
  int get tabIndex;
  set tabIndex(int value);

  /// Whether this node is collapsed and does not participate in focus.
  set isCollapsed(bool value);

  /// The edge behavior for this node when it acts as a scope.
  EdgeBehavior get edgeBehavior;
  set edgeBehavior(EdgeBehavior value);

  /// Debug name for this node (does not need to be unique).
  String get name;
  set name(String value);

  /// Set the world bounds for this node (for directional navigation).
  /// Bounds are in root artboard space and used for spatial navigation
  /// calculations. Call this during your update cycle when the node's
  /// position/size changes.
  void setWorldBounds(double minX, double minY, double maxX, double maxY);

  /// Clear the world bounds for this node (marks bounds as unavailable).
  /// Nodes without bounds will not participate in directional navigation.
  void clearWorldBounds();

  /// Dispose of this focus node and release native resources.
  void dispose();
}

/// Manages focus state and hierarchy for a set of FocusNodes.
abstract class FocusManager {
  /// Create a new FocusManager.
  static FocusManager make() {
    return makeFocusManager();
  }

  /// Set a callback to be invoked when focus changes.
  /// Pass null to remove the callback.
  set changed(FocusCallback? callback);

  /// Set a callback to be invoked when focus changes to an element in a
  /// Dart-mounted artboard (root artboard with no native host).
  /// This allows Dart to handle scrolling the focused element into view.
  /// Pass null to remove the callback.
  set scrollIntoView(ScrollIntoViewCallback? callback);

  /// Set focus to the given node.
  void setFocus(FocusNode node);

  /// Clear the current focus.
  void clearFocus();

  /// Check if the given node or any of its descendants has focus.
  bool hasFocus(FocusNode node);

  /// Check if the given node is the primary focus.
  bool hasPrimaryFocus(FocusNode node);

  /// Add a child node to the hierarchy.
  /// If [parent] is null, the child is added as a root node.
  void addChild(FocusNode? parent, FocusNode child);

  /// Remove a child node from the hierarchy.
  /// The child knows its own parent, so no parent parameter is needed.
  void removeChild(FocusNode child);

  /// Detach a child node from the hierarchy WITHOUT clearing focus.
  /// Use this when reordering an existing node (e.g. rebuilding the focus
  /// hierarchy) so the primary focus and its blur/focus callbacks are
  /// preserved. For genuine removal use [removeChild] instead.
  void detachChild(FocusNode child);

  /// Move focus to the next focusable node.
  /// Returns true if focus was moved.
  bool focusNext();

  /// Move focus to the previous focusable node.
  /// Returns true if focus was moved.
  bool focusPrevious();

  /// Move focus to the nearest focusable node to the left.
  /// Returns true if focus was moved.
  bool focusLeft();

  /// Move focus to the nearest focusable node to the right.
  /// Returns true if focus was moved.
  bool focusRight();

  /// Move focus to the nearest focusable node above.
  /// Returns true if focus was moved.
  bool focusUp();

  /// Move focus to the nearest focusable node below.
  /// Returns true if focus was moved.
  bool focusDown();

  /// Route key input to the focused node.
  /// Returns true if the input was handled.
  bool keyInput(int key, int modifiers, bool isPressed, bool isRepeat);

  /// Route text input to the focused node.
  /// Returns true if the input was handled.
  bool textInput(String text);

  /// Get the world bounds of the primary focus node.
  /// Returns null if there is no focus or the focused node has no bounds.
  /// Bounds are in root artboard space.
  ({double minX, double minY, double maxX, double maxY})? primaryFocusBounds();

  /// Get the root native artboard pointer address that contains the primary focus.
  /// This walks up the nested artboard chain to find the topmost artboard.
  /// Returns null if there is no focus or the focusable has no artboard.
  int? primaryFocusArtboardPtr();

  /// Get the immediate native artboard pointer address that contains the
  /// primary focus. Unlike [primaryFocusArtboardPtr], this does NOT walk up
  /// the nested artboard chain - it returns the direct parent artboard.
  /// This can be compared against MountedArtboard native pointer addresses to
  /// find which NestedArtboard hosts the focused element.
  int? primaryFocusImmediateArtboardPtr();

  /// Check if the primary focus is inside the given artboard (or a nested
  /// artboard within it). Returns true if the focused element's artboard is
  /// the given artboard or a descendant of it.
  /// [artboardPtr] should be a native artboard pointer address.
  bool isFocusInArtboard(int artboardPtr);

  /// Dispose of this focus manager and release native resources.
  void dispose();

  /// Get the native pointer address for this focus manager.
  /// Used internally for sharing focus managers across FFI boundaries.
  /// Returns null on platforms that don't support this (e.g., web).
  int? get nativePointerAddress;

  /// Clear focus if the current target is hidden.
  void dropFocusIfFocusTargetHidden();
}
