import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/toolbar/favorite_pens.dart';
import 'package:saber/components/toolbar/quick_options.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/favorite_pen.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:sbn/tool_id.dart';

void main() {
  FlavorConfig.setup();
  setUp(() => stows.favoritePens.value = const []);

  test('FavoritePen json round trip', () {
    const favorite = FavoritePen(
      toolId: .highlighter,
      color: Color(0x64FFEB3B),
      size: 40,
    );
    final json = jsonDecode(jsonEncode([favorite])) as List;
    final decoded = FavoritePen.fromJson(json.single as Map<String, dynamic>);
    expect(decoded, favorite);
  });

  test('FavoritePen.apply switches pen type, color and size', () {
    Pen.currentPen = Pen.fountainPen();
    const favorite = FavoritePen(
      toolId: .ballpointPen,
      color: Colors.blue,
      size: 3,
    );
    final pen = favorite.apply();
    expect(pen.toolId, ToolId.ballpointPen);
    expect(Pen.currentPen, same(pen));
    expect(pen.color, Colors.blue);
    expect(pen.options.size, 3);
    expect(favorite.matches(pen), isTrue);

    final highlighter = const FavoritePen(
      toolId: .highlighter,
      color: Color(0x64FFEB3B),
      size: 40,
    ).apply();
    expect(highlighter, same(Highlighter.currentHighlighter));
    expect(highlighter.options.size, 40);
  });

  testWidgets('Add, use and remove favorite pens', (tester) async {
    Tool currentTool = Pen.currentPen = Pen.fountainPen()
      ..color = Colors.red
      ..options.size = 7;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FavoritePens(
              axis: .horizontal,
              currentTool: currentTool,
              setTool: (tool) => setState(() => currentTool = tool),
              invert: false,
              padding: .zero,
            ),
          ),
        ),
      ),
    );

    // save the current pen as a favorite
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pump();
    expect(stows.favoritePens.value, [
      const FavoritePen(toolId: .fountainPen, color: Colors.red, size: 7),
    ]);
    expect(
      find.byIcon(Icons.star_border),
      findsNothing,
      reason: "Can't add the same favorite twice",
    );

    // switch to another tool, then tap the favorite to switch back
    Pen.currentPen.color = Colors.black;
    Pen.currentPen.options.size = 2;
    currentTool = Select.currentSelect;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FavoritePens(
              axis: .horizontal,
              currentTool: currentTool,
              setTool: (tool) => setState(() => currentTool = tool),
              invert: false,
              padding: .zero,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(QuickOption).first);
    await tester.pump();
    expect(currentTool, isA<Pen>());
    expect((currentTool as Pen).color, Colors.red);
    expect((currentTool as Pen).options.size, 7);

    // long-press to remove it
    await tester.longPress(find.byType(QuickOption).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(stows.favoritePens.value, isEmpty);
  });
}
