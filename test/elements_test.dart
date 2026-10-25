import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/canvas_element.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/tape.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  FileManager.documentsDirectory =
      '$tmpDir/elements_test/'
      '${FileManager.appRootDirectoryPrefix}';

  Future<EditorState> pumpEditor(WidgetTester tester) async {
    stows.editorFingerDrawing.value = false;
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();
    return state;
  }

  Stroke line(EditorPage page, Offset from, Offset to) => Stroke(
    color: Colors.red,
    pressureEnabled: false,
    options: StrokeOptions(size: 4, isComplete: true),
    pageIndex: 0,
    page: page,
    toolId: .fountainPen,
  )..addPoints([for (var i = 0; i <= 10; ++i) Offset.lerp(from, to, i / 10)!]);

  group('CanvasElement', () {
    final page = EditorPage();

    test('encode and decode', () {
      final element = CanvasElement.fromStrokes([
        line(page, const Offset(100, 100), const Offset(200, 150)),
        CircleStroke(
          color: Colors.blue,
          pressureEnabled: false,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
          center: const Offset(150, 200),
          radius: 20,
        ),
      ]);
      expect(element.bounds.topLeft, Offset.zero);

      final decoded = CanvasElement.decode(element.encode());
      expect(decoded.strokes, hasLength(2));
      expect(decoded.strokes[0].color.toARGB32(), Colors.red.toARGB32());
      expect(decoded.strokes[0].length, element.strokes[0].length);
      expect(decoded.strokes[1], isA<CircleStroke>());
      expect(decoded.bounds.size.width, closeTo(element.bounds.width, 0.01));
    });

    test('instantiate centers the strokes', () {
      final element = CanvasElement.fromStrokes([
        line(page, const Offset(100, 100), const Offset(200, 200)),
      ]);
      final strokes = element.instantiate(
        page: page,
        pageIndex: 3,
        center: const Offset(500, 500),
      );
      final bounds = CanvasElement.boundsOf(strokes);
      expect(bounds.center.dx, closeTo(500, 0.01));
      expect(bounds.center.dy, closeTo(500, 0.01));
      expect(strokes.single.pageIndex, 3);
      expect(strokes.single.page, same(page));
    });
  });

  testWidgets('Save a selection as an element, insert it and paste again', (
    tester,
  ) async {
    stows.savedElements.value = [];
    final state = await pumpEditor(tester);
    final page = state.coreInfo.pages.first;
    final stroke = line(page, const Offset(300, 400), const Offset(400, 450));
    page.insertStroke(stroke);

    // select the stroke and save it
    final select = Select.currentSelect;
    state.currentTool = select;
    select.selectResult = SelectResult(
      pageIndex: 0,
      strokes: [stroke],
      images: [],
      path: Path()..addRect(const Rect.fromLTWH(250, 350, 200, 150)),
    );
    select.doneSelecting = true;
    state.saveSelectionAsElement();
    expect(stows.savedElements.value, hasLength(1));

    // no paste again in the insert menu until something is pasted
    await tester.pump();
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    expect(find.text('Paste again'), findsNothing);
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();

    final element = CanvasElement.decode(stows.savedElements.value.single);
    state.insertElement(element);
    await tester.pump();
    expect(page.strokes, hasLength(2));
    final inserted = page.strokes.firstWhere((s) => s != stroke);
    expect(select.selectResult.strokes, [inserted], reason: 'Selected');
    expect(state.history.canUndo, isTrue);

    // paste again adds another offset copy
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste again'));
    await tester.pumpAndSettle();
    expect(page.strokes, hasLength(3));
    final again = select.selectResult.strokes.single;
    final insertedBounds = CanvasElement.boundsOf([inserted]);
    final againBounds = CanvasElement.boundsOf([again]);
    expect(againBounds.center - insertedBounds.center, const Offset(20, 20));

    state.undo();
    expect(page.strokes, hasLength(2));
  });

  group('Tape', () {
    testWidgets('draws straight tape, and tapping it toggles revealing', (
      tester,
    ) async {
      final state = await pumpEditor(tester);
      final page = state.coreInfo.pages.first;
      state.currentTool = Tape.currentTape;
      await tester.pump();

      Offset global(Offset local) => page.renderBox!.localToGlobal(local);

      // draw a wobbly line of tape
      final gesture = await tester.createGesture(kind: .stylus);
      await gesture.down(global(const Offset(200, 500)));
      for (var i = 1; i <= 10; ++i) {
        await gesture.moveTo(global(Offset(200 + i * 30.0, 500 + (i % 2) * 4)));
      }
      await gesture.up();
      await tester.pump();

      expect(page.strokes, hasLength(1));
      final tape = page.strokes.single;
      expect(tape.toolId, Tape.currentTape.toolId);
      expect(tape.length, 3, reason: 'Converted to a straight line');
      expect(page.revealedTapes, isEmpty);

      Future<void> tap(Offset local) async {
        final gesture = await tester.createGesture(kind: .stylus);
        await gesture.down(global(local));
        await gesture.moveBy(const Offset(1, 0));
        await gesture.up();
        await tester.pump();
      }

      await tap(const Offset(350, 500));
      expect(page.strokes, [tape], reason: 'Tapping does not add tape');
      expect(page.revealedTapes, {tape});

      await tap(const Offset(350, 500));
      expect(page.revealedTapes, isEmpty);
    });
  });
}
