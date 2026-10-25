import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/toolbar/editor_page_manager.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  FileManager.documentsDirectory =
      '$tmpDir/page_sidebar_test/'
      '${FileManager.appRootDirectoryPrefix}';

  Future<EditorState> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();
    return state;
  }

  Stroke strokeOnPage(EditorPage page, int pageIndex) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 4, isComplete: true),
    pageIndex: pageIndex,
    page: page,
    toolId: .fountainPen,
  )..addPoints(const [Offset(10, 10), Offset(50, 50)]);

  testWidgets('The pages button toggles the sidebar', (tester) async {
    await pumpEditor(tester);
    expect(find.byType(EditorPageManager), findsNothing);

    await tester.tap(find.byTooltip('Pages'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorPageManager), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(
      find.byType(EditorPageManager),
      findsNothing,
      reason: 'The hidden sidebar should be offstage',
    );
  });

  testWidgets('Insert a page from the sidebar', (tester) async {
    final state = await pumpEditor(tester);
    final firstPage = state.coreInfo.pages.first;
    firstPage.insertStroke(strokeOnPage(firstPage, 0));
    state.createPage(0);
    expect(state.coreInfo.pages, hasLength(2));

    await tester.tap(find.byTooltip('Pages'));
    await tester.pumpAndSettle();

    // open the first page's menu and insert a page after it
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert page below'));
    await tester.pumpAndSettle();
    expect(state.coreInfo.pages, hasLength(3));
    expect(state.coreInfo.pages.first, same(firstPage));
  });

  testWidgets('Inserting and deleting pages updates page indices', (
    tester,
  ) async {
    final state = await pumpEditor(tester);
    final pages = state.coreInfo.pages;
    state.createPage(1);
    final secondPage = pages[1];
    final stroke = strokeOnPage(secondPage, 1);
    secondPage.insertStroke(stroke);

    state.insertPageAfter(0);
    await tester.pump();
    expect(pages[2], same(secondPage));
    expect(stroke.pageIndex, 2);

    state.undo();
    expect(pages[1], same(secondPage));
    expect(stroke.pageIndex, 1);
  });
}
