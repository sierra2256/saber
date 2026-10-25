import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// Tape covers parts of a page (e.g. answers when studying)
/// and can be tapped to reveal what's underneath.
///
/// Tape is always drawn as a straight band on top of everything else.
/// Whether a piece of tape is revealed isn't saved,
/// see [EditorPage.revealedTapes].
class Tape extends Pen {
  new()
    : super(
        name: t.editor.pens.tape,
        sizeMin: 10,
        sizeMax: 80,
        sizeStep: 5,
        icon: tapeIcon,
        options: StrokeOptions(
          size: 30,
          thinning: 0,
          smoothing: 0,
          streamline: 0,
          simulatePressure: false,
        ),
        pressureEnabled: false,
        color: defaultColor,
        toolId: .tape,
      );

  static var currentTape = Tape();

  static const tapeIcon = FontAwesomeIcons.tape;
  static const defaultColor = Color(0xFFF2C14E);

  /// The opacity of revealed tape, so it's clear where the tape is.
  static const revealedAlpha = 40;

  /// The maximum length of a gesture for it to count as a tap
  /// (to reveal tape) instead of drawing new tape.
  static const maxTapLength = 8.0;

  /// Returns whether [stroke] is short enough to be a tap.
  static bool isTap(Stroke stroke) {
    final bounds = stroke.lowQualityPath.getBounds();
    return bounds.width - stroke.options.size <= maxTapLength &&
        bounds.height - stroke.options.size <= maxTapLength;
  }

  /// Returns the topmost tape on [page] at [position], if any.
  static Stroke? tapeAt(EditorPage page, Offset position) {
    for (final stroke in page.strokes.reversed) {
      if (stroke.toolId != .tape) continue;
      if (stroke.lowQualityPath.contains(position)) return stroke;
    }
    return null;
  }

  /// Reveals [tape] if it's hidden, or hides it again if it's revealed.
  static void toggleRevealed(EditorPage page, Stroke tape) {
    if (!page.revealedTapes.remove(tape)) page.revealedTapes.add(tape);
  }
}
