import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/zoom_writing_box.dart';
import 'package:saber/data/editor/zoom_box.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  group('ZoomBox', () {
    // A writing box 4x wider than it is tall, at 3x magnification
    const boxSize = Size(720, 180);
    ZoomBox create() => ZoomBox(
      pageIndex: 0,
      pageSize: const Size(1000, 1400),
      position: const Offset(50, 100),
      height: 60,
    );

    test('maps writing box positions to the page', () {
      final zoomBox = create();
      expect(zoomBox.scaleFor(boxSize), 3);
      expect(zoomBox.targetFor(boxSize), const Rect.fromLTWH(50, 100, 240, 60));
      expect(
        zoomBox.toPage(const Offset(300, 90), boxSize),
        const Offset(150, 130),
      );
    });

    test('moves forward when writing near the end of the target', () {
      final zoomBox = create();
      // 50% of the way through the target
      expect(zoomBox.advanceAfterStroke(170, boxSize), isFalse);
      expect(zoomBox.position.dx, 50);

      // 80% of the way through the target
      expect(zoomBox.advanceAfterStroke(242, boxSize), isTrue);
      expect(zoomBox.position.dx, 242 - 240 * ZoomBox.advanceTo);
      expect(zoomBox.position.dy, 100);
    });

    test('wraps to the next line at the end of the page', () {
      final zoomBox = create()..position = const Offset(700, 100);
      expect(zoomBox.advanceAfterStroke(960, boxSize), isTrue);
      expect(zoomBox.position, Offset(zoomBox.margin, 160));
    });

    test('manual movement', () {
      final zoomBox = create();
      zoomBox.forward(boxSize);
      expect(zoomBox.position, const Offset(170, 100));
      zoomBox.back(boxSize);
      expect(zoomBox.position, const Offset(50, 100));
      zoomBox.back(boxSize);
      expect(zoomBox.position.dx, 0, reason: "Can't move past the page edge");
      zoomBox.newLine();
      expect(zoomBox.position, Offset(zoomBox.margin, 160));
      zoomBox.lineUp();
      expect(zoomBox.position, Offset(zoomBox.margin, 100));
    });
  });

  testWidgets('Writing in the zoom box draws small on the page', (
    tester,
  ) async {
    FileManager.documentsDirectory =
        '$tmpDir/zoom_box_test/'
        '${FileManager.appRootDirectoryPrefix}';
    stows.editorFingerDrawing.value = false;

    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();

    // open the zoom box from the overflow menu
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom writing box'));
    await tester.pumpAndSettle();
    expect(find.byType(ZoomWritingBox), findsOneWidget);

    final page = state.coreInfo.pages.first;
    final zoomBox = state.zoomBox!;
    expect(page.zoomBoxTarget, isNotNull, reason: 'Target is shown on page');

    // write a stroke across the box
    final boxRect = tester.getRect(find.byKey(ZoomWritingBox.stripKey));
    final boxSize = boxRect.size;
    final target = zoomBox.targetFor(boxSize);
    final gesture = await tester.createGesture(kind: .stylus);
    await gesture.down(boxRect.centerLeft + const Offset(20, 0));
    for (var i = 1; i <= 10; ++i) {
      await gesture.moveBy(const Offset(10, 2));
    }
    await gesture.up();
    await tester.pump();

    expect(page.strokes, hasLength(1));
    final strokeBounds = page.strokes.single.lowQualityPath.getBounds();
    expect(
      target.inflate(10).contains(strokeBounds.center),
      isTrue,
      reason: 'Stroke should be in the target area',
    );
    expect(
      strokeBounds.width,
      lessThan(100 / zoomBox.scaleFor(boxSize) + 20),
      reason: 'Stroke should be drawn smaller than it was written',
    );

    // close it again
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(ZoomWritingBox), findsNothing);
    expect(page.zoomBoxTarget, isNull);
  });
}
