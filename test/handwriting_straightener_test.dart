import 'dart:math';

import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/handwriting/handwriting_straightener.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  group('HandwritingStraightener', () {
    test('levels a slanted line', () {
      final words = _line(const Offset(100, 300), rotation: -10 * pi / 180);
      final strokes = words.expand((w) => w).toList();
      final changed = HandwritingStraightener.straighten(strokes);
      expect(changed.keys, unorderedEquals(strokes));

      final centers = [
        for (final word in words) _bounds(word.map((s) => changed[s]!)).center,
      ];
      for (final center in centers) {
        expect(center.dy, closeTo(centers.first.dy, 1));
      }
      // still about as tall as before
      final letter = _bounds([changed[words.first.first]!]);
      expect(letter.height, closeTo(20, 1));
    });

    test('moves bobbing words onto one line', () {
      final words = _line(const Offset(100, 300), wordOffsets: [0, 6, -5, 3]);
      final changed = HandwritingStraightener.straighten(
        words.expand((w) => w),
      );
      final centers = [
        for (final word in words)
          _bounds(word.map((s) => changed[s] ?? s)).center.dy,
      ];
      expect(centers.toSet().length, 1, reason: '$centers');
    });

    test('evens out the gaps between words', () {
      final words = _line(const Offset(100, 300), gaps: [20, 40, 25]);
      final changed = HandwritingStraightener.straighten(
        words.expand((w) => w),
      );
      final bounds = [
        for (final word in words) _bounds(word.map((s) => changed[s] ?? s)),
      ];
      expect(bounds.first.left, 100, reason: 'The first word stays in place');
      for (int i = 1; i < bounds.length; i++) {
        expect(bounds[i].left - bounds[i - 1].right, closeTo(25, 0.01));
      }
    });

    test('keeps big gaps, e.g. between columns', () {
      final words = _line(const Offset(100, 300), gaps: [30, 120]);
      final changed = HandwritingStraightener.straighten(
        words.expand((w) => w),
      );
      expect(changed, isEmpty);
    });

    test('resizes words that are much bigger than the rest', () {
      final words = _line(const Offset(100, 300), sizes: [1, 1, 2, 1]);
      final changed = HandwritingStraightener.straighten(
        words.expand((w) => w),
      );
      final big = _bounds(words[2].map((s) => changed[s]!));
      expect(big.height, lessThan(40 * 0.8));
      expect(big.height, greaterThan(20));
      // the stroke width is scaled with it
      expect(changed[words[2].first]!.options.size, lessThan(2));
      expect(changed[words[0].first], isNull);
    });

    test('leaves neat handwriting alone', () {
      final words = _line(const Offset(100, 300));
      final secondLine = _line(const Offset(100, 400));
      final changed = HandwritingStraightener.straighten([
        ...words.expand((w) => w),
        ...secondLine.expand((w) => w),
      ]);
      expect(changed, isEmpty);
    });

    test('a period stays on the baseline', () {
      final words = _line(const Offset(100, 300), wordOffsets: [0, 8, 0]);
      final period = _stroke(const [Offset(370, 319), Offset(371, 320)]);
      final changed = HandwritingStraightener.straighten([
        ...words.expand((w) => w),
        period,
      ]);
      expect(changed[period], isNull);
    });

    test('keeps slanted lines apart', () {
      const rotation = -12 * pi / 180;
      final first = _line(const Offset(100, 300), rotation: rotation);
      final second = _line(const Offset(100, 345), rotation: rotation);
      expect(
        HandwritingStraightener.groupLines([
          ...first.expand((w) => w),
          ...second.expand((w) => w),
        ]).map((line) => line.toSet()),
        unorderedEquals([
          first.expand((w) => w).toSet(),
          second.expand((w) => w).toSet(),
        ]),
      );
    });

    test('the dot of an "i" moves with its word', () {
      final words = _line(const Offset(100, 300), wordOffsets: [0, 6, -5]);
      // above the first letter of the second word
      final dot = _stroke(const [Offset(196, 296), Offset(197, 297)]);
      final changed = HandwritingStraightener.straighten([
        ...words.expand((w) => w),
        dot,
      ]);
      final letter = words[1].first;
      expect(changed[letter], isNotNull);
      final letterMoved =
          _bounds([changed[letter]!]).top - _bounds([letter]).top;
      final dotMoved = _bounds([changed[dot]!]).top - _bounds([dot]).top;
      expect(dotMoved, closeTo(letterMoved, 0.5));
    });

    test('ignores shapes and highlighter', () {
      final words = _line(const Offset(100, 300), wordOffsets: [0, 6, -5]);
      final highlight = _stroke(const [
        Offset(100, 310),
        Offset(400, 330),
      ], toolId: .highlighter);
      final changed = HandwritingStraightener.straighten([
        ...words.expand((w) => w),
        highlight,
      ]);
      expect(changed, isNotEmpty);
      expect(changed.keys, isNot(contains(highlight)));
    });
  });

  testWidgets('Straighten a selection, then undo', (tester) async {
    FileManager.documentsDirectory =
        '$tmpDir/handwriting_straightener_test/'
        '${FileManager.appRootDirectoryPrefix}';
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pump();

    final page = state.coreInfo.pages.first;
    final strokes = [
      for (final word in _line(const Offset(100, 300), wordOffsets: [0, 6, -5]))
        for (final stroke in word) stroke..page = page,
    ];
    for (final stroke in strokes) {
      page.insertStroke(stroke);
    }

    final select = Select.currentSelect;
    state.currentTool = select;
    select.selectResult = SelectResult(
      pageIndex: 0,
      strokes: List.of(strokes),
      images: [],
      path: Path()..addRect(const Rect.fromLTWH(50, 250, 500, 150)),
    );
    select.doneSelecting = true;
    tester.element(find.byType(Editor)).markNeedsBuild();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Straighten handwriting'));
    await tester.pumpAndSettle();
    expect(page.strokes, hasLength(strokes.length));
    expect(page.strokes, isNot(containsAll(strokes)));
    expect(
      select.selectResult.strokes,
      unorderedEquals(page.strokes),
      reason: 'The straightened strokes stay selected',
    );

    state.undo();
    await tester.pumpAndSettle();
    expect(page.strokes, unorderedEquals(strokes));
  });
}

const _page = HasSize(Size(1000, 1400));

Stroke _stroke(List<Offset> points, {ToolId toolId = .fountainPen}) => Stroke(
  color: Colors.black,
  pressureEnabled: false,
  options: StrokeOptions(size: 2, isComplete: true),
  pageIndex: 0,
  page: _page,
  toolId: toolId,
)..addPoints(points);

/// A line of words, each made of 4 zigzag letters 12 wide and 20 tall
/// (times the word's size) with 4 between them, starting at [topLeft].
///
/// Each word can be moved down by [wordOffsets], and the gaps between
/// words are [gaps] (or 30). The whole line is rotated by [rotation]
/// around [topLeft].
List<List<Stroke>> _line(
  Offset topLeft, {
  double rotation = 0,
  List<double> wordOffsets = const [0, 0, 0, 0],
  List<double>? gaps,
  List<double>? sizes,
}) {
  final wordCount = [
    if (gaps == null && sizes == null) wordOffsets.length,
    if (gaps != null) gaps.length + 1,
    ?sizes?.length,
  ].max;
  Offset rotate(Offset p) {
    final d = p - topLeft;
    return topLeft +
        Offset(
          d.dx * cos(rotation) - d.dy * sin(rotation),
          d.dx * sin(rotation) + d.dy * cos(rotation),
        );
  }

  final words = <List<Stroke>>[];
  var x = topLeft.dx;
  for (int w = 0; w < wordCount; w++) {
    final size = sizes?[w] ?? 1;
    final dy = w < wordOffsets.length ? wordOffsets[w] : 0.0;
    // keep the word centered on the line when resized
    final top = topLeft.dy + dy + 10 - 10 * size;
    final word = <Stroke>[];
    for (int l = 0; l < 4; l++) {
      word.add(
        _stroke([
          for (int i = 0; i <= 6; i++)
            rotate(Offset(x + i * 2 * size, top + (i.isEven ? 0 : 20 * size))),
        ]),
      );
      x += 12 * size + (l < 3 ? 4 : 0);
    }
    words.add(word);
    if (w < wordCount - 1) x += gaps?[w] ?? 30;
  }
  return words;
}

Rect _bounds(Iterable<Stroke> strokes) => strokes
    .expand((s) => s.centerline)
    .map((p) => Rect.fromCenter(center: p, width: 0, height: 0))
    .reduce((a, b) => a.expandToInclude(b));
