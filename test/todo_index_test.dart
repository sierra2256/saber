import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/home/todo_badge.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/todo.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/todos/todo_index.dart';
import 'package:saber/data/todos/todo_indexer.dart';

import 'utils/fake_handwriting_recognizer.dart';

void main() {
  FlavorConfig.setup();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('todo_index'));
  tearDown(() => dir.deleteSync(recursive: true));
  TodoIndex newIndex() => TodoIndex(file: File('${dir.path}/todo_index.json'));

  IndexedTodo todo({bool closed = false, int id = 0}) =>
      IndexedTodo(kind: .drawn, id: id, pageIndex: 0, top: 0, closed: closed);

  test('Checklist items in typed text are to-dos', () {
    final delta = Delta()
      ..insert('Shopping\n', {'header': 1})
      ..insert('Milk')
      ..insert('\n', {'list': 'unchecked'})
      ..insert('Bread')
      ..insert('\n', {'list': 'checked'})
      ..insert('Just a bullet')
      ..insert('\n', {'list': 'bullet'})
      ..insert('Eggs\n\n', null)
      ..insert('Call mum')
      ..insert('\n', {'list': 'unchecked'});

    final todos = TodoIndexer.typedTodosOf(delta, 2);
    expect(
      [for (final todo in todos) todo.label],
      ['Milk', 'Bread', 'Call mum'],
    );
    expect([for (final todo in todos) todo.closed], [false, true, false]);
    expect(todos.every((todo) => todo.kind == .typed), isTrue);
    expect(todos.every((todo) => todo.pageIndex == 2), isTrue);
    expect(todos[2].top, greaterThan(todos[1].top));
  });

  test('Open to-dos are counted per note and per folder, recursively', () {
    final index = newIndex()
      ..setNote(
        '/work/meeting',
        IndexedNoteTodos(
          stamp: '1',
          todos: [todo(id: 1), todo(id: 2), todo(id: 3, closed: true)],
        ),
      )
      ..setNote(
        '/work/projects/plan',
        IndexedNoteTodos(stamp: '1', todos: [todo()]),
      )
      ..setNote('/workout', IndexedNoteTodos(stamp: '1', todos: [todo()]))
      ..setNote('/home', IndexedNoteTodos(stamp: '1', todos: [todo()]));

    expect(index.openCountOf('/work/meeting'), 2);
    expect(index.openCountOf('/nothing'), 0);
    expect(index.openCountInFolder('/work'), 3, reason: 'Not /workout');
    expect(index.openCountInFolder('/work/projects'), 1);
    expect(index.openCountInFolder(''), 5, reason: 'The root folder');
    expect(index.openCount, 5);
  });

  test('The index is saved and loaded again', () async {
    final index = newIndex()
      ..setNote(
        '/a',
        IndexedNoteTodos(
          stamp: '42:10',
          todos: [
            IndexedTodo(
              kind: .drawn,
              id: 7,
              pageIndex: 1,
              top: 30,
              closed: true,
              closedAt: DateTime(2026, 10, 25),
              label: 'buy milk',
              labelSignature: 99,
            ),
          ],
        ),
      );
    await index.save();
    index.dispose();

    final loaded = newIndex();
    await loaded.load();
    expect(loaded.noteOf('/a')!.stamp, '42:10');
    expect(loaded.noteOf('/a')!.todos, index.noteOf('/a')!.todos);
  });

  group('TodoIndexer', () {
    late Map<String, EditorCoreInfo Function()> notes;
    late Map<String, String> stamps;
    late StreamController<FileOperation> fileOperations;
    late FakeHandwritingRecognizer recognizer;
    late var recognitionEnabled = false;
    late int loads;

    TodoIndexer newIndexer(TodoIndex index) => TodoIndexer(
      index: index,
      recognizer: recognizer,
      loadNote: (filePath) async {
        loads++;
        return notes[filePath]!();
      },
      stampOf: (filePath) async => stamps[filePath],
      fileOperations: fileOperations.stream,
      getAllNotes: () async => notes.keys.toList(),
      recognitionEnabled: () => recognitionEnabled,
      debounce: Duration.zero,
    );

    setUp(() {
      notes = {};
      stamps = {};
      fileOperations = StreamController.broadcast();
      recognizer = FakeHandwritingRecognizer(textForLine: (_) => 'buy milk');
      recognitionEnabled = false;
      loads = 0;
    });
    tearDown(() => fileOperations.close());

    EditorCoreInfo noteWithTodos(String filePath, {bool closeFirst = false}) {
      final page = EditorPage();
      final coreInfo = EditorCoreInfo(filePath: filePath)..pages.add(page);
      page.todos = [
        TodoBox(
          id: 1,
          rect: const Rect.fromLTWH(100, 100, 20, 20),
          closedAt: closeFirst ? DateTime(2026) : null,
        ),
        const TodoBox(id: 2, rect: Rect.fromLTWH(100, 200, 20, 20)),
      ];
      page.strokes.add(_word(page, const Offset(140, 105)));
      return coreInfo;
    }

    test(
      'indexes notes with to-dos, and skips notes that did not change',
      () async {
        notes['/a'] = () => noteWithTodos('/a');
        notes['/empty'] = () => EditorCoreInfo(filePath: '/empty');
        stamps['/a'] = '1';
        stamps['/empty'] = '1';
        final index = newIndex();
        final indexer = newIndexer(index);

        await indexer.start();
        await indexer.idle;
        expect(index.openCountOf('/a'), 2);
        expect(index.noteOf('/empty')!.todos, isEmpty);
        expect(index.noteOf('/a')!.todos.first.label, isNull);
        expect(loads, 2);

        // the app restarts, nothing changed
        await indexer.stop();
        await indexer.start();
        await indexer.idle;
        expect(loads, 2, reason: 'No note is loaded again');

        // the first to-do is closed
        notes['/a'] = () => noteWithTodos('/a', closeFirst: true);
        stamps['/a'] = '2';
        fileOperations.add(const FileOperation(.write, '/a'));
        await Future.delayed(const Duration(milliseconds: 10));
        await indexer.idle;
        expect(index.openCountOf('/a'), 1);

        fileOperations.add(const FileOperation(.delete, '/a'));
        await Future.delayed(const Duration(milliseconds: 10));
        expect(index.noteOf('/a'), isNull);
        await indexer.stop();
      },
    );

    test('recognizes labels when handwriting recognition is on', () async {
      notes['/a'] = () => noteWithTodos('/a');
      stamps['/a'] = '1';
      recognitionEnabled = true;
      final index = newIndex();
      final indexer = newIndexer(index);

      await indexer.start();
      await indexer.idle;
      final todos = index.noteOf('/a')!.todos;
      expect(todos[0].label, 'buy milk');
      expect(todos[1].label, isNull, reason: 'Nothing written next to it');
      final recognized = recognizer.recognizedLines.length;

      // the note changed, but not the label
      stamps['/a'] = '2';
      indexer.enqueue('/a');
      await indexer.idle;
      expect(recognizer.recognizedLines.length, recognized);
      expect(index.noteOf('/a')!.todos[0].label, 'buy milk');

      // turning recognition off forgets the labels
      recognitionEnabled = false;
      indexer.reindexAll();
      await indexer.idle;
      expect(index.noteOf('/a')!.todos[0].label, isNull);
      await indexer.stop();
    });
  });

  testWidgets('The badge shows the open to-dos, and hides when there are '
      'none', (tester) async {
    final index = newIndex();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            TodoBadge.note('/work/a', index: index),
            TodoBadge.folder('/work', index: index),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.check_box_outlined), findsNothing);

    index.setNote(
      '/work/a',
      IndexedNoteTodos(stamp: '1', todos: [todo(id: 1), todo(id: 2)]),
    );
    index.setNote('/work/b', IndexedNoteTodos(stamp: '1', todos: [todo()]));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    index.dispose();
  });
}

/// A handwritten word starting at [start].
Stroke _word(EditorPage page, Offset start) {
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 3),
    pageIndex: 0,
    page: page,
    toolId: .fountainPen,
  );
  for (var i = 0; i < 20; i++) {
    stroke.addPoint(start + Offset(i * 4, (i % 4) * 3));
  }
  return stroke;
}
