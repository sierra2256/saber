import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/toolbar/pen_radial_menu.dart';
import 'package:saber/components/toolbar/quick_options.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  FileManager.documentsDirectory =
      '$tmpDir/pen_menu_test/'
      '${FileManager.appRootDirectoryPrefix}';

  Future<EditorState> pumpEditor(WidgetTester tester) async {
    setupMockWindowManager();
    stows.editorFingerDrawing.value = false;
    stows.stylusButtonDoublePress.value = true;
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final editor = tester.state<EditorState>(find.byType(Editor));
    addTearDown(editor.cancelAutosaveAndMarkSaved);
    await tester.pump();
    editor.setTool(Pen.ofType(.fountainPen));
    await tester.pump();
    return editor;
  }

  const position = Offset(400, 600);

  Finder inMenu(Finder finder) =>
      find.descendant(of: find.byType(PenRadialMenu), matching: finder);

  /// Presses and releases the stylus button, [ms] milliseconds in.
  void click(EditorState editor, int ms) {
    editor.onStylusButtonChanged(true, position, Duration(milliseconds: ms));
    editor.onStylusButtonChanged(
      false,
      position,
      Duration(milliseconds: ms + 50),
    );
  }

  testWidgets('Pressing the stylus button twice opens the pen menu', (
    tester,
  ) async {
    final editor = await pumpEditor(tester);
    click(editor, 1000);
    click(editor, 1250);
    await tester.pump();

    expect(find.byType(PenRadialMenu), findsOneWidget);
    expect(
      editor.currentTool,
      isA<Pen>(),
      reason: 'The temporary eraser is cancelled',
    );
    expect(
      tester.getCenter(find.byKey(PenRadialMenu.circleKey)),
      within(distance: 1, from: position),
      reason: 'The menu is where the stylus is',
    );

    // pressing twice again closes it
    click(editor, 3000);
    click(editor, 3200);
    await tester.pump();
    expect(find.byType(PenRadialMenu), findsNothing);
  });

  testWidgets('Slow presses or touching the screen in between do nothing', (
    tester,
  ) async {
    final editor = await pumpEditor(tester);
    click(editor, 1000);
    click(editor, 2000);
    await tester.pump();
    expect(find.byType(PenRadialMenu), findsNothing);

    // press, touch the screen, press
    click(editor, 5000);
    final page = editor.coreInfo.pages.first;
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(page.renderBox!.localToGlobal(const Offset(200, 400)));
    await gesture.moveBy(const Offset(5, 5));
    await gesture.up();
    await tester.pump();
    click(editor, 5200);
    await tester.pump();
    expect(find.byType(PenRadialMenu), findsNothing);
  });

  testWidgets('The pen menu can be turned off', (tester) async {
    final editor = await pumpEditor(tester);
    stows.stylusButtonDoublePress.value = false;
    addTearDown(() => stows.stylusButtonDoublePress.value = true);
    click(editor, 1000);
    click(editor, 1200);
    await tester.pump();
    expect(find.byType(PenRadialMenu), findsNothing);
  });

  testWidgets('Pick a color, thickness and pen in the menu', (tester) async {
    final editor = await pumpEditor(tester);
    editor.togglePenMenu(position);
    await tester.pump();

    final colors = QuickColors.colorsUpTo(7);
    await tester.tap(
      find.descendant(
        of: find.byType(PenRadialMenu),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              (widget.decoration as BoxDecoration?)?.color == colors[1],
        ),
      ),
    );
    await tester.pump();
    expect((editor.currentTool as Pen).color, colors[1]);

    final sizes = WidthPresets.of(editor.currentTool as Pen);
    await tester.tap(inMenu(find.byTooltip('Size: ${sizes.last.round()}')));
    await tester.pump();
    expect((editor.currentTool as Pen).options.size, sizes.last);

    await tester.tap(inMenu(find.byTooltip('Highlighter')));
    await tester.pump();
    expect(editor.currentTool, isA<Highlighter>());
    expect(find.byType(PenRadialMenu), findsOneWidget, reason: 'Stays open');

    await tester.tap(inMenu(find.byTooltip('Eraser')));
    await tester.pump();
    expect(editor.currentTool, isA<Eraser>());
    expect(
      inMenu(find.byTooltip('Size: ${Eraser.sizePresets.last.round()}')),
      findsOneWidget,
      reason: 'Eraser sizes are shown for the eraser',
    );

    // tapping outside closes the menu
    await tester.tapAt(const Offset(20, 1100));
    await tester.pump();
    expect(find.byType(PenRadialMenu), findsNothing);
  });

  testWidgets('The menu stays on screen near the edges', (tester) async {
    final editor = await pumpEditor(tester);
    editor.togglePenMenu(const Offset(5, 5));
    await tester.pump();
    final menu = tester.getRect(find.byKey(PenRadialMenu.circleKey));
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.top, greaterThanOrEqualTo(0));
  });
}
