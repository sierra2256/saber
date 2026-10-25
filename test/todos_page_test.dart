import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/todo.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/todos/todo_index.dart';
import 'package:saber/data/todos/todo_indexer.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/home/todos_page.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  FileManager.documentsDirectory =
      '$tmpDir/todos_page_test/'
      '${FileManager.appRootDirectoryPrefix}';

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('todos_page'));
  tearDown(() => dir.deleteSync(recursive: true));

  TodoIndex newIndex() {
    final index = TodoIndex(file: File('${dir.path}/todo_index.json'))
      ..setNote(
        '/work/meeting',
        IndexedNoteTodos(
          stamp: '1',
          todos: [
            const IndexedTodo(
              kind: .drawn,
              id: 11,
              pageIndex: 1,
              top: 300,
              closed: false,
              label: 'send minutes',
            ),
            IndexedTodo(
              kind: .drawn,
              id: 12,
              pageIndex: 0,
              top: 100,
              closed: true,
              closedAt: DateTime(2026, 10, 20),
              label: 'book room',
            ),
          ],
        ),
      )
      ..setNote(
        '/shopping',
        const IndexedNoteTodos(
          stamp: '1',
          todos: [
            IndexedTodo(
              kind: .typed,
              id: 0,
              pageIndex: 0,
              top: 0,
              closed: false,
              label: 'milk',
            ),
            IndexedTodo(
              kind: .drawn,
              id: 5,
              pageIndex: 0,
              top: 50,
              closed: false,
            ),
          ],
        ),
      )
      ..setNote('/no todos', const IndexedNoteTodos(stamp: '1', todos: []));
    return index;
  }

  testWidgets('Lists to-dos by folder and note, filtered', (tester) async {
    final opened = <(String, IndexedTodo)>[];
    final index = newIndex();
    await tester.pumpWidget(
      MaterialApp(
        home: TodosPage(
          index: index,
          openTodo: (context, filePath, todo) => opened.add((filePath, todo)),
        ),
      ),
    );

    // open to-dos by default
    expect(find.text('send minutes'), findsOneWidget);
    expect(find.text('book room'), findsNothing);
    expect(find.text('milk'), findsOneWidget);
    expect(find.text('To-do'), findsOneWidget, reason: 'No label');
    expect(find.text('Top level'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('meeting'), findsOneWidget);
    expect(find.text('no todos'), findsNothing);
    expect(find.text('Page 2'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Top level')).dy,
      lessThan(tester.getTopLeft(find.text('work')).dy),
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('book room'), findsOneWidget);
    expect(find.text('send minutes'), findsNothing);
    expect(find.textContaining('done'), findsOneWidget, reason: 'The date');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('book room'), findsOneWidget);
    expect(find.text('send minutes'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('book room')).dy,
      lessThan(tester.getTopLeft(find.text('send minutes')).dy),
      reason: 'Sorted by page',
    );

    await tester.tap(find.text('send minutes'));
    expect(opened.single.$1, '/work/meeting');
    expect(opened.single.$2.id, 11);
    expect(opened.single.$2.pageIndex, 1);

    // (disposing the index cancels its pending save)
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });

  testWidgets('Says when everything is done', (tester) async {
    final index = TodoIndex(file: File('${dir.path}/todo_index.json'))
      ..setNote(
        '/a',
        const IndexedNoteTodos(
          stamp: '1',
          todos: [
            IndexedTodo(
              kind: .drawn,
              id: 1,
              pageIndex: 0,
              top: 0,
              closed: true,
            ),
          ],
        ),
      );
    await tester.pumpWidget(MaterialApp(home: TodosPage(index: index)));
    expect(find.text('Nothing left to do.'), findsOneWidget);

    // (disposing the index cancels its pending save)
    await tester.pumpWidget(const SizedBox());
    index.dispose();
  });

  testWidgets('Handwritten labels are drawn as a picture', (tester) async {
    final page = EditorPage();
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: page,
      toolId: .fountainPen,
    );
    for (var i = 0; i < 20; i++) {
      stroke.addPoint(Offset(140 + i * 4, 105 + (i % 4) * 3));
    }
    final bytes = await tester.runAsync(
      () => TodoIndexer.renderLabel([stroke]),
    );
    expect(bytes, isNotNull);
    // a PNG file
    expect(bytes!.sublist(1, 4), 'PNG'.codeUnits);
  });

  testWidgets('Opening a to-do highlights it in the note', (tester) async {
    setupMockWindowManager();
    stows.editorFingerDrawing.value = false;
    const filePath = '/todos_page_test_note';
    final coreInfo = EditorCoreInfo(filePath: filePath)
      ..pages.addAll([EditorPage(), EditorPage()]);
    coreInfo.pages[1].todos = [
      const TodoBox(id: 42, rect: Rect.fromLTWH(100, 900, 24, 24)),
    ];
    await tester.runAsync(() async {
      final (bson, _) = coreInfo.saveToBinary(currentPageIndex: 0);
      await FileManager.writeFile(
        filePath + Editor.extension,
        bson,
        awaitWrite: true,
        alsoUpload: false,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Editor(path: filePath, initialPageIndex: 1, highlightTodo: 42),
      ),
    );
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    for (var i = 0; i < 50 && state.coreInfo.filePath.isEmpty; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    final page = state.coreInfo.pages[1];
    expect(page.todos.single.id, 42);
    expect(page.highlightedTodoId, 42);
    expect(state.coreInfo.pages[0].highlightedTodoId, isNull);

    await tester.pump(EditorState.highlightTodoDuration);
    expect(page.highlightedTodoId, isNull);
  });
}
