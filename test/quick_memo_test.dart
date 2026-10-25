import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/quick_memo.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  FileManager.documentsDirectory =
      '$tmpDir/quick_memo_test/'
      '${FileManager.appRootDirectoryPrefix}';

  Future<EditorState> pumpQuickMemo(
    WidgetTester tester, {
    required Future<void> Function() close,
  }) async {
    setupMockWindowManager();
    stows.editorFingerDrawing.value = false;
    await tester.pumpWidget(MaterialApp(home: QuickMemoPage(close: close)));
    // wait for the memo's path and the editor to load
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final editors = find.byType(Editor);
      if (editors.evaluate().isNotEmpty &&
          tester.state<EditorState>(editors).coreInfo.filePath.isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    final editor = tester.state<EditorState>(find.byType(Editor));
    addTearDown(editor.cancelAutosaveAndMarkSaved);
    return editor;
  }

  test('memos are saved in their own folder', () async {
    final path = await QuickMemoPage.newMemoPath();
    expect(path, startsWith('${QuickMemoPage.folder}/Memo '));
  });

  testWidgets('A quick memo hides anything that reveals other notes', (
    tester,
  ) async {
    final editor = await pumpQuickMemo(tester, close: () async {});
    expect(editor.widget.quickMemo, isTrue);
    expect(editor.coreInfo.filePath, startsWith(QuickMemoPage.folder));

    expect(find.text('Done'), findsOneWidget);
    expect(find.byTooltip('Images'), findsNothing);
    expect(find.byTooltip('Elements'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Split view'), findsNothing);
    expect(find.text('Export (Ctrl Shift S)'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Insert page below'), findsOneWidget);
  });

  testWidgets('Done saves the memo and closes it', (tester) async {
    var closed = false;
    final editor = await pumpQuickMemo(
      tester,
      close: () async => closed = true,
    );
    editor.currentTool = Pen.currentPen;
    await tester.pump();

    final page = editor.coreInfo.pages.first;
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(page.renderBox!.localToGlobal(const Offset(200, 400)));
    for (var i = 0; i < 10; ++i) {
      await gesture.moveBy(const Offset(8, 3));
    }
    await gesture.up();
    await tester.pump();
    expect(page.strokes, hasLength(1));

    await tester.runAsync(editor.finishQuickMemo);
    expect(closed, isTrue);
    expect(
      File(
        FileManager.documentsDirectory +
            editor.coreInfo.filePath +
            Editor.extension,
      ).existsSync(),
      isTrue,
      reason: 'The memo was saved before closing',
    );
  });

  testWidgets('The quick memo app is dark', (tester) async {
    setupMockWindowManager();
    await tester.pumpWidget(TranslationProvider(child: const QuickMemoApp()));
    await tester.pump();
    final context = tester.element(find.byType(QuickMemoPage));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, Colors.black);
    // let the memo load so the test can clean up
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    if (find.byType(Editor).evaluate().isNotEmpty) {
      tester
          .state<EditorState>(find.byType(Editor))
          .cancelAutosaveAndMarkSaved();
    }
  });
}
