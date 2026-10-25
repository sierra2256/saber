import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/handwriting/handwriting_lines.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';

/// Makes handwriting look neater while keeping it handwritten,
/// like "Straighten" in Samsung Notes:
/// - slanted lines are rotated to be level,
/// - the words in each line are moved onto a common center line,
/// - words that are much bigger or smaller than the rest are resized
///   towards the typical size, and
/// - the gaps between words are evened out.
abstract final class HandwritingStraightener {
  /// Lines that slope more than this (in radians) are probably
  /// meant to be diagonal, so they aren't leveled.
  static const maxSlope = 25 * pi / 180;

  /// Lines that slope less than this (in radians) are already level.
  static const minSlope = 0.5 * pi / 180;

  /// A gap between strokes wider than this many [_Line.bodyHeight]s
  /// separates two words.
  static const wordGap = 0.75;

  /// Gaps wider than this many target gaps are kept as they are,
  /// since they're probably intentional, e.g. between columns.
  static const maxGapToEven = 3.0;

  /// Words are resized by at most this factor (or its inverse).
  static const maxResize = 1.4;

  /// Straightens the handwriting in [strokes].
  /// Other strokes (e.g. shapes and highlighter) are ignored.
  ///
  /// Returns a map from the strokes that changed to their replacements.
  /// [strokes] aren't modified.
  static Map<Stroke, Stroke> straighten(Iterable<Stroke> strokes) {
    final lines = [
      for (final line in groupLines(
        strokes.where(HandwritingRecognizer.isHandwriting).toList(),
      ))
        _Line(line),
    ];
    if (lines.isEmpty) return const {};

    for (final line in lines) {
      line.level();
    }

    final targetHeight = _median([
      for (final line in lines)
        for (final word in line.words)
          if (word.canResizeIn(line)) word.bodyHeight,
    ]);
    final targetGap = _median(lines.expand((line) => line.gaps).toList());

    final changed = <Stroke, Stroke>{};
    for (final line in lines) {
      if (targetHeight != null) line.resizeWords(targetHeight);
      line.alignWords();
      if (targetGap != null) line.spaceWords(targetGap);
      changed.addAll(line.transformedStrokes());
    }
    return changed;
  }

  /// Strokes in the same line overlap vertically by at least this
  /// fraction of the shorter of the two heights.
  static const minOverlap = 0.4;

  /// Strokes further right than this many typical stroke heights
  /// from the end of a line start a new line, e.g. in another column.
  static const maxLineGap = 3.0;

  /// Groups [strokes] into lines of text.
  ///
  /// Unlike [HandwritingLines.group], this follows each line from left
  /// to right, so lines that slope a lot are still found as one line.
  @visibleForTesting
  static List<List<Stroke>> groupLines(List<Stroke> strokes) {
    if (strokes.isEmpty) return const [];
    final bounds = {
      for (final stroke in strokes) stroke: stroke.lowQualityPath.getBounds(),
    };
    final height = _median([for (final b in bounds.values) b.height])!;

    final lines = <_LineGroup>[];
    for (final stroke in strokes.sorted(
      (a, b) => bounds[a]!.left.compareTo(bounds[b]!.left),
    )) {
      final b = bounds[stroke]!;
      _LineGroup? best;
      var bestOverlap = minOverlap;
      for (final line in lines) {
        if (b.left - line.right > maxLineGap * height) continue;
        // compare with the end of the line, which may have drifted
        // up or down from its start if the line slopes
        final center = line.tailCenter;
        final overlap =
            min(center + height / 2, b.bottom) -
            max(center - height / 2, b.top);
        if (overlap <= 0) continue;
        final shorter = min(height, b.height);
        final fraction = shorter <= 0 ? 1.0 : overlap / shorter;
        if (fraction >= bestOverlap) {
          best = line;
          bestOverlap = fraction;
        }
      }
      if (best != null) {
        best.add(stroke, b);
      } else {
        lines.add(_LineGroup(stroke, b));
      }
    }

    // Small "lines" are usually dots and accents above or below a line
    // (e.g. on an "i"), so they move along with the nearest line.
    final lineHeight = _median([for (final l in lines) l.bounds.height])!;
    final small = [
      for (final line in lines)
        if (line.bounds.height < lineHeight / 2) line,
    ];
    for (final line in small) {
      final nearest = lines
          .where(
            (other) =>
                !small.contains(other) &&
                other.bounds.left <= line.bounds.right &&
                other.bounds.right >= line.bounds.left,
          )
          .map(
            (other) => (
              line: other,
              distance: (other.bounds.center.dy - line.bounds.center.dy).abs(),
            ),
          )
          .where((other) => other.distance < lineHeight)
          .sorted((a, b) => a.distance.compareTo(b.distance))
          .firstOrNull;
      if (nearest == null) continue;
      nearest.line.strokes.addAll(line.strokes);
      lines.remove(line);
    }

    return [for (final line in lines) line.strokes];
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    values.sort();
    return values[values.length ~/ 2];
  }

  /// The [fraction] quantile of the y coordinates of [points],
  /// where each point is weighted by the length of the stroke around it,
  /// so that slowly drawn parts (with more points) don't count more.
  static double _quantileY(List<_WeightedPoint> points, double fraction) {
    final sorted = points.sorted((a, b) => a.y.compareTo(b.y));
    final total = sorted.fold(0.0, (sum, p) => sum + p.weight);
    var cumulative = 0.0;
    for (final point in sorted) {
      cumulative += point.weight;
      if (cumulative >= total * fraction) return point.y;
    }
    return sorted.last.y;
  }
}

class _LineGroup {
  new(Stroke stroke, Rect bounds)
    : strokes = [stroke],
      bounds = bounds,
      _recentCenters = [bounds.center.dy];

  final List<Stroke> strokes;
  Rect bounds;
  final List<double> _recentCenters;

  double get right => bounds.right;

  /// The vertical center of the last few strokes.
  double get tailCenter => _recentCenters.average;

  void add(Stroke stroke, Rect strokeBounds) {
    strokes.add(stroke);
    bounds = bounds.expandToInclude(strokeBounds);
    _recentCenters.add(strokeBounds.center.dy);
    if (_recentCenters.length > 3) _recentCenters.removeAt(0);
  }
}

typedef _WeightedPoint = ({double x, double y, double weight});

/// A stroke and the transform that will be applied to it:
/// rotated by [rotation] around [pivot], then scaled by [scale]
/// around [anchor], then shifted by [offset].
class _StrokeTransform {
  new(this.stroke) : points = _weightedPoints(stroke.centerline);

  final Stroke stroke;

  /// The points of the stroke, transformed as far as decided so far.
  List<_WeightedPoint> points;

  var pivot = Offset.zero;
  var rotation = 0.0;
  var anchor = Offset.zero;
  var scale = 1.0;
  var offset = Offset.zero;

  double get left => points.map((p) => p.x).min;
  double get right => points.map((p) => p.x).max;

  bool get isIdentity => rotation == 0 && scale == 1 && offset == Offset.zero;

  Stroke apply() {
    if (isIdentity) return stroke;
    // transformed() rotates and scales around the same pivot,
    // so make up for scaling around [anchor] instead with a shift.
    return stroke.transformed(pivot: pivot, scale: scale, rotation: rotation)
      ..shift((anchor - pivot) * (1 - scale) + offset);
  }

  void rotate(Offset pivot, double rotation) {
    this.pivot = pivot;
    this.rotation = rotation;
    final c = cos(rotation), s = sin(rotation);
    points = [
      for (final p in points)
        (
          x: pivot.dx + (p.x - pivot.dx) * c - (p.y - pivot.dy) * s,
          y: pivot.dy + (p.x - pivot.dx) * s + (p.y - pivot.dy) * c,
          weight: p.weight,
        ),
    ];
  }

  void resize(Offset anchor, double scale) {
    this.anchor = anchor;
    this.scale = scale;
    points = [
      for (final p in points)
        (
          x: anchor.dx + (p.x - anchor.dx) * scale,
          y: anchor.dy + (p.y - anchor.dy) * scale,
          weight: p.weight * scale,
        ),
    ];
  }

  void move(Offset delta) {
    offset += delta;
    points = [
      for (final p in points)
        (x: p.x + delta.dx, y: p.y + delta.dy, weight: p.weight),
    ];
  }

  /// Gives each point half the length of its neighboring segments.
  static List<_WeightedPoint> _weightedPoints(List<Offset> centerline) {
    if (centerline.length == 1) {
      final p = centerline.single;
      return [(x: p.dx, y: p.dy, weight: 1)];
    }
    return [
      for (int i = 0; i < centerline.length; i++)
        (
          x: centerline[i].dx,
          y: centerline[i].dy,
          // a tiny minimum weight so dots and repeated points still count
          weight:
              0.01 +
              (i > 0 ? (centerline[i] - centerline[i - 1]).distance / 2 : 0) +
              (i < centerline.length - 1
                  ? (centerline[i + 1] - centerline[i]).distance / 2
                  : 0),
        ),
    ];
  }
}

/// Strokes that are close together horizontally in a line.
class _Word {
  new(_StrokeTransform stroke) : strokes = [stroke];

  final List<_StrokeTransform> strokes;

  Iterable<_WeightedPoint> get _points => strokes.expand((s) => s.points);

  double get left => strokes.map((s) => s.left).min;
  double get right => strokes.map((s) => s.right).max;

  /// The vertical middle of the word, ignoring ascenders and descenders.
  double get centerY =>
      HandwritingStraightener._quantileY(_points.toList(), 0.5);

  /// The height of the main part of the word,
  /// ignoring ascenders and descenders.
  double get bodyHeight {
    final points = _points.toList();
    return HandwritingStraightener._quantileY(points, 0.8) -
        HandwritingStraightener._quantileY(points, 0.2);
  }

  /// Whether this is a real word that can be resized,
  /// not e.g. a dot or a dash whose height says nothing about its size.
  bool canResizeIn(_Line line) {
    final height = bodyHeight;
    return height > 0 && right - left >= height && !isDotIn(line);
  }

  /// Whether this is just a dot, e.g. a period, which should stay
  /// where it is instead of being moved to the line's center line.
  bool isDotIn(_Line line) {
    final ys = _points.map((p) => p.y);
    final size = max(right - left, ys.max - ys.min);
    return size < 0.5 * line.bodyHeight;
  }

  void resize(Offset anchor, double scale) {
    for (final stroke in strokes) {
      stroke.resize(anchor, scale);
    }
  }

  void move(Offset delta) {
    for (final stroke in strokes) {
      stroke.move(delta);
    }
  }
}

class _Line {
  new(List<Stroke> strokes)
    : strokes = [for (final stroke in strokes) _StrokeTransform(stroke)];

  final List<_StrokeTransform> strokes;
  late List<_Word> words = _findWords();

  Iterable<_WeightedPoint> get _points => strokes.expand((s) => s.points);

  double get bodyHeight {
    final points = _points.toList();
    return HandwritingStraightener._quantileY(points, 0.8) -
        HandwritingStraightener._quantileY(points, 0.2);
  }

  /// The gaps between the words in this line.
  Iterable<double> get gaps sync* {
    for (int i = 1; i < words.length; i++) {
      yield words[i].left - words[i - 1].right;
    }
  }

  /// Rotates the line to be horizontal, around its left end.
  void level() {
    final points = _points.toList();
    final left = strokes.map((s) => s.left).min;
    final right = strokes.map((s) => s.right).max;
    // short lines don't have a reliable slope
    if (right - left < 3 * bodyHeight) return;

    // weighted least squares fit of y = a + b * x
    var sumW = 0.0, sumX = 0.0, sumY = 0.0;
    for (final p in points) {
      sumW += p.weight;
      sumX += p.weight * p.x;
      sumY += p.weight * p.y;
    }
    final meanX = sumX / sumW, meanY = sumY / sumW;
    var covXY = 0.0, varX = 0.0;
    for (final p in points) {
      covXY += p.weight * (p.x - meanX) * (p.y - meanY);
      varX += p.weight * (p.x - meanX) * (p.x - meanX);
    }
    if (varX == 0) return;
    final slope = atan(covXY / varX);
    if (slope.abs() < HandwritingStraightener.minSlope ||
        slope.abs() > HandwritingStraightener.maxSlope) {
      return;
    }

    final pivot = Offset(left, meanY + (left - meanX) * covXY / varX);
    for (final stroke in strokes) {
      stroke.rotate(pivot, -slope);
    }
    words = _findWords();
  }

  List<_Word> _findWords() {
    final sorted = strokes.sorted((a, b) => a.left.compareTo(b.left));
    final maxGap = HandwritingStraightener.wordGap * bodyHeight;
    final words = <_Word>[];
    for (final stroke in sorted) {
      final last = words.lastOrNull;
      if (last != null && stroke.left - last.right <= maxGap) {
        last.strokes.add(stroke);
      } else {
        words.add(_Word(stroke));
      }
    }
    return words;
  }

  /// Resizes words towards [targetHeight], about their left middle.
  void resizeWords(double targetHeight) {
    for (final word in words) {
      if (!word.canResizeIn(this)) continue;
      // only go halfway, so words keep some of their character
      final scale = sqrt(targetHeight / word.bodyHeight).clamp(
        1 / HandwritingStraightener.maxResize,
        HandwritingStraightener.maxResize,
      );
      if ((scale - 1).abs() < 0.05) continue;
      word.resize(Offset(word.left, word.centerY), scale);
    }
  }

  /// Moves the words onto the line's center line.
  void alignWords() {
    final toAlign = [
      for (final word in words)
        if (!word.isDotIn(this)) word,
    ];
    if (toAlign.isEmpty) return;
    final centers = [for (final word in toAlign) word.centerY]..sort();
    final center = centers[centers.length ~/ 2];
    for (final word in toAlign) {
      final dy = center - word.centerY;
      if (dy != 0) word.move(Offset(0, dy));
    }
  }

  /// Evens out the gaps between words, keeping the first word in place.
  void spaceWords(double targetGap) {
    for (int i = 1; i < words.length; i++) {
      final gap = words[i].left - words[i - 1].right;
      final newGap = gap > HandwritingStraightener.maxGapToEven * targetGap
          ? gap
          : targetGap;
      final dx = newGap - gap;
      if (dx == 0) continue;
      // move this word and the rest of the line along with it
      for (final word in words.skip(i)) {
        word.move(Offset(dx, 0));
      }
    }
  }

  Map<Stroke, Stroke> transformedStrokes() => {
    for (final stroke in strokes)
      if (!stroke.isIdentity) stroke.stroke: stroke.apply(),
  };
}
