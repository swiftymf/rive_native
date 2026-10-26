import 'package:meta/meta.dart';

/// Bitmask constants for semantic trait flags.
///
/// Traits sit between [SemanticRole] and [SemanticState]: they declare what
/// *capabilities* a semantic node has. A state flag is only meaningful when
/// its corresponding trait is set.
///
/// Example: a button with the [expandable] trait can be expanded or
/// collapsed. Without the trait the expanded state bit is ignored by the
/// platform accessibility layer.
@experimental
@internal
abstract final class SemanticTrait {
  /// Node can be expanded / collapsed (disclosure).
  static const int expandable = 1 << 0;

  /// Node can be selected / unselected.
  static const int selectable = 1 << 1;

  /// Node can be checked / unchecked (checkbox, radio).
  static const int checkable = 1 << 2;

  /// Node can be toggled on / off (switch).
  static const int toggleable = 1 << 3;

  /// Node can be marked as required / optional (form field).
  static const int requirable = 1 << 4;

  /// Node has an enabled / disabled concept.
  /// Without this trait, the disabled state bit is ignored and the platform
  /// sees the node as neither enabled nor disabled.
  static const int enablable = 1 << 5;

  /// Node can receive focus. Auto-set by the runtime when a sibling
  /// FocusData exists.
  static const int focusable = 1 << 6;

  /// Check whether a specific trait is set in a bitmask.
  static bool has(int flags, int trait) => flags & trait != 0;
}
