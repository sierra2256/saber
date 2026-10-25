import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/handwriting/handwriting_lines.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

import 'utils/fake_handwriting_recognizer.dart';
import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  group('HandwritingLines.group', () {
    test('groups words on the same line, ordered left to right', () {
      final hello = _word(const Offset(100, 100));
      final world = _word(const Offset(200, 105));
      final second = _word(const Offset(100, 200));
      final lines = HandwritingLines.group([world, second, hello]);
      expect(lines, [
        [hello, world],
        [second],
      ]);
    });

    test('a tall stroke does not join two lines', () {
      final line1 = _word(const Offset(100, 100));
      // e.g. a long "g" descending towards the next line
      final tall = _stroke([const Offset(200, 95), const Offset(200, 160)]);
      final line2 = _word(const Offset(100, 170));
      final lines = HandwritingLines.group([line1, tall, line2]);
      expect(lines, hasLength(2));
      expect(lines.first, contains(line1));
      expect(lines.last, contains(line2));
    });
  });

  group('HandwritingRecognizer', () {
    test('only recognizes handwriting', () {
      expect(HandwritingRecognizer.isHandwriting(_word(Offset.zero)), isTrue);
      expect(
        HandwritingRecognizer.isHandwriting(
          _word(Offset.zero, toolId: .highlighter),
        ),
        isFalse,
      );
      expect(
        HandwritingRecognizer.isHandwriting(_word(Offset.zero, toolId: .tape)),
        isFalse,
      );
      expect(
        HandwritingRecognizer.isHandwriting(
          CircleStroke(
            color: Colors.black,
            pressureEnabled: false,
            options: StrokeOptions(),
            pageIndex: 0,
            page: _page,
            toolId: .shapePen,
            center: Offset.zero,
            radius: 10,
          ),
        ),
        isFalse,
      );
    });

    test('recognizes each line with the previous line as context', () async {
      final recognizer = FakeHandwritingRecognizer();
      final text = await recognizer.recognize([
        _word(const Offset(100, 200)),
        _word(const Offset(100, 100)),
        _word(const Offset(100, 100), toolId: .highlighter),
      ]);
      expect(text, 'line 1\nline 2');
      expect(recognizer.recognizedLines, hasLength(2));
      expect(recognizer.recognizedLines[0].preContext, isNull);
      expect(recognizer.recognizedLines[1].preContext, 'line 1');
    });
  });

  testWidgets('Convert a selection to text', (tester) async {
    HandwritingRecognizer.instance = FakeHandwritingRecognizer(
      textForLine: (_) => 'hello world',
    );
    addTearDown(
      () => HandwritingRecognizer.instance = MlKitHandwritingRecognizer(),
    );
    stows.handwritingRecognition.value = true;
    addTearDown(() => stows.handwritingRecognition.value = false);
    FileManager.documentsDirectory =
        '$tmpDir/handwriting_to_text_test/'
        '${FileManager.appRootDirectoryPrefix}';

    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();

    final page = state.coreInfo.pages.first;
    final word = _word(const Offset(300, 400), page: page);
    page.insertStroke(word);

    final select = Select.currentSelect;
    state.currentTool = select;
    select.selectResult = SelectResult(
      pageIndex: 0,
      strokes: [word],
      images: [],
      path: Path()..addRect(const Rect.fromLTWH(250, 350, 200, 150)),
    );
    select.doneSelecting = true;
    tester.element(find.byType(Editor)).markNeedsBuild();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Convert to text'));
    await tester.pumpAndSettle();
    expect(find.text('hello world'), findsOneWidget);

    await tester.tap(find.text('Replace with text'));
    await tester.pumpAndSettle();
    expect(page.strokes, isEmpty);
    expect(page.quill.controller.document.toPlainText(), 'hello world\n');
  });
}

const _page = HasSize(Size(1000, 1400));

Stroke _stroke(
  List<Offset> points, {
  ToolId toolId = .fountainPen,
  HasSize? page,
}) => Stroke(
  color: Colors.black,
  pressureEnabled: false,
  options: StrokeOptions(size: 2, isComplete: true),
  pageIndex: 0,
  page: page ?? _page,
  toolId: toolId,
)..addPoints(points);

/// A small scribble 60 wide and 20 tall, starting at [topLeft].
Stroke _word(
  Offset topLeft, {
  ToolId toolId = .fountainPen,
  EditorPage? page,
}) => _stroke(
  [for (var i = 0; i <= 12; ++i) topLeft + Offset(i * 5.0, i.isEven ? 0 : 20)],
  toolId: toolId,
  page: page,
);
