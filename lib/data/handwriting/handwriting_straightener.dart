import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/handwriting/handwriting_lines.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';

/// Makes handwriting look neater while keeping it handwritten,
/// like "Straighten" in Samsung Notes:
/// - slanted lines are rotated to be level, and
/// - the words in each line are moved up or down onto a common baseline.
///
/// Nothing else changes: letters keep their shapes and sizes,
/// and words keep their horizontal positions and spacing.
abstract final class HandwritingStraightener {
  /// Lines that slope more than this (in radians) are probably
  /// meant to be diagonal, so they aren't leveled.
  static const maxSlope = 25 * pi / 180;

  /// Lines that slope less than this (in radians) are already level.
  static const minSlope = 0.5 * pi / 180;

  /// A gap between strokes wider than this many [_Line.bodyHeight]s
  /// separates two words.
  static const wordGap = 0.75;

  /// Words aren't moved by less than this many pixels,
  /// since handwriting is never perfectly aligned anyway.
  static const minMove = 0.5;

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

    final changed = <Stroke, Stroke>{};
    for (final line in lines) {
      line.level();
      line.alignWords();
      changed.addAll(line.transformedStrokes());
    }
    return changed;
  }

  /// Strokes in the same word overlap vertically by at least this
  /// fraction of the shorter of the two heights.
  static const minWordOverlap = 0.5;

  /// A word's baseline can be this many typical heights away from where
  /// its line is expected to continue: handwriting bobs up and down,
  /// but the next line is further away than this.
  static const lineBand = 0.7;

  /// Words further right than this many typical heights from the end
  /// of a line start a new line, e.g. in another column.
  static const maxLineGap = 3.0;

  /// Strokes shorter than this many typical heights are dots, dashes
  /// and accents, which follow the line they're on or above
  /// rather than having a baseline of their own.
  static const dotHeight = 0.4;

  /// Groups [strokes] into lines of text.
  ///
  /// Strokes that are close together make a word, and words whose
  /// baselines line up make a line. Unlike [HandwritingLines.group],
  /// this follows the slope of each line, so lines that slope a lot
  /// are still found as one line.
  @visibleForTesting
  static List<List<Stroke>> groupLines(List<Stroke> strokes) {
    if (strokes.isEmpty) return const [];
    final infos = [for (final stroke in strokes) _StrokeInfo(stroke)]
      ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    final height = _typicalHeight(infos);

    // Strokes that are close together and overlap vertically make a word
    // (or a letter, in print handwriting). Words are compact, so it
    // doesn't matter here if the line slopes.
    final words = <_WordGroup>[];
    for (final info in infos) {
      final b = info.bounds;
      _WordGroup? best;
      var bestOverlap = minWordOverlap;
      for (final word in words) {
        if (b.left - word.bounds.right > wordGap * height) continue;
        final overlap =
            min(word.bounds.bottom, b.bottom) - max(word.bounds.top, b.top);
        final shorter = max(1.0, min(word.bounds.height, b.height));
        final fraction = overlap / shorter;
        if (fraction >= bestOverlap) {
          best = word;
          bestOverlap = fraction;
        }
      }
      if (best != null) {
        best.add(info);
      } else {
        words.add(_WordGroup(info));
      }
    }

    // A word continues the line whose baseline it's closest to,
    // following the slope of the line so far.
    final lines = <_LineGroup>[];
    final dots = <_WordGroup>[];
    for (final word in words) {
      if (word.bounds.height < dotHeight * height) {
        dots.add(word);
        continue;
      }
      final x = word.bounds.center.dx;
      final baseline = _baselineOf(word.points, height);
      _LineGroup? best;
      var bestScore = 1.0;
      for (final line in lines) {
        if (word.bounds.left - line.right > maxLineGap * height) continue;
        final (:expected, :tolerance) = line.expectAt(x, height);
        final score = (baseline - expected).abs() / tolerance;
        if (score <= bestScore) {
          best = line;
          bestScore = score;
        }
      }
      if (best != null) {
        best.add(word, x, baseline);
      } else {
        lines.add(_LineGroup(word, x, baseline));
      }
    }

    // Dots, dashes and accents go with the line they're on or above,
    // e.g. the dot of an "i" or a period.
    final unplaced = <_WordGroup>[];
    for (final dot in dots) {
      final x = dot.bounds.center.dx;
      final y = dot.bounds.center.dy;
      _LineGroup? best;
      var bestDistance = height;
      for (final line in lines) {
        if (x < line.left - height || x > line.right + height) continue;
        final baseline = line.expectAt(x, height).expected;
        // from the top of the ascenders to just below the baseline
        final distance = max(
          0.0,
          max(baseline - 2 * height - y, y - baseline - dotHeight * height),
        );
        if (distance < bestDistance) {
          best = line;
          bestDistance = distance;
        }
      }
      if (best != null) {
        best.words.add(dot);
      } else {
        unplaced.add(dot);
      }
    }

    return [
      for (final line in lines)
        [
          for (final word in line.words)
            for (final info in word.strokes) info.stroke,
        ],
      for (final dot in unplaced) [for (final info in dot.strokes) info.stroke],
    ];
  }

  /// The typical height of the letters in [strokes] (roughly the
  /// x-height), from the height of each stroke's main body of ink,
  /// so a cursive word with ascenders counts about the same as an "o".
  static double _typicalHeight(List<_StrokeInfo> strokes) {
    final heights = [
      for (final info in strokes)
        if (_quantileY(info.points, 0.8) - _quantileY(info.points, 0.2)
            case final body when body >= 1)
          body * 1.5,
    ];
    if (heights.isNotEmpty) return _midMedian(heights);
    return max(1, _midMedian([for (final info in strokes) info.bounds.height]));
  }

  /// Where the ink in [points] sits on its line.
  ///
  /// Most of a word's ink is in its x-height band (the part between the
  /// baseline and the top of letters like "o"), so this is the bottom
  /// of the densest band of ink [height] tall. Unlike the ink's center,
  /// it isn't pulled up by ascenders ("l") or down by descenders ("p").
  static double _baselineOf(List<_WeightedPoint> points, double height) {
    final sorted = points.sorted((a, b) => a.y.compareTo(b.y));
    // the ink in the band of [height] ending at each point
    final bands = <({double bottom, double ink})>[];
    var top = 0;
    var ink = 0.0;
    for (final point in sorted) {
      ink += point.weight;
      while (sorted[top].y < point.y - height) {
        ink -= sorted[top].weight;
        top++;
      }
      bands.add((bottom: point.y, ink: ink));
    }
    final mostInk = bands.map((b) => b.ink).max;
    // Prefer the lowest of the dense bands: for a word whose ink is
    // spread evenly (e.g. only ascenders, like "till"), every band
    // is about as dense, and the bottom one ends at the baseline.
    return bands.lastWhere((b) => b.ink >= 0.95 * mostInk).bottom;
  }

  /// A line y = intercept + slope * x through [points], or null if
  /// there are fewer than two of them further apart than [minDx].
  ///
  /// This is a repeated median: for each point, the median slope to the
  /// other points, and then the median of those. So one point that's
  /// off (a word that dips or rises) doesn't tilt the whole line.
  /// [slopeSpread] is how much the points disagree about the slope.
  static ({double slope, double intercept, double slopeSpread})? _robustFit(
    List<({double x, double y})> points, {
    required double minDx,
  }) {
    final slopes = <double>[];
    for (int i = 0; i < points.length; i++) {
      final toOthers = <double>[];
      for (int j = 0; j < points.length; j++) {
        final dx = points[j].x - points[i].x;
        if (dx.abs() < minDx) continue; // too close to tell
        toOthers.add((points[j].y - points[i].y) / dx);
      }
      if (toOthers.isNotEmpty) slopes.add(_midMedian(toOthers));
    }
    if (slopes.isEmpty) return null;
    final slope = _midMedian(slopes);
    final intercept = _midMedian([for (final p in points) p.y - slope * p.x]);
    final slopeSpread = _midMedian([for (final s in slopes) (s - slope).abs()]);
    return (slope: slope, intercept: intercept, slopeSpread: slopeSpread);
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

  /// The median of [values], halfway between the middle two
  /// if there's an even number of them.
  static double _midMedian(List<double> values) {
    values.sort();
    final n = values.length;
    return n.isOdd ? values[n ~/ 2] : (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2;
  }

  /// The weighted median of [values].
  static double _weightedMedian(List<({double value, double weight})> values) {
    final sorted = values.sorted((a, b) => a.value.compareTo(b.value));
    final total = sorted.fold(0.0, (sum, v) => sum + v.weight);
    var cumulative = 0.0;
    for (final v in sorted) {
      cumulative += v.weight;
      if (cumulative >= total / 2) return v.value;
    }
    return sorted.last.value;
  }
}

/// A stroke's bounds and ink, for [HandwritingStraightener.groupLines].
class _StrokeInfo {
  new(this.stroke)
    : bounds = stroke.lowQualityPath.getBounds(),
      points = _StrokeTransform._weightedPoints(stroke.centerline);

  final Stroke stroke;
  final Rect bounds;
  final List<_WeightedPoint> points;
}

/// Strokes that are close together, for [HandwritingStraightener.groupLines].
class _WordGroup {
  new(_StrokeInfo stroke) : strokes = [stroke], bounds = stroke.bounds;

  final List<_StrokeInfo> strokes;
  Rect bounds;

  List<_WeightedPoint> get points => [
    for (final stroke in strokes) ...stroke.points,
  ];

  void add(_StrokeInfo stroke) {
    strokes.add(stroke);
    bounds = bounds.expandToInclude(stroke.bounds);
  }
}

/// Words whose baselines line up, for [HandwritingStraightener.groupLines].
class _LineGroup {
  new(_WordGroup word, double x, double baseline)
    : words = [word],
      bounds = word.bounds,
      _points = [(x: x, y: baseline)];

  final List<_WordGroup> words;
  Rect bounds;

  /// The center and baseline of each word (not dots).
  final List<({double x, double y})> _points;

  double get left => bounds.left;
  double get right => bounds.right;

  void add(_WordGroup word, double x, double baseline) {
    words.add(word);
    bounds = bounds.expandToInclude(word.bounds);
    _points.add((x: x, y: baseline));
  }

  /// Where the line's baseline is expected to be at [x], and how far
  /// from there a word's baseline can be and still be in this line.
  ({double expected, double tolerance}) expectAt(double x, double height) {
    final band = HandwritingStraightener.lineBand * height;
    switch (_points) {
      case [final only]:
        // the line could slope either way
        final dx = (x - only.x).abs();
        return (
          expected: only.y,
          tolerance: band + tan(HandwritingStraightener.maxSlope) * dx,
        );
      case [final first, final last]:
        // Two words only roughly give the slope, since one of them
        // may just bob up or down, so allow for that much.
        final dx = last.x - first.x;
        final slope = dx.abs() < 1 ? 0.0 : (last.y - first.y) / dx;
        final bob = (last.y - first.y).abs();
        return (
          expected: last.y + slope * (x - last.x),
          tolerance: band + bob * max(1, (x - last.x).abs() / max(1, dx)),
        );
      default:
        final fit = HandwritingStraightener._robustFit(_points, minDx: height);
        if (fit == null) {
          return (expected: _points.last.y, tolerance: band);
        }
        final spread = HandwritingStraightener._midMedian([
          for (final p in _points)
            (p.y - fit.intercept - fit.slope * p.x).abs(),
        ]);
        // the further from the words, the more an uncertain slope matters
        final meanX = _points.map((p) => p.x).average;
        return (
          expected: fit.intercept + fit.slope * x,
          tolerance: band + 1.5 * spread + fit.slopeSpread * (x - meanX).abs(),
        );
    }
  }
}

typedef _WeightedPoint = ({double x, double y, double weight});

/// A stroke and the transform that will be applied to it:
/// rotated by [rotation] around [pivot], then shifted by [offset].
class _StrokeTransform {
  new(this.stroke) : points = _weightedPoints(stroke.centerline);

  final Stroke stroke;

  /// The points of the stroke, transformed as far as decided so far.
  List<_WeightedPoint> points;

  var pivot = Offset.zero;
  var rotation = 0.0;
  var offset = Offset.zero;

  double get left => points.map((p) => p.x).min;
  double get right => points.map((p) => p.x).max;

  bool get isIdentity => rotation == 0 && offset == Offset.zero;

  Stroke apply() {
    if (isIdentity) return stroke;
    return stroke.transformed(pivot: pivot, rotation: rotation)..shift(offset);
  }

  /// Rotates by [rotation] around [pivot], on top of any earlier
  /// rotation and shift.
  void rotate(Offset pivot, double rotation) {
    final c = cos(rotation), s = sin(rotation);
    Offset rotated(Offset v) =>
        Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
    if (isIdentity) {
      this.pivot = pivot;
    } else {
      // Rotating around a new pivot after the earlier transform is the
      // same as rotating further around the old pivot, then shifting.
      final d = pivot - this.pivot;
      offset = rotated(offset) + d - rotated(d);
    }
    this.rotation += rotation;
    points = [
      for (final p in points)
        (
          x: pivot.dx + (p.x - pivot.dx) * c - (p.y - pivot.dy) * s,
          y: pivot.dy + (p.x - pivot.dx) * s + (p.y - pivot.dy) * c,
          weight: p.weight,
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

  /// How much ink is in the word.
  double get weight => _points.fold(0.0, (sum, p) => sum + p.weight);

  /// Where the word sits on the line, see
  /// [HandwritingStraightener._baselineOf].
  double baselineFor(double height) =>
      HandwritingStraightener._baselineOf(_points.toList(), height);

  /// Whether this is just a dot, dash or accent, e.g. a period,
  /// which is too small to have a baseline of its own
  /// and so follows the word before it.
  bool isDotIn(_Line line) {
    final ys = _points.map((p) => p.y);
    return ys.max - ys.min <
        HandwritingStraightener.dotHeight * line.bodyHeight;
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

  /// The height of the main part of the line, between the
  /// 20% and 80% quantiles of its ink, so ignoring most ascenders
  /// and descenders.
  double get bodyHeight {
    final points = _points.toList();
    return HandwritingStraightener._quantileY(points, 0.8) -
        HandwritingStraightener._quantileY(points, 0.2);
  }

  /// Rotates the line to be horizontal, around its left end.
  ///
  /// The slope is that of the words' baselines (see [_Word.baselineFor]),
  /// so it isn't swayed by which words have ascenders or descenders.
  /// It's leveled twice, since the baselines are found more accurately
  /// once the line is roughly level.
  void level() {
    final left = strokes.map((s) => s.left).min;
    final right = strokes.map((s) => s.right).max;
    // short lines don't have a reliable slope
    if (right - left < 3 * bodyHeight) return;

    for (var pass = 0; pass < 2; pass++) {
      final fit = _baselineFit() ?? _inkFit();
      if (fit == null) return;
      final slope = atan(fit.slope);
      // lines that slope a lot are probably meant to be diagonal
      if (pass == 0 && slope.abs() > HandwritingStraightener.maxSlope) return;
      if (slope.abs() < HandwritingStraightener.minSlope) return;

      final pivot = Offset(left, fit.intercept + fit.slope * left);
      for (final stroke in strokes) {
        stroke.rotate(pivot, -slope);
      }
      words = _findWords();
    }
  }

  /// A line y = intercept + slope * x through the words' baselines,
  /// or null if there are fewer than two words.
  ({double slope, double intercept})? _baselineFit() {
    final height = bodyHeight;
    if (height <= 0) return null;
    final fit = HandwritingStraightener._robustFit([
      for (final word in words)
        if (!word.isDotIn(this))
          (x: (word.left + word.right) / 2, y: word.baselineFor(height)),
    ], minDx: height);
    if (fit == null) return null;
    return (slope: fit.slope, intercept: fit.intercept);
  }

  /// A weighted least squares fit of y = intercept + slope * x
  /// through all the ink, for lines of a single word.
  ({double slope, double intercept})? _inkFit() {
    final points = _points.toList();
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
    if (varX == 0) return null;
    final slope = covXY / varX;
    return (slope: slope, intercept: meanY - slope * meanX);
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

  /// Moves the words up or down onto the line's baseline,
  /// which is where most of them already are.
  void alignWords() {
    final height = bodyHeight;
    if (height <= 0) return;
    final baselines = <_Word, double>{
      for (final word in words)
        if (!word.isDotIn(this)) word: word.baselineFor(height),
    };
    if (baselines.isEmpty) return;
    final baseline = HandwritingStraightener._weightedMedian([
      for (final MapEntry(key: word, value: y) in baselines.entries)
        (value: y, weight: word.weight),
    ]);

    var lastMove = 0.0;
    for (final word in words) {
      final double dy;
      if (baselines[word] case final y?) {
        dy = baseline - y;
        lastMove = dy;
      } else {
        // a dot, e.g. a period: stays with the word before it
        dy = lastMove;
      }
      if (dy.abs() >= HandwritingStraightener.minMove) {
        word.move(Offset(0, dy));
      }
    }
  }

  Map<Stroke, Stroke> transformedStrokes() => {
    for (final stroke in strokes)
      if (!stroke.isIdentity) stroke.stroke: stroke.apply(),
  };
}
