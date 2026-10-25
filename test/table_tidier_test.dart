import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/data/tools/table_tidier.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  const frame = Rect.fromLTRB(100, 100, 500, 400);
  RectangleStroke rectangle() => RectangleStroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 3),
    pageIndex: 0,
    page: _page,
    toolId: .shapePen,
    rect: frame,
  );

  group('TableTidier', () {
    test('a new line snaps to the rectangle around it', () {
      // falls short on the left, overshoots on the right
      final line = _line(const Offset(115, 200), const Offset(510, 200));
      final result = TableTidier.tidy(line, [rectangle()]);
      expect(result.changed, isEmpty);
      expect(result.newStroke.centerline.first, const Offset(100, 200));
      expect(result.newStroke.centerline.last, const Offset(500, 200));
    });

    test('lines snap to a rectangle drawn after them', () {
      final row = _line(const Offset(110, 200), const Offset(490, 200));
      final column = _line(const Offset(300, 92), const Offset(300, 415));
      final rect = rectangle();
      final result = TableTidier.tidy(rect, [row, column]);
      expect(result.newStroke, same(rect), reason: 'Rectangles stay as is');
      expect(result.changed.keys, unorderedEquals([row, column]));
      expect(result.changed[row]!.centerline.first, const Offset(100, 200));
      expect(result.changed[row]!.centerline.last, const Offset(500, 200));
      expect(result.changed[column]!.centerline.first, const Offset(300, 100));
      expect(result.changed[column]!.centerline.last, const Offset(300, 400));
    });

    test('a grid of only lines', () {
      final top = _line(const Offset(100, 100), const Offset(500, 100));
      final bottom = _line(const Offset(100, 400), const Offset(500, 400));
      final left = _line(const Offset(100, 100), const Offset(100, 400));
      // a column drawn last, a little short at both ends
      final column = _line(const Offset(300, 110), const Offset(300, 385));
      final result = TableTidier.tidy(column, [top, bottom, left]);
      expect(result.newStroke.centerline.first, const Offset(300, 100));
      expect(result.newStroke.centerline.last, const Offset(300, 400));
      expect(result.changed, isEmpty, reason: 'Other lines already fit');
    });

    test('lines that are far away are left alone', () {
      final line = _line(const Offset(150, 200), const Offset(450, 200));
      final result = TableTidier.tidy(line, [rectangle()]);
      expect(result.newStroke, same(line));

      final outside = _line(const Offset(105, 600), const Offset(495, 600));
      expect(TableTidier.tidy(outside, [rectangle()]).newStroke, same(outside));
    });

    test('only shape pen lines are tidied', () {
      final handwritten = _line(
        const Offset(115, 200),
        const Offset(490, 200),
        toolId: .fountainPen,
      );
      final result = TableTidier.tidy(handwritten, [rectangle()]);
      expect(result.newStroke, same(handwritten));
    });

    test('short lines are not collapsed onto one point', () {
      final short = _line(const Offset(95, 200), const Offset(110, 200));
      expect(TableTidier.tidy(short, [rectangle()]).newStroke, same(short));
    });
  });

  test('convertToLine can skip snapping to horizontal/vertical', () {
    Stroke almostLevel() => Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: _page,
      toolId: .shapePen,
    )..addPoints(const [Offset.zero, Offset(50, 1), Offset(100, 2)]);

    final snapped = almostLevel()..convertToLine();
    expect(snapped.centerline.last, const Offset(100, 0));

    final notSnapped = almostLevel()..convertToLine(snapToAxes: false);
    expect(notSnapped.centerline.last, const Offset(100, 2));
  });

  testWidgets('A shape pen line inside a rectangle snaps to its sides, and '
      'undoing removes it', (tester) async {
    FileManager.documentsDirectory =
        '$tmpDir/table_tidier_test/'
        '${FileManager.appRootDirectoryPrefix}';
    stows.editorFingerDrawing.value = false;

    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();

    final page = state.coreInfo.pages.first;
    final rect = rectangle()..page = page;
    page.insertStroke(rect);
    state.currentTool = ShapePen();
    await tester.pump();

    // draw a roughly straight row across the rectangle
    Offset global(Offset local) => page.renderBox!.localToGlobal(local);
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(global(const Offset(112, 250)));
    // (the shape recognizer needs plenty of points, like a real stroke)
    for (var i = 1; i <= 80; ++i) {
      // rising 3 units over the whole line
      await gesture.moveTo(
        global(Offset(112 + i * 380 / 80, 250 + i * 3 / 80)),
      );
    }
    await gesture.up();
    await tester.pump();

    expect(page.strokes, hasLength(2));
    final row = page.strokes.firstWhere((stroke) => stroke != rect);
    expect(row.centerline.first.dx, 100);
    expect(row.centerline.last.dx, 500);
    expect(row.centerline.first.dy, row.centerline.last.dy);

    state.undo();
    expect(page.strokes, [rect]);
  });
}

const _page = HasSize(Size(1000, 1400));

/// A straight line, like the shape pen makes.
Stroke _line(Offset from, Offset to, {ToolId toolId = .shapePen}) => Stroke(
  color: Colors.black,
  pressureEnabled: false,
  options: StrokeOptions(size: 3),
  pageIndex: 0,
  page: _page,
  toolId: toolId,
)..addPoints([from, to, to]);
