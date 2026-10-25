import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/home/todo_badge.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/todos/todo_index.dart';
import 'package:saber/data/todos/todo_indexer.dart';
import 'package:saber/i18n/strings.g.dart';

/// Which to-dos [TodosPage] lists.
enum TodoFilter { open, done, all }

/// A button for the home page app bars that opens [TodosPage],
/// showing how many to-dos are open.
class TodosButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final index = TodoIndexer.appIndex;
    Widget button(int openCount) => IconButton(
      tooltip: t.todos.title,
      icon: Badge(
        isLabelVisible: openCount > 0,
        label: Text('$openCount'),
        child: const Icon(Icons.checklist),
      ),
      onPressed: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TodosPage())),
    );
    if (index == null) return button(0);
    return ListenableBuilder(
      listenable: index,
      builder: (context, _) => button(index.openCount),
    );
  }
}

/// Lists the to-dos in all notes, grouped by folder and note.
///
/// To-dos are closed in the note itself: tapping one opens the note
/// at its page, with the to-do highlighted.
class TodosPage extends StatefulWidget {
  const new({super.key, this.indexer, this.index, this.openTodo});

  /// Defaults to [TodoIndexer.instance].
  final TodoIndexer? indexer;

  /// Defaults to the [indexer]'s index.
  final TodoIndex? index;

  /// Opens the note at [filePath] at [todo]. By default, this opens
  /// the editor.
  final void Function(BuildContext context, String filePath, IndexedTodo todo)?
  openTodo;

  @override
  State<TodosPage> createState() => _TodosPageState();
}

class _TodosPageState extends State<TodosPage> {
  var filter = TodoFilter.open;

  TodoIndexer? get indexer => widget.indexer ?? TodoIndexer.instance;
  TodoIndex? get index => widget.index ?? indexer?.index;

  void _open(String filePath, IndexedTodo todo) {
    if (widget.openTodo case final openTodo?) {
      return openTodo(context, filePath, todo);
    }
    context.push(
      RoutePaths.editFilePath(
        filePath,
        pageIndex: todo.pageIndex,
        highlightTodo: todo.kind == .drawn ? todo.id : null,
      ),
    );
  }

  bool _matches(IndexedTodo todo) => switch (filter) {
    .open => !todo.closed,
    .done => todo.closed,
    .all => true,
  };

  @override
  Widget build(BuildContext context) {
    final index = this.index;
    return Scaffold(
      appBar: AppBar(title: Text(t.todos.title)),
      body: Column(
        children: [
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<TodoFilter>(
              segments: [
                ButtonSegment(value: .open, label: Text(t.todos.filter.open)),
                ButtonSegment(value: .done, label: Text(t.todos.filter.done)),
                ButtonSegment(value: .all, label: Text(t.todos.filter.all)),
              ],
              selected: {filter},
              onSelectionChanged: (selected) =>
                  setState(() => filter = selected.single),
            ),
          ),
          Expanded(
            child: index == null
                ? _buildEmpty(context, anyTodos: false)
                : ListenableBuilder(
                    listenable: index,
                    builder: (context, _) => _buildList(context, index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, {required bool anyTodos}) {
    return Center(
      child: Padding(
        padding: const .all(32),
        child: Text(
          !anyTodos
              ? t.todos.empty
              : switch (filter) {
                  .open => t.todos.allDone,
                  .done => t.todos.noneDone,
                  .all => t.todos.empty,
                },
          textAlign: .center,
          style: TextTheme.of(context).bodyLarge,
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, TodoIndex index) {
    // folder -> note -> to-dos
    final folders = <String, Map<String, List<IndexedTodo>>>{};
    var anyTodos = false;
    for (final MapEntry(key: filePath, value: note) in index.notes.entries) {
      if (note.todos.isNotEmpty) anyTodos = true;
      final todos = note.todos.where(_matches).toList();
      if (todos.isEmpty) continue;
      todos.sort((a, b) {
        final byPage = a.pageIndex.compareTo(b.pageIndex);
        if (byPage != 0) return byPage;
        final byKind = a.kind.index.compareTo(b.kind.index);
        if (byKind != 0) return byKind;
        return a.top.compareTo(b.top);
      });
      folders.putIfAbsent(p.posix.dirname(filePath), () => {})[filePath] =
          todos;
    }
    if (folders.isEmpty) return _buildEmpty(context, anyTodos: anyTodos);

    final textTheme = TextTheme.of(context);
    final colorScheme = ColorScheme.of(context);
    final children = <Widget>[];
    for (final folder in folders.keys.toList()..sort(_comparePaths)) {
      children.add(
        Padding(
          padding: const .fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Icon(Icons.folder, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folder == '/' ? t.todos.topLevel : folder.substring(1),
                  style: textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      );
      final notes = folders[folder]!;
      for (final filePath in notes.keys.toList()..sort(_comparePaths)) {
        children.add(
          Padding(
            padding: const .fromLTRB(48, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.posix.basename(filePath),
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TodoBadge.note(filePath, index: index),
              ],
            ),
          ),
        );
        for (final todo in notes[filePath]!) {
          children.add(_buildTodo(context, filePath, todo));
        }
      }
    }
    return ListView(padding: const .only(bottom: 32), children: children);
  }

  Widget _buildTodo(BuildContext context, String filePath, IndexedTodo todo) {
    final colorScheme = ColorScheme.of(context);
    final closedAt = todo.closedAt;
    return ListTile(
      key: ValueKey('todo $filePath ${todo.kind.name} ${todo.id}'),
      contentPadding: const .only(left: 40, right: 16),
      leading: Icon(
        todo.closed ? Icons.check_box : Icons.check_box_outline_blank,
        color: todo.closed ? const Color(0xFF2E9E4F) : null,
      ),
      title: _buildLabel(context, filePath, todo),
      subtitle: Text(
        [
          t.todos.page(n: todo.pageIndex + 1),
          if (closedAt != null)
            t.todos.doneOn(
              date: MaterialLocalizations.of(context).formatShortDate(closedAt),
            ),
        ].join(' · '),
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      onTap: () => _open(filePath, todo),
    );
  }

  Widget _buildLabel(BuildContext context, String filePath, IndexedTodo todo) {
    final closedStyle = TextStyle(
      decoration: TextDecoration.lineThrough,
      color: ColorScheme.of(context).onSurfaceVariant,
    );
    if (todo.label case final label?) {
      return Text(label, style: todo.closed ? closedStyle : null);
    }
    if (indexer?.labelImageOf(filePath, todo) case final image?) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Opacity(
          opacity: todo.closed ? 0.5 : 1,
          child: DecoratedBox(
            // handwriting is usually dark, so keep it on white
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const .all(2),
              child: Image.file(
                image,
                height: 32,
                fit: BoxFit.contain,
                alignment: AlignmentDirectional.centerStart,
                errorBuilder: (context, _, _) =>
                    Text(t.todos.unlabeled, style: closedStyle),
              ),
            ),
          ),
        ),
      );
    }
    return Text(
      t.todos.unlabeled,
      style: (todo.closed ? closedStyle : const TextStyle()).copyWith(
        fontStyle: FontStyle.italic,
      ),
    );
  }

  static int _comparePaths(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}
