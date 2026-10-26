import 'package:meta/meta.dart';

/// Bitmask constants for semantic state flags.
///
/// These map to platform accessibility properties.
/// Bits 0-7 are trait-gated: they are only meaningful when the
/// corresponding [SemanticTrait] is set on the node.
/// Bits 8-13 are non-trait states (binary, always applicable or role-implied).
///
/// ## Checked / Mixed precedence
///
/// [checked] and [mixed] occupy independent bits. A designer may set both
/// on the same `SemanticData` (intentionally or via data-binding error).
/// When both are set, **[mixed] wins** — the node is reported as
/// indeterminate, not checked. Route checked-state queries through
/// [effectiveChecked] rather than testing the raw bit so the rule is
/// centralised.
@experimental
@internal
abstract final class SemanticState {
  // ── Trait-gated states (only meaningful when trait is active) ───────────

  /// Node is currently expanded (requires Expandable trait).
  static const int expanded = 1 << 0;

  /// Node is currently selected (requires Selectable trait).
  static const int selected = 1 << 1;

  /// Node is currently checked (requires Checkable trait). When [mixed]
  /// is also set, Mixed takes precedence — use [effectiveChecked] to
  /// surface state to the platform accessibility API.
  static const int checked = 1 << 2;

  /// Checkbox is in indeterminate/mixed state (requires Checkable trait).
  /// Takes precedence over [checked] when both bits are set.
  static const int mixed = 1 << 3;

  /// Toggle is in the "on" position (requires Toggleable trait).
  static const int toggled = 1 << 4;

  /// Field is required (requires Requirable trait).
  static const int required = 1 << 5;

  /// Node is disabled (requires Enablable trait).
  static const int disabled = 1 << 6;

  /// Node currently has focus (requires Focusable trait).
  static const int focused = 1 << 7;

  // ── Non-trait states (binary, always applicable or role-implied) ────────

  /// Node is hidden from accessibility tree.
  static const int hidden = 1 << 8;

  /// Label changes trigger screen reader announcements.
  static const int liveRegion = 1 << 9;

  /// Text field is read-only.
  static const int readOnly = 1 << 10;

  /// Dialog traps focus within.
  static const int modal = 1 << 11;

  /// Text field content is hidden (password).
  static const int obscured = 1 << 12;

  /// Text field is multi-line.
  static const int multiline = 1 << 13;

  /// Check whether a specific flag is set in a bitmask.
  static bool has(int flags, int flag) => flags & flag != 0;

  /// Returns the effective checked state after applying the Mixed-wins rule.
  /// Prefer this over `SemanticState.has(flags, SemanticState.checked)` when
  /// surfacing state to a platform accessibility API.
  static bool effectiveChecked(int flags) =>
      !has(flags, mixed) && has(flags, checked);

  /// Returns the effective indeterminate/mixed state. Mutually exclusive
  /// with [effectiveChecked] for any given [flags] value.
  static bool effectiveMixed(int flags) => has(flags, mixed);
}
