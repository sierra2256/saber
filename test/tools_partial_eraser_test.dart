import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  group('Stroke.splitAround', () {
    test('splits a line in two', () {
      final stroke = _horizontalLine(0, 100);
      final pieces = stroke.splitAround(const Offset(50, 50), 10)!;
      expect(pieces, hasLength(2));

      // radius 10 + half the stroke size (1 / 2)
      expect(pieces[0].points.first.dx, closeTo(0, 0.01));
      expect(pieces[0].points.last.dx, closeTo(39.5, 0.01));
      expect(pieces[1].points.first.dx, closeTo(60.5, 0.01));
      expect(pieces[1].points.last.dx, closeTo(100, 0.01));

      for (final piece in pieces) {
        expect(piece.color, stroke.color);
        expect(piece.toolId, stroke.toolId);
        expect(piece.pageIndex, stroke.pageIndex);
      }
    });

    test('cuts segments even if no points are inside the eraser', () {
      // Only two points, far away from the eraser
      final stroke = _stroke([const Offset(0, 50), const Offset(100, 50)]);
      final pieces = stroke.splitAround(const Offset(50, 50), 10)!;
      expect(pieces, hasLength(2));
    });

    test('erasing the end of a stroke shortens it', () {
      final stroke = _horizontalLine(0, 100);
      final pieces = stroke.splitAround(const Offset(100, 50), 10)!;
      expect(pieces, hasLength(1));
      expect(pieces.single.points.last.dx, closeTo(89.5, 0.01));
    });

    test('returns null if the eraser misses', () {
      final stroke = _horizontalLine(0, 100);
      expect(stroke.splitAround(const Offset(50, 80), 10), isNull);
    });

    test('returns an empty list if the whole stroke is erased', () {
      final stroke = _horizontalLine(45, 55);
      expect(stroke.splitAround(const Offset(50, 50), 10), isEmpty);
    });
  });

  group('Eraser.erasePartially', () {
    test('replaces strokes with their pieces', () {
      final eraser = Eraser(size: 10, partial: true, highlighterOnly: false);
      final stroke = _horizontalLine(0, 100);
      final strokes = [stroke];

      expect(eraser.erasePartially(const Offset(50, 50), strokes), isTrue);
      expect(strokes, hasLength(2));
      expect(strokes, isNot(contains(stroke)));

      // erase more of the left piece during the same drag
      final leftPiece = strokes.first;
      expect(eraser.erasePartially(const Offset(20, 50), strokes), isTrue);
      expect(strokes, hasLength(3));

      final (:erased, :created) = eraser.onPartialDragEnd();
      expect(erased, [stroke], reason: 'Only the original stroke is erased');
      expect(created, hasLength(3));
      expect(created, isNot(contains(leftPiece)));
      expect(created, unorderedEquals(strokes));
    });

    test('erases shapes entirely', () {
      final eraser = Eraser(size: 10, partial: true, highlighterOnly: false);
      final rect = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 1),
        pageIndex: 0,
        page: _page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(10, 10, 80, 80),
      );
      final strokes = <Stroke>[rect];
      expect(eraser.erasePartially(const Offset(10, 15), strokes), isTrue);
      expect(strokes, isEmpty);
    });

    test('highlighter only', () {
      final eraser = Eraser(size: 10, partial: true, highlighterOnly: true);
      final pen = _horizontalLine(0, 100);
      final highlighter = _horizontalLine(0, 100, toolId: .highlighter);
      final strokes = [pen, highlighter];
      expect(eraser.erasePartially(const Offset(50, 50), strokes), isTrue);
      expect(strokes, contains(pen));
      expect(strokes, isNot(contains(highlighter)));
      expect(strokes, hasLength(3));

      final wholeEraser = Eraser(
        size: 10,
        partial: false,
        highlighterOnly: true,
      );
      expect(
        wholeEraser.checkForOverlappingStrokes(const Offset(50, 50), [
          pen,
          highlighter,
        ]),
        [highlighter],
      );
    });
  });

  testWidgets('Partial erasing can be undone and redone', (tester) async {
    FileManager.documentsDirectory =
        '$tmpDir/partial_eraser_test/'
        '${FileManager.appRootDirectoryPrefix}';
    stows.eraserPartial.value = true;
    addTearDown(() => stows.eraserPartial.value = false);

    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();

    final page = state.coreInfo.pages.first;
    // below the floating toolbar
    final stroke = _horizontalLine(0, 100, y: 400);
    page.insertStroke(stroke);

    // erase the middle of the stroke with a stylus
    stows.editorFingerDrawing.value = false;
    state.currentTool = Eraser();
    await tester.pump();
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(page.renderBox!.localToGlobal(const Offset(50, 390)));
    for (var i = 0; i < 10; ++i) {
      await gesture.moveBy(const Offset(0, 2));
    }
    await gesture.up();
    await tester.pump();
    expect(state.history.peekUndo().type, EditorHistoryItemType.replaceStrokes);
    final created = List.of(page.strokes);
    expect(page.strokes, hasLength(2));

    state.undo();
    expect(page.strokes, [stroke]);

    state.redo();
    expect(page.strokes, hasLength(2));
    expect(page.strokes, unorderedEquals(created));
  });
}

const _page = HasSize(Size(100, 100));

Stroke _stroke(List<Offset> points, {ToolId toolId = .fountainPen}) => Stroke(
  color: Colors.black,
  pressureEnabled: false,
  options: StrokeOptions(size: 1, isComplete: true),
  pageIndex: 0,
  page: _page,
  toolId: toolId,
)..addPoints(points);

/// A horizontal line at [y] with a point every 1 unit.
Stroke _horizontalLine(
  double from,
  double to, {
  double y = 50,
  ToolId toolId = .fountainPen,
}) =>
    _stroke([for (var x = from; x <= to; x += 1) Offset(x, y)], toolId: toolId);
