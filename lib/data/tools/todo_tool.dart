import 'package:flutter/material.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

/// Tapping the page with this tool places a to-do box,
/// see [TodoBox].
class TodoTool extends Tool {
  new _();

  static final _currentTodoTool = TodoTool._();
  static TodoTool get currentTodoTool => _currentTodoTool;

  static const todoIcon = Icons.check_box_outlined;

  /// How far (in page pixels) a tap can move and still count as a tap.
  static const maxTapMovement = 10.0;

  @override
  ToolId get toolId => .todo;
}
