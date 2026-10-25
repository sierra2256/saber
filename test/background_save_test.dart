import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';

void main() {
  FlavorConfig.setup();

  EditorCoreInfo note({int strokes = 3, int pointsPerStroke = 10}) {
    final coreInfo = EditorCoreInfo(filePath: '/note');
    final page = EditorPage();
    coreInfo.pages.add(page);
    for (var s = 0; s < strokes; s++) {
      page.strokes.add(
        Stroke(
          color: Colors.black,
          pressureEnabled: true,
          options: StrokeOptions(size: 3, isComplete: true),
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoints([
          for (var i = 0; i < pointsPerStroke; i++)
            Offset(i.toDouble(), s.toDouble()),
        ]),
      );
    }
    // points with pressure, shapes and an empty page
    page.strokes
      ..add(
        Stroke(
            color: Colors.red,
            pressureEnabled: true,
            options: StrokeOptions(size: 5, isComplete: true),
            pageIndex: 0,
            page: page,
            toolId: .pencil,
          )
          ..addPoint(const Offset(1, 2), 0.25)
          ..addPoint(const Offset(3, 4), 0.75),
      )
      ..add(
        CircleStroke(
          color: Colors.blue,
          pressureEnabled: false,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
          center: const Offset(50, 50),
          radius: 10,
        ),
      )
      ..add(
        RectangleStroke(
          color: Colors.green,
          pressureEnabled: false,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
          rect: const Rect.fromLTWH(10, 10, 30, 40),
        ),
      );
    coreInfo.pages.add(EditorPage());
    return coreInfo;
  }

  test('packed json encodes to exactly the same bytes', () {
    final coreInfo = note();
    final (expected, _) = coreInfo.saveToBinary(currentPageIndex: 0);
    final (json, _) = coreInfo.toJson(packStrokePoints: true);
    final actual = EditorCoreInfo.encodePackedJson(json);
    expect(listEquals(actual, expected), isTrue);
  });

  test(
    'large notes are saved in the background, with the same result',
    () async {
      final coreInfo = note(strokes: 50, pointsPerStroke: 500);
      expect(
        50 * 500,
        greaterThan(EditorCoreInfo.backgroundSaveThreshold),
        reason: 'This note should be big enough to use an isolate',
      );
      final (expected, _) = coreInfo.saveToBinary(currentPageIndex: 0);
      final (actual, _) = await coreInfo.saveToBinaryInBackground(
        currentPageIndex: 0,
      );
      expect(listEquals(actual, expected), isTrue);
    },
  );

  test('changes made while saving are not marked as saved', () {
    EditorHistoryItem item() => EditorHistoryItem(
      type: .draw,
      pageIndex: 0,
      strokes: const [],
      images: const [],
    );
    final history = EditorHistory()..recordChange(item());
    final savedChange = history.lastChange;
    // a change while saving
    history.recordChange(item());
    history.markChangeAsSaved(savedChange);
    expect(history.isCurrentStateSaved, isFalse);

    history.markChangeAsSaved(history.lastChange);
    expect(history.isCurrentStateSaved, isTrue);
  });

  test('page content hash changes when the page changes', () {
    final coreInfo = note();
    final page = coreInfo.pages.first;
    final hash = page.contentHash;
    expect(page.contentHash, hash, reason: 'Stable when nothing changes');

    page.strokes.first.shift(const Offset(5, 0));
    final movedHash = page.contentHash;
    expect(movedHash, isNot(hash));

    page.strokes.first.color = Colors.purple;
    expect(page.contentHash, isNot(movedHash));
  });
}
