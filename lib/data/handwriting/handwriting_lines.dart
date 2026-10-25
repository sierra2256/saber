import 'dart:math';
import 'dart:ui';

import 'package:saber/components/canvas/_stroke.dart';

/// Groups handwritten strokes into lines of text,
/// since handwriting is recognized one line at a time.
abstract final class HandwritingLines {
  /// Strokes are on the same line if they overlap vertically
  /// by at least this fraction of the shorter of the two heights.
  static const minOverlap = 0.4;

  /// Returns the lines of [strokes], from top to bottom,
  /// with the strokes in each line ordered from left to right.
  static List<List<Stroke>> group(Iterable<Stroke> strokes) {
    final sorted = strokes.toList()
      ..sort((a, b) => _bounds(a).center.dy.compareTo(_bounds(b).center.dy));

    final lines = <_Line>[];
    for (final stroke in sorted) {
      final bounds = _bounds(stroke);
      _Line? bestLine;
      var bestOverlap = 0.0;
      for (final line in lines) {
        final overlap = line.overlapWith(bounds);
        if (overlap > bestOverlap) {
          bestLine = line;
          bestOverlap = overlap;
        }
      }
      if (bestLine != null && bestOverlap >= minOverlap) {
        bestLine.add(stroke, bounds);
      } else {
        lines.add(_Line(stroke, bounds));
      }
    }

    lines.sort((a, b) => a.top.compareTo(b.top));
    return [
      for (final line in lines)
        line.strokes
          ..sort((a, b) => _bounds(a).left.compareTo(_bounds(b).left)),
    ];
  }

  static Rect boundsOf(Iterable<Stroke> strokes) {
    Rect? bounds;
    for (final stroke in strokes) {
      final strokeBounds = _bounds(stroke);
      bounds = bounds?.expandToInclude(strokeBounds) ?? strokeBounds;
    }
    return bounds ?? Rect.zero;
  }

  static Rect _bounds(Stroke stroke) => stroke.lowQualityPath.getBounds();
}

class _Line {
  new(Stroke stroke, Rect bounds)
    : strokes = [stroke],
      top = bounds.top,
      bottom = bounds.bottom,
      _heights = [bounds.height];

  final List<Stroke> strokes;
  double top, bottom;

  /// The heights of the strokes in this line, sorted.
  final List<double> _heights;

  /// A typical stroke height in this line, so that one tall stroke
  /// (e.g. a "g" or an underline) doesn't swallow the next line.
  double get _medianHeight => _heights[_heights.length ~/ 2];

  /// The vertical band of the line's typical strokes.
  double get _bandTop => (top + bottom) / 2 - _medianHeight / 2;
  double get _bandBottom => (top + bottom) / 2 + _medianHeight / 2;

  double overlapWith(Rect bounds) {
    final overlap = min(_bandBottom, bounds.bottom) - max(_bandTop, bounds.top);
    if (overlap <= 0) return 0;
    final shorter = min(_medianHeight, bounds.height);
    if (shorter <= 0) return 1;
    return overlap / shorter;
  }

  void add(Stroke stroke, Rect bounds) {
    strokes.add(stroke);
    top = min(top, bounds.top);
    bottom = max(bottom, bounds.bottom);
    _heights
      ..add(bounds.height)
      ..sort();
  }
}
