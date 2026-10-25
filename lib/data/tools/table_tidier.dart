import 'dart:ui';

import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// Tidies hand-drawn tables: when a horizontal or vertical line drawn
/// with the shape pen ends near a perpendicular line or a rectangle,
/// the end is snapped exactly onto it, so the table becomes a clean grid.
///
/// This works in both directions, so tables can be drawn in any order:
/// a new line snaps to the lines it touches, and the lines whose ends
/// touch a new line or rectangle are snapped to it.
abstract final class TableTidier {
  /// How far (in page units) the end of a line can be from another line,
  /// either short of it or overshooting it, to snap onto it.
  static const snapDistance = 25.0;

  /// Snaps [newStroke] and the lines in [strokes] to each other.
  ///
  /// Returns the (possibly changed) new stroke, and a map from
  /// the strokes in [strokes] that changed to their replacements.
  /// [strokes] isn't modified.
  static ({Stroke newStroke, Map<Stroke, Stroke> changed}) tidy(
    Stroke newStroke,
    List<Stroke> strokes,
  ) {
    final others = [
      for (final stroke in strokes)
        if (stroke != newStroke) ...GridLine.allOf(stroke),
    ];

    // Snap the new line to the existing lines it touches
    var tidiedNewStroke = newStroke;
    if (GridLine.lineOf(newStroke) case final newLine?) {
      final snapped = newLine.snapEndsTo(others);
      if (snapped != newLine) tidiedNewStroke = snapped.toStroke();
    }

    // Snap the existing lines that touch the new line or rectangle
    final newLines = GridLine.allOf(tidiedNewStroke);
    final changed = <Stroke, Stroke>{};
    if (newLines.isNotEmpty) {
      for (final other in others) {
        if (!other.isMovable) continue;
        final snapped = other.snapEndsTo(newLines);
        if (snapped != other) changed[other.stroke] = snapped.toStroke();
      }
    }

    return (newStroke: tidiedNewStroke, changed: changed);
  }
}

/// A horizontal or vertical line, which is either a line drawn with the
/// shape pen or one side of a rectangle.
class GridLine {
  const new({
    required this.stroke,
    required this.horizontal,
    required this.position,
    required this.start,
    required this.end,
    required this.isMovable,
  }) : assert(start <= end);

  /// The stroke this line belongs to.
  final Stroke stroke;
  final bool horizontal;

  /// The y coordinate of a horizontal line, or x of a vertical line.
  final double position;

  /// Where the line starts and ends along its axis.
  final double start, end;

  /// Whether the line's ends can be snapped.
  /// The sides of rectangles can't be moved.
  final bool isMovable;

  /// Returns [stroke] as a line if it's a horizontal or vertical line
  /// drawn with the shape pen.
  static GridLine? lineOf(Stroke stroke) {
    if (stroke.toolId != .shapePen || stroke is RectangleStroke) return null;
    final points = stroke.centerline;
    // straightened lines have 2 points, with the last one repeated
    if (points.length < 2 || points.length > 3) return null;
    final a = points.first, b = points.last;
    if (a.dy == b.dy && a.dx != b.dx) {
      return GridLine(
        stroke: stroke,
        horizontal: true,
        position: a.dy,
        start: a.dx < b.dx ? a.dx : b.dx,
        end: a.dx < b.dx ? b.dx : a.dx,
        isMovable: true,
      );
    } else if (a.dx == b.dx && a.dy != b.dy) {
      return GridLine(
        stroke: stroke,
        horizontal: false,
        position: a.dx,
        start: a.dy < b.dy ? a.dy : b.dy,
        end: a.dy < b.dy ? b.dy : a.dy,
        isMovable: true,
      );
    }
    return null;
  }

  /// Returns the line of [stroke] (see [lineOf]),
  /// or the four sides if it's a rectangle.
  static List<GridLine> allOf(Stroke stroke) {
    if (stroke is RectangleStroke) {
      final rect = stroke.rect;
      GridLine side(bool horizontal, double position) => GridLine(
        stroke: stroke,
        horizontal: horizontal,
        position: position,
        start: horizontal ? rect.left : rect.top,
        end: horizontal ? rect.right : rect.bottom,
        isMovable: false,
      );
      return [
        side(true, rect.top),
        side(true, rect.bottom),
        side(false, rect.left),
        side(false, rect.right),
      ];
    }
    final line = lineOf(stroke);
    return line == null ? const [] : [line];
  }

  /// Returns a copy of this line with each end snapped to the nearest
  /// perpendicular line in [lines] that it touches, if any.
  GridLine snapEndsTo(List<GridLine> lines) {
    double snapEnd(double end) {
      var best = end;
      var bestDistance = TableTidier.snapDistance;
      for (final line in lines) {
        if (line.horizontal == horizontal) continue;
        if (identical(line.stroke, stroke)) continue;
        // this line must be within the other line's span
        if (position < line.start - TableTidier.snapDistance ||
            position > line.end + TableTidier.snapDistance) {
          continue;
        }
        final distance = (line.position - end).abs();
        if (distance <= bestDistance) {
          best = line.position;
          bestDistance = distance;
        }
      }
      return best;
    }

    final newStart = snapEnd(start);
    final newEnd = snapEnd(end);
    // don't collapse a short line onto a single point
    if (newEnd - newStart < TableTidier.snapDistance) return this;
    if (newStart == start && newEnd == end) return this;
    return GridLine(
      stroke: stroke,
      horizontal: horizontal,
      position: position,
      start: newStart,
      end: newEnd,
      isMovable: isMovable,
    );
  }

  Stroke toStroke() => horizontal
      ? stroke.copyAsLine(Offset(start, position), Offset(end, position))
      : stroke.copyAsLine(Offset(position, start), Offset(position, end));
}
