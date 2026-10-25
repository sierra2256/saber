import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/multi_finger_tap_detector.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  group('MultiFingerTapDetector', () {
    late List<int> taps;
    late MultiFingerTapDetector detector;
    setUp(() {
      taps = [];
      detector = MultiFingerTapDetector(onTap: taps.add);
    });

    void down(int pointer, Offset position, int ms) => detector.onPointerDown(
      PointerDownEvent(
        pointer: pointer,
        position: position,
        timeStamp: Duration(milliseconds: ms),
      ),
    );
    void move(int pointer, Offset position, int ms) => detector.onPointerMove(
      PointerMoveEvent(
        pointer: pointer,
        position: position,
        timeStamp: Duration(milliseconds: ms),
      ),
    );
    void up(int pointer, int ms) => detector.onPointerUp(
      PointerUpEvent(
        pointer: pointer,
        timeStamp: Duration(milliseconds: ms),
      ),
    );

    test('two-finger tap', () {
      down(1, const Offset(100, 100), 0);
      down(2, const Offset(200, 100), 20);
      up(1, 100);
      expect(taps, isEmpty, reason: 'Not all fingers have lifted yet');
      up(2, 110);
      expect(taps, [2]);
    });

    test('three-finger tap', () {
      down(1, const Offset(100, 100), 0);
      down(2, const Offset(200, 100), 10);
      down(3, const Offset(300, 100), 20);
      up(2, 100);
      up(1, 110);
      up(3, 120);
      expect(taps, [3]);
    });

    test('single-finger tap is ignored', () {
      down(1, const Offset(100, 100), 0);
      up(1, 50);
      expect(taps, isEmpty);
    });

    test('slow taps are ignored', () {
      down(1, const Offset(100, 100), 0);
      down(2, const Offset(200, 100), 10);
      up(1, 400);
      up(2, 410);
      expect(taps, isEmpty);
    });

    test('pinch-zooming is ignored', () {
      down(1, const Offset(100, 100), 0);
      down(2, const Offset(200, 100), 10);
      move(1, const Offset(80, 100), 50);
      move(2, const Offset(220, 100), 50);
      up(1, 100);
      up(2, 110);
      expect(taps, isEmpty);
    });

    test('tiny movements are allowed', () {
      down(1, const Offset(100, 100), 0);
      down(2, const Offset(200, 100), 10);
      move(1, const Offset(102, 101), 50);
      up(1, 100);
      up(2, 110);
      expect(taps, [2]);
    });

    test('a cancelled gesture does not affect the next one', () {
      down(1, const Offset(100, 100), 0);
      down(2, const Offset(200, 100), 10);
      move(2, const Offset(300, 100), 50);
      up(1, 100);
      up(2, 110);
      expect(taps, isEmpty);

      down(3, const Offset(100, 100), 1000);
      down(4, const Offset(200, 100), 1010);
      up(3, 1100);
      up(4, 1110);
      expect(taps, [2]);
    });

    test('stylus pointers are ignored', () {
      detector.onPointerDown(const PointerDownEvent(pointer: 1, kind: .stylus));
      detector.onPointerDown(const PointerDownEvent(pointer: 2, kind: .stylus));
      detector.onPointerUp(const PointerUpEvent(pointer: 1, kind: .stylus));
      detector.onPointerUp(const PointerUpEvent(pointer: 2, kind: .stylus));
      expect(taps, isEmpty);
    });
  });

  group('Editor multi-finger taps', () {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/multi_finger_tap_test/'
        '${FileManager.appRootDirectoryPrefix}';

    for (final fingerDrawing in const [false, true]) {
      testWidgets('two-finger tap undoes, three-finger tap redoes '
          '(fingerDrawing: $fingerDrawing)', (tester) async {
        stows.editorFingerDrawing.value = fingerDrawing;
        await tester.pumpWidget(
          MaterialApp(home: Editor(path: '/multi-finger-tap')),
        );
        final editorState = tester.state<EditorState>(find.byType(Editor));
        addTearDown(editorState.cancelAutosaveAndMarkSaved);
        await tester.pump();
        final page = editorState.coreInfo.pages.first;
        final center = tester.getCenter(find.byType(Editor));

        // draw a stroke with a stylus
        final stylus = await tester.createGesture(kind: .stylus);
        await stylus.down(center);
        for (var i = 0; i < 10; ++i) {
          await stylus.moveBy(const Offset(5, 5));
        }
        await stylus.up();
        await tester.pump();
        expect(page.strokes, hasLength(1));

        Future<void> tap(int fingers) async {
          final gestures = [
            for (var i = 0; i < fingers; ++i)
              await tester.startGesture(
                center + Offset(i * 50, 0),
                pointer: 100 + i,
              ),
          ];
          await tester.pump(const Duration(milliseconds: 20));
          for (final gesture in gestures) {
            await gesture.moveBy(const Offset(2, 2));
          }
          for (final gesture in gestures) {
            await gesture.up();
          }
          await tester.pump();
        }

        await tap(2);
        expect(page.strokes, isEmpty, reason: 'Two-finger tap should undo');
        expect(find.text('Undo'), findsOneWidget, reason: 'Shows a hint');

        await tap(3);
        expect(page.strokes, hasLength(1), reason: 'Three-finger tap redoes');
        expect(find.text('Redo'), findsOneWidget, reason: 'Shows a hint');

        // let the hint disappear
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Redo'), findsNothing);
      });
    }
  });
}
