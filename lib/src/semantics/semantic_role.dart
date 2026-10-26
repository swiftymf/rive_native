import 'package:meta/meta.dart';

@experimental
@internal
enum SemanticRole {
  none(0),

  // Actions
  button(1),
  link(2),

  // Controls
  checkbox(3),
  switchControl(4),
  slider(5),
  textField(6),

  // Content
  text(7),
  image(8),

  // Structure
  group(9),
  list(10),
  listItem(11),

  // Navigation
  tab(12),
  tabList(13),

  // Phase 2
  dialog(14),
  alertDialog(15),
  radioGroup(16),
  radioButton(17);

  const SemanticRole(this.value);
  final int value;

  static SemanticRole fromValue(int value) {
    return SemanticRole.values.firstWhere(
      (r) => r.value == value,
      orElse: () => SemanticRole.none,
    );
  }
}
