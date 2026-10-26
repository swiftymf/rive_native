import 'package:meta/meta.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

/// Mixin that provides semantic tree tracking on a [rive.RivePainter].
///
/// When [semanticsEnabled] is set to `true`, each call to [updateSemantics]
/// queries the state machine for incremental semantic diffs and applies them
/// to [semanticTree]. The host painter should call [updateSemantics] from its
/// `advance` method after advancing the animation/state machine.
///
/// Custom painters can mix this in to expose accessibility information:
///
/// ```dart
/// base class MyPainter extends BasicArtboardPainter
///     with RiveSemanticsMixin {
///   @override
///   rive.StateMachine? get semanticsStateMachine => myStateMachine;
///
///   @override
///   bool advance(double elapsedSeconds) {
///     final advanced = myAnimation.advanceAndApply(elapsedSeconds);
///     updateSemantics();
///     return advanced;
///   }
/// }
/// ```
@experimental
@internal
base mixin RiveSemanticsMixin on rive.RivePainter {
  /// The state machine to query for semantic diffs.
  rive.StateMachine? get semanticsStateMachine => null;

  SemanticTreeModel? _semanticTree;

  /// The semantic tree model, updated each frame by [updateSemantics].
  /// Null until [semanticsEnabled] is set to `true`.
  SemanticTreeModel? get semanticTree => _semanticTree;

  bool _semanticsEnabled = false;

  /// Whether semantic tree tracking is currently enabled.
  bool get isSemanticsEnabled => _semanticsEnabled;

  /// Enable or disable semantic tree tracking.
  set semanticsEnabled(bool value) {
    if (_semanticsEnabled == value) return;
    _semanticsEnabled = value;
    if (value) {
      semanticsStateMachine?.enableSemantics();
      _semanticTree ??= SemanticTreeModel();
    } else {
      _semanticTree?.dispose();
      _semanticTree = null;
    }
  }

  /// Query the state machine for semantic diffs and apply them to
  /// [semanticTree]. Call this from your `advance` method after advancing
  /// the animation.
  void updateSemantics() {
    final tree = _semanticTree;
    final sm = semanticsStateMachine;
    if (tree == null || sm == null) return;
    final diff = sm.drainSemanticsDiff();
    if (diff.isNotEmpty) {
      tree.applyDiff(diff);
    }
  }

  /// Dispose the semantic tree. Call from your painter's `dispose` method.
  void disposeSemantics() {
    _semanticTree?.dispose();
    _semanticTree = null;
  }
}
