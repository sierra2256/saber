import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/toolbar/quick_options.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';

void main() {
  FlavorConfig.setup();
  setUp(() => stows.widthPresets.value = const {});

  group('WidthPresets', () {
    test('default width is the middle preset', () {
      for (final pen in [
        Pen.fountainPen(),
        Pen.ballpointPen(),
        Pencil(),
        Highlighter(),
      ]) {
        final presets = WidthPresets.of(pen);
        expect(presets, hasLength(3));
        expect(
          presets[1],
          pen.options.size,
          reason: '${pen.toolId} default size should be the middle preset',
        );
        for (final size in presets) {
          expect(size, inInclusiveRange(pen.sizeMin, pen.sizeMax));
        }
      }
    });

    test('presets are stored per tool type', () {
      WidthPresets.set(Pen.fountainPen(), 0, 3);
      expect(WidthPresets.of(Pen.fountainPen()), [3, 5, 10]);
      expect(WidthPresets.of(Pen.ballpointPen()), [
        3,
        5,
        10,
      ], reason: 'Pens share presets');
      expect(WidthPresets.of(Pencil()), WidthPresets.defaults['pencil']);
      expect(
        WidthPresets.of(Highlighter()),
        WidthPresets.defaults['highlighter'],
      );
    });

    test('presets stay sorted', () {
      WidthPresets.set(Pencil(), 0, 12);
      expect(WidthPresets.of(Pencil()), [5, 9, 12]);
    });
  });

  testWidgets('Long-press a width dot to set it to the current width', (
    tester,
  ) async {
    final pen = Pen.fountainPen()..options = Pen.fountainPenOptions;
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => QuickSizes(
              axis: .horizontal,
              pen: pen,
              onChanged: () => setState(() => changes++),
            ),
          ),
        ),
      ),
    );

    final dots = find.byType(InkWell);
    expect(dots, findsNWidgets(3));

    // tap the thickest dot
    await tester.tap(dots.at(2));
    await tester.pump();
    expect(pen.options.size, 10);

    // choose a custom width, then save it as the fine preset
    pen.options.size = 7;
    await tester.longPress(dots.at(0));
    await tester.pump();
    expect(changes, 2);
    expect(WidthPresets.of(pen), [5, 7, 10]);
  });
}
