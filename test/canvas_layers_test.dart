import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  testWidgets('Drawing only repaints the current stroke, not every stroke', (
    tester,
  ) async {
    FileManager.documentsDirectory =
        '$tmpDir/canvas_layers_test/'
        '${FileManager.appRootDirectoryPrefix}';
    stows.editorFingerDrawing.value = false;

    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();
    state.currentTool = Pen.currentPen;

    final page = state.coreInfo.pages.first;
    var strokesRepaints = 0;
    var overlayRepaints = 0;
    page.strokesListenable.addListener(() => strokesRepaints++);
    page.addListener(() => overlayRepaints++);

    Future<void> drag() async {
      final gesture = await tester.createGesture(kind: .stylus);
      await gesture.down(page.renderBox!.localToGlobal(const Offset(200, 400)));
      for (var i = 0; i < 20; ++i) {
        await gesture.moveBy(const Offset(10, 2));
      }
      await gesture.up();
      await tester.pump();
    }

    await drag();
    expect(page.strokes, hasLength(1));
    expect(overlayRepaints, greaterThan(10), reason: 'Current stroke redraws');
    expect(strokesRepaints, 0, reason: "Committed strokes don't redraw");

    // erasing changes the committed strokes, so they do redraw
    state.currentTool = Eraser(size: 10, partial: false);
    await tester.pump();
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(page.renderBox!.localToGlobal(const Offset(200, 400)));
    await gesture.moveBy(const Offset(5, 1));
    await gesture.up();
    await tester.pump();
    expect(page.strokes, isEmpty);
    expect(strokesRepaints, greaterThan(0));
  });
}
