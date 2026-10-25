import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keybinder/keybinder.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/editor/split_editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  FileManager.documentsDirectory =
      '$tmpDir/split_view_test/'
      '${FileManager.appRootDirectoryPrefix}';

  Future<(EditorState left, EditorState right)> pumpSplitView(
    WidgetTester tester,
  ) async {
    setupMockWindowManager();
    stows.editorFingerDrawing.value = false;
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: SplitEditorPage(leftPath: '/left', rightPath: '/right'),
      ),
    );
    await tester.pump();
    final editors = tester.stateList<EditorState>(find.byType(Editor)).toList();
    expect(editors, hasLength(2));
    for (final editor in editors) {
      addTearDown(editor.cancelAutosaveAndMarkSaved);
    }
    // wait for both notes to load
    for (var i = 0; i < 50; i++) {
      if (editors.every((e) => e.coreInfo.filePath.isNotEmpty)) break;
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final left = editors.firstWhere((e) => e.coreInfo.filePath == '/left');
    final right = editors.firstWhere((e) => e.coreInfo.filePath == '/right');
    return (left, right);
  }

  Future<void> drawStroke(
    WidgetTester tester,
    EditorState editor, [
    Offset start = const Offset(200, 400),
  ]) async {
    final page = editor.coreInfo.pages.first;
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(page.renderBox!.localToGlobal(start));
    for (var i = 0; i < 10; ++i) {
      await gesture.moveBy(const Offset(8, 3));
    }
    await gesture.up();
    await tester.pump();
  }

  void select(EditorState editor, List<Stroke> strokes) {
    editor.currentTool = Select.currentSelect;
    Select.currentSelect
      ..selectResult = SelectResult(
        pageIndex: 0,
        strokes: List.of(strokes),
        images: [],
        path: Path()..addRect(const Rect.fromLTWH(0, 0, 1000, 1000)),
      )
      ..doneSelecting = true
      ..owner = editor;
  }

  testWidgets('Two notes side by side, each laid out in its own half', (
    tester,
  ) async {
    final (left, right) = await pumpSplitView(tester);

    final leftWidth = MediaQuery.sizeOf(left.context).width;
    final rightWidth = MediaQuery.sizeOf(right.context).width;
    expect(leftWidth, closeTo(rightWidth, 1));
    expect(leftWidth, lessThan(1200 / 2));
    expect(
      tester.getSize(find.byType(Editor).first).width,
      closeTo(leftWidth, 1),
    );
  });

  testWidgets('Drawing and selecting only affect one side', (tester) async {
    final (left, right) = await pumpSplitView(tester);
    left.currentTool = Pen.currentPen;
    right.currentTool = Pen.currentPen;

    await drawStroke(tester, left);
    expect(left.coreInfo.pages.first.strokes, hasLength(1));
    expect(right.coreInfo.pages.first.strokes, isEmpty);

    select(left, left.coreInfo.pages.first.strokes);
    right.currentTool = Select.currentSelect;
    tester.element(find.byType(SplitEditorPage)).markNeedsBuild();
    for (final element in find.byType(Editor).evaluate()) {
      element.markNeedsBuild();
    }
    await tester.pumpAndSettle();

    expect(Select.currentSelect.isDoneSelectingFor(left), isTrue);
    expect(Select.currentSelect.isDoneSelectingFor(right), isFalse);
    expect(
      find.byType(SelectionBar),
      findsOneWidget,
      reason: 'Only the left side shows the selection bar',
    );
  });

  testWidgets('Copy a selection to the other side', (tester) async {
    final (left, right) = await pumpSplitView(tester);
    left.currentTool = Pen.currentPen;
    await drawStroke(tester, left);
    final stroke = left.coreInfo.pages.first.strokes.single;

    select(left, [stroke]);
    left.copySelectionToOtherSide();
    await tester.pump();

    final copied = right.coreInfo.pages.first.strokes;
    expect(copied, hasLength(1));
    expect(copied.single, isNot(same(stroke)));
    expect(copied.single.length, stroke.length);
    expect(left.coreInfo.pages.first.strokes, [stroke], reason: 'Kept');
    expect(
      Select.currentSelect.isDoneSelectingFor(right),
      isTrue,
      reason: 'The copy is selected on the right so it can be moved',
    );
    expect(
      (copied.single.page as EditorPage),
      same(right.coreInfo.pages.first),
    );
  });

  testWidgets('Keyboard shortcuts only go to the side used last', (
    tester,
  ) async {
    // Keybinder keeps its keyboard listener between tests, which the test
    // framework resets, so start from scratch.
    Keybinder.dispose();
    final (left, right) = await pumpSplitView(tester);
    left.currentTool = Pen.currentPen;
    right.currentTool = Pen.currentPen;
    await drawStroke(tester, left);
    await drawStroke(tester, right);
    expect(left.coreInfo.pages.first.strokes, hasLength(1));
    expect(right.coreInfo.pages.first.strokes, hasLength(1));

    // the right side was used last
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(right.coreInfo.pages.first.strokes, isEmpty, reason: 'Undone');
    expect(left.coreInfo.pages.first.strokes, hasLength(1));
  });

  testWidgets('Closing the split view keeps one note open', (tester) async {
    final (left, _) = await pumpSplitView(tester);
    final split = tester.state<SplitEditorPageState>(
      find.byType(SplitEditorPage),
    );

    await tester.runAsync(() async {
      final closing = split.close(keep: left);
      // let the navigator push the new route
      await Future.delayed(const Duration(milliseconds: 100));
      await closing.timeout(const Duration(seconds: 5), onTimeout: () {});
    });
    await tester.pumpAndSettle();

    expect(find.byType(SplitEditorPage), findsNothing);
    final editor = tester.state<EditorState>(find.byType(Editor));
    addTearDown(editor.cancelAutosaveAndMarkSaved);
    expect(editor.widget.initialPath, completion('/left'));
  });
}
