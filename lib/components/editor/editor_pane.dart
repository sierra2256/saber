import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tells an editor whether it's the active one, when there are
/// two editors side by side (see [SplitEditorPage]).
///
/// Keyboard shortcuts only apply to the active editor.
/// Without an [EditorPane] (i.e. a single editor), the editor is active.
class EditorPane extends InheritedWidget {
  const new({super.key, required this.isActive, required super.child});

  final ValueListenable<bool> isActive;

  /// Whether the editor at [context] is active.
  ///
  /// This doesn't rebuild [context] when it changes,
  /// so it's meant for callbacks like keyboard shortcuts.
  static bool isActiveAt(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditorPane>()?.isActive.value ??
      true;

  @override
  bool updateShouldNotify(EditorPane oldWidget) =>
      isActive != oldWidget.isActive;
}
