import 'package:flutter/gestures.dart';
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
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/data/tools/todo_tool.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  FileManager.documentsDirectory =
      '$tmpDir/todo_test/'
      '${FileManager.appRootDirectoryPrefix}';

  group('TodoBox', () {
    test('JSON round trip', () {
      const open = TodoBox(id: 1, rect: Rect.fromLTWH(10, 20, 24, 24));
      final closed = open.toggled(DateTime(2026, 10, 25, 12));
      expect(TodoBox.fromJson(open.toJson()), open);
      expect(TodoBox.fromJson(closed.toJson()), closed);
      expect(open.toJson().containsKey('c'), isFalse);
      expect(closed.isClosed, isTrue);
      expect(closed.toggled(DateTime.now()).isClosed, isFalse);
    });

    test('only small squares look like boxes', () {
      expect(TodoBox.looksLikeBox(const Rect.fromLTWH(0, 0, 30, 32), 40), true);
      expect(
        TodoBox.looksLikeBox(const Rect.fromLTWH(0, 0, 30, 60), 40),
        false,
        reason: 'Not square',
      );
      expect(
        TodoBox.looksLikeBox(const Rect.fromLTWH(0, 0, 200, 200), 40),
        false,
        reason: 'Too big',
      );
    });

    test('the label is the writing to the right, up to the next box', () {
      const first = TodoBox(id: 1, rect: Rect.fromLTWH(100, 100, 20, 20));
      const second = TodoBox(id: 2, rect: Rect.fromLTWH(400, 100, 20, 20));
      const below = TodoBox(id: 3, rect: Rect.fromLTWH(100, 200, 20, 20));
      final boxes = [first, second, below];

      final word = _scribble(const Offset(140, 105), const Offset(300, 115));
      final afterSecond = _scribble(
        const Offset(440, 105),
        const Offset(600, 115),
      );
      final nextLine = _scribble(
        const Offset(140, 205),
        const Offset(300, 215),
      );
      final leftOfBox = _scribble(const Offset(20, 105), const Offset(80, 115));
      final highlight = _scribble(
        const Offset(140, 105),
        const Offset(300, 115),
        toolId: .highlighter,
      );
      final strokes = [word, afterSecond, nextLine, leftOfBox, highlight];

      expect(first.labelStrokes(strokes, 1000, boxes), [word]);
      expect(second.labelStrokes(strokes, 1000, boxes), [afterSecond]);
      expect(below.labelStrokes(strokes, 1000, boxes), [nextLine]);

      final closed = [first.toggled(DateTime.now()), second, below];
      expect(TodoBox.closedLabelStrokes(strokes, closed, 1000), {word});
    });
  });

  group('File version', () {
    test('notes with to-dos are saved with the new version', () {
      final coreInfo = EditorCoreInfo(filePath: '/todo_version')
        ..pages.add(EditorPage());
      expect(coreInfo.toJson().$1['v'], EditorCoreInfo.lastVersionWithoutTodos);

      coreInfo.pages.first.todos = [
        const TodoBox(id: 5, rect: Rect.fromLTWH(10, 10, 24, 24)),
      ];
      final json = coreInfo.toJson().$1;
      expect(json['v'], EditorCoreInfo.sbnVersion);

      final loaded = EditorCoreInfo.fromJson(
        json,
        filePath: '/todo_version',
        onlyFirstPage: false,
      );
      expect(loaded.readOnly, isFalse);
      expect(loaded.pages.first.todos, coreInfo.pages.first.todos);
    });
  });

  group('Editor', () {
    Future<(EditorState, EditorPage)> pumpEditor(WidgetTester tester) async {
      stows.editorFingerDrawing.value = false;
      await tester.pumpWidget(MaterialApp(home: Editor()));
      final state = tester.state<EditorState>(find.byType(Editor));
      addTearDown(state.cancelAutosaveAndMarkSaved);
      await tester.pump();
      return (state, state.coreInfo.pages.first);
    }

    Future<void> tap(
      WidgetTester tester,
      EditorPage page,
      Offset position, {
      PointerDeviceKind kind = .stylus,
    }) async {
      final gesture = await tester.createGesture(kind: kind);
      await gesture.down(page.renderBox!.localToGlobal(position));
      await gesture.moveBy(const Offset(1, 1));
      await gesture.up();
      await tester.pump();
    }

    testWidgets('The to-do tool places a box, then switches to the pen', (
      tester,
    ) async {
      final (state, page) = await pumpEditor(tester);
      state.currentTool = TodoTool.currentTodoTool;

      await tap(tester, page, const Offset(200, 300));
      expect(page.todos, hasLength(1));
      expect(page.todos.single.rect.center.dx, closeTo(200, 1));
      expect(page.todos.single.isClosed, isFalse);
      expect(state.currentTool, isA<Pen>());

      state.undo();
      expect(page.todos, isEmpty);
      state.redo();
      expect(page.todos, hasLength(1));
    });

    testWidgets('Tapping a box with a finger ticks it, tapping again reopens '
        'it', (tester) async {
      final (state, page) = await pumpEditor(tester);
      page.todos = [
        const TodoBox(id: 7, rect: Rect.fromLTWH(200, 300, 24, 24)),
      ];
      await tester.pump();

      await tap(tester, page, const Offset(212, 312), kind: .touch);
      expect(page.todos.single.isClosed, isTrue);
      expect(page.strokes, isEmpty, reason: 'Tapping a box draws nothing');

      await tap(tester, page, const Offset(212, 312));
      expect(page.todos.single.isClosed, isFalse);

      state.undo();
      expect(page.todos.single.isClosed, isTrue);
      state.undo();
      expect(page.todos.single.isClosed, isFalse);
    });

    testWidgets('Writing over a box with the pen draws a stroke', (
      tester,
    ) async {
      final (state, page) = await pumpEditor(tester);
      state.currentTool = Pen.currentPen;
      page.todos = [
        const TodoBox(id: 7, rect: Rect.fromLTWH(200, 300, 24, 24)),
      ];
      await tester.pump();

      final gesture = await tester.createGesture(kind: .stylus);
      await gesture.down(page.renderBox!.localToGlobal(const Offset(212, 312)));
      for (var i = 0; i < 10; ++i) {
        await gesture.moveBy(const Offset(8, 2));
      }
      await gesture.up();
      await tester.pump();

      expect(page.strokes, hasLength(1));
      expect(page.todos.single.isClosed, isFalse);
    });

    testWidgets('A small square drawn with the shape pen becomes a box', (
      tester,
    ) async {
      final (state, page) = await pumpEditor(tester);
      state.currentTool = ShapePen();

      const square = Rect.fromLTWH(300, 400, 30, 30);
      final corners = [
        square.topLeft,
        square.topRight,
        square.bottomRight,
        square.bottomLeft,
        square.topLeft,
      ];
      Offset global(Offset local) => page.renderBox!.localToGlobal(local);
      final gesture = await tester.createGesture(kind: .stylus);
      await gesture.down(global(corners.first));
      // (the shape recognizer needs plenty of points, like a real stroke)
      // (perfectly straight sides confuse the shape recognizer,
      // so wobble a little like a real hand)
      var n = 0;
      for (var side = 0; side < 4; ++side) {
        for (var i = 1; i <= 20; ++i) {
          final wobble = Offset((++n * 7 % 3) * 0.5, (n * 5 % 3) * 0.5);
          await gesture.moveTo(
            global(
              Offset.lerp(corners[side], corners[side + 1], i / 20)! + wobble,
            ),
          );
        }
      }
      await gesture.moveBy(const Offset(3, 4));
      await gesture.up();
      await tester.pump();

      expect(page.strokes, isEmpty);
      expect(page.todos, hasLength(1));
      expect(page.todos.single.rect.center.dx, closeTo(square.center.dx, 5));
      expect(page.todos.single.rect.width, closeTo(30, 6));
    });

    testWidgets('The eraser removes boxes, and undo brings them back', (
      tester,
    ) async {
      final (state, page) = await pumpEditor(tester);
      const todo = TodoBox(id: 7, rect: Rect.fromLTWH(200, 300, 24, 24));
      page.todos = [todo];
      state.currentTool = Eraser(partial: false, highlighterOnly: false);
      await tester.pump();

      await tap(tester, page, const Offset(212, 312));
      expect(page.todos, isEmpty);

      state.undo();
      expect(page.todos, [todo]);
    });

    testWidgets('The to-do tool is in the insert menu', (tester) async {
      final (state, _) = await pumpEditor(tester);
      await tester.tap(find.byTooltip('Insert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('To-do'));
      await tester.pumpAndSettle();
      expect(state.currentTool, same(TodoTool.currentTodoTool));
    });

    testWidgets('A finger away from a box does nothing', (tester) async {
      final (state, page) = await pumpEditor(tester);
      state.currentTool = TodoTool.currentTodoTool;
      await tap(tester, page, const Offset(500, 500), kind: .touch);
      expect(page.todos, isEmpty);
    });
  });
}

const _page = HasSize(Size(1000, 1400));

/// A horizontal scribble from [from] to [to], like a handwritten word.
Stroke _scribble(Offset from, Offset to, {ToolId toolId = .fountainPen}) =>
    Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: _page,
      toolId: toolId,
    )..addPoints([from, Offset.lerp(from, to, 0.5)!, to]);
