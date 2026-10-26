/// Edge behavior for focus traversal within a scope.
enum EdgeBehavior {
  /// Focus exits to parent scope's next focusable.
  parentScope(0),

  /// Focus wraps from last to first within this scope.
  closedLoop(1),

  /// Focus stays on boundary element.
  stop(2);

  const EdgeBehavior(this.value);

  /// The native value for this edge behavior.
  final int value;

  /// Create an EdgeBehavior from a native value.
  static EdgeBehavior fromValue(int value) {
    return EdgeBehavior.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EdgeBehavior.parentScope,
    );
  }

  String get uiStringKey => switch (this) {
    EdgeBehavior.parentScope => 'parent_scope',
    EdgeBehavior.closedLoop => 'closed_loop',
    EdgeBehavior.stop => 'stop',
  };
}
