import 'package:flutter/material.dart';
import 'package:saber/data/todos/todo_index.dart';
import 'package:saber/data/todos/todo_indexer.dart';
import 'package:saber/i18n/strings.g.dart';

/// Shows how many open to-dos a note (or all notes in a folder) has,
/// or nothing if there are none.
class TodoBadge extends StatelessWidget {
  /// The open to-dos in the note at [filePath].
  const new note(this.filePath, {super.key, this.index}) : folderPath = null;

  /// The open to-dos in all notes in [folderPath] and its subfolders.
  const new folder(this.folderPath, {super.key, this.index}) : filePath = null;

  final String? filePath;
  final String? folderPath;

  /// The index to count from, defaults to [TodoIndexer.appIndex].
  final TodoIndex? index;

  @override
  Widget build(BuildContext context) {
    final index = this.index ?? TodoIndexer.appIndex;
    if (index == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: index,
      builder: (context, _) {
        final count = filePath != null
            ? index.openCountOf(filePath!)
            : index.openCountInFolder(folderPath!);
        if (count == 0) return const SizedBox.shrink();

        final colorScheme = ColorScheme.of(context);
        return Tooltip(
          message: t.todos.openCount(n: count),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Row(
                mainAxisSize: .min,
                children: [
                  Icon(
                    Icons.check_box_outlined,
                    size: 14,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
