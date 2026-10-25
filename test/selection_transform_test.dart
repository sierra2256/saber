import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  group('Stroke.transformed', () {
    test('scales points and width around the pivot', () {
      final stroke = _line(const Offset(10, 10), const Offset(20, 10));
      final scaled = stroke.transformed(pivot: const Offset(10, 10), scale: 2);
      expect(scaled.points.first.dx, closeTo(10, 1e-9));
      expect(scaled.points.last.dx, closeTo(30, 1e-9));
      expect(scaled.options.size, stroke.options.size * 2);
      expect(stroke.points.last.dx, 20, reason: 'Original is unchanged');
    });

    test('rotates points around the pivot', () {
      final stroke = _line(const Offset(10, 0), const Offset(20, 0));
      final rotated = stroke.transformed(pivot: Offset.zero, rotation: pi / 2);
      expect(rotated.points.first.dx, closeTo(0, 1e-9));
      expect(rotated.points.first.dy, closeTo(10, 1e-9));
      expect(rotated.options.size, stroke.options.size);
    });

    test('circles keep their shape', () {
      final circle = CircleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 2),
        pageIndex: 0,
        page: _page,
        toolId: .shapePen,
        center: const Offset(50, 50),
        radius: 10,
      );
      final scaled = circle.transformed(pivot: Offset.zero, scale: 0.5);
      expect(scaled.center, const Offset(25, 25));
      expect(scaled.radius, 5);
    });

    test('rotated rectangles become normal strokes', () {
      final rect = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 2),
        pageIndex: 0,
        page: _page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(0, 0, 10, 10),
      );
      final scaled = rect.transformed(pivot: Offset.zero, scale: 2);
      expect(scaled, isA<RectangleStroke>());
      expect(
        (scaled as RectangleStroke).rect,
        const Rect.fromLTWH(0, 0, 20, 20),
      );

      final rotated = rect.transformed(pivot: Offset.zero, rotation: pi / 4);
      expect(rotated, isNot(isA<RectangleStroke>()));
      expect(rotated.isEmpty, isFalse);
    });
  });

  group('SelectionHandle.hitTest', () {
    final selection = SelectResult(
      pageIndex: 0,
      strokes: [_line(const Offset(100, 100), const Offset(200, 200))],
      images: [],
      path: Path(),
    );
    final bounds = SelectionHandle.boundsOf(selection)!;

    test('finds corner handles', () {
      expect(
        SelectionHandle.hitTest(bounds.topLeft, selection, 1),
        SelectionHandle.topLeft,
      );
      expect(
        SelectionHandle.hitTest(
          bounds.bottomRight + const Offset(5, 5),
          selection,
          1,
        ),
        SelectionHandle.bottomRight,
      );
    });

    test('finds the rotate handle', () {
      expect(
        SelectionHandle.hitTest(
          SelectionHandle.rotate.positionIn(bounds, 1),
          selection,
          1,
        ),
        SelectionHandle.rotate,
      );
    });

    test('misses the middle of the selection', () {
      expect(SelectionHandle.hitTest(bounds.center, selection, 1), isNull);
    });

    test('touch radius depends on zoom', () {
      final position = bounds.topLeft - const Offset(20, 0);
      expect(SelectionHandle.hitTest(position, selection, 1), isNotNull);
      expect(SelectionHandle.hitTest(position, selection, 4), isNull);
    });
  });

  testWidgets('Resize a selection by dragging a corner, then undo', (
    tester,
  ) async {
    FileManager.documentsDirectory =
        '$tmpDir/selection_transform_test/'
        '${FileManager.appRootDirectoryPrefix}';
    stows.editorFingerDrawing.value = false;

    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();

    final page = state.coreInfo.pages.first;
    final stroke = _line(const Offset(200, 400), const Offset(300, 500));
    page.insertStroke(stroke);

    // select the stroke
    final select = Select.currentSelect;
    state.currentTool = select;
    select.selectResult = SelectResult(
      pageIndex: 0,
      strokes: [stroke],
      images: [],
      path: Path()..addRect(const Rect.fromLTWH(150, 350, 200, 200)),
    );
    select.doneSelecting = true;
    await tester.pump();

    final bounds = SelectionHandle.boundsOf(select.selectResult)!;

    // drag the bottom-right corner to double the size
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(page.renderBox!.localToGlobal(bounds.bottomRight));
    final target = bounds.topLeft + (bounds.bottomRight - bounds.topLeft) * 2;
    for (var i = 1; i <= 10; ++i) {
      await gesture.moveTo(
        page.renderBox!.localToGlobal(
          Offset.lerp(bounds.bottomRight, target, i / 10)!,
        ),
      );
    }
    await gesture.up();
    await tester.pump();

    expect(page.strokes, hasLength(1));
    final resized = page.strokes.single;
    expect(resized, isNot(same(stroke)));
    expect(resized.options.size, closeTo(stroke.options.size * 2, 0.01));
    final newBounds = SelectionHandle.boundsOf(select.selectResult)!;
    expect(newBounds.width, closeTo(bounds.width * 2, 1));
    expect(newBounds.topLeft.dx, closeTo(bounds.topLeft.dx, 1));

    expect(state.history.peekUndo().type, EditorHistoryItemType.replaceStrokes);
    state.undo();
    expect(page.strokes, [stroke]);
    state.redo();
    expect(page.strokes, [resized]);
  });
}

const _page = HasSize(Size(1000, 1000));

Stroke _line(Offset from, Offset to) => Stroke(
  color: Colors.black,
  pressureEnabled: false,
  options: StrokeOptions(size: 4, isComplete: true),
  pageIndex: 0,
  page: _page,
  toolId: .fountainPen,
)..addPoints([for (var i = 0; i <= 10; ++i) Offset.lerp(from, to, i / 10)!]);
