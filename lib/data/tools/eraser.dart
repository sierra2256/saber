import 'dart:ui';

import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

double square(double x) => x * x;
double sqrDistanceBetween(Offset p1, Offset p2) =>
    square(p1.dx - p2.dx) + square(p1.dy - p2.dy);

class Eraser extends Tool {
  /// Creates an eraser.
  ///
  /// Any parameters that aren't provided use the user's
  /// preferences ([stows.eraserSize], [stows.eraserPartial] and
  /// [stows.eraserHighlighterOnly]).
  new({this._size, this._partial, this._highlighterOnly});

  final double? _size;
  final bool? _partial;
  final bool? _highlighterOnly;

  /// The radius of the eraser.
  double get size => _size ?? stows.eraserSize.value;
  double get sqrSize => square(size);

  /// If true, only the erased section of a stroke is removed,
  /// splitting the stroke into multiple strokes.
  /// Otherwise, whole strokes are removed.
  bool get partial => _partial ?? stows.eraserPartial.value;

  /// If true, only highlighter strokes are erased.
  bool get highlighterOnly =>
      _highlighterOnly ?? stows.eraserHighlighterOnly.value;

  /// The eraser sizes that can be picked in the toolbar.
  static const sizePresets = [5.0, 10.0, 25.0];

  /// The strokes that existed before this drag and have been erased.
  List<Stroke> _erased = [];

  /// The strokes created during this drag by partially erasing strokes.
  List<Stroke> _created = [];

  @override
  ToolId get toolId => .eraser;

  /// Returns any [strokes] that are close to the given [eraserPos].
  ///
  /// This is used for whole-stroke erasing: the caller should
  /// remove the returned strokes from the page.
  List<Stroke> checkForOverlappingStrokes(
    Offset eraserPos,
    List<Stroke> strokes,
  ) {
    final List<Stroke> overlapping = [];
    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      if (!_canErase(stroke)) continue;
      if (_shouldStrokeBeErased(eraserPos, stroke, sqrSize)) {
        overlapping.add(stroke);
        _markErased(stroke);
      }
    }
    return overlapping;
  }

  /// Erases the parts of [strokes] that are close to [eraserPos].
  ///
  /// [strokes] is modified in place: strokes that are touched by the
  /// eraser are replaced by the remaining pieces of that stroke.
  /// Shapes (circles and rectangles) can't be split,
  /// so they are erased entirely.
  ///
  /// Returns whether any strokes were changed.
  bool erasePartially(Offset eraserPos, List<Stroke> strokes) {
    var changed = false;
    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      if (!_canErase(stroke)) continue;

      final List<Stroke> pieces;
      if (stroke is CircleStroke || stroke is RectangleStroke) {
        if (!_shouldStrokeBeErased(eraserPos, stroke, sqrSize)) continue;
        pieces = const [];
      } else {
        final split = stroke.splitAround(eraserPos, size);
        if (split == null) continue;
        pieces = split;
      }

      _markErased(stroke);
      _created.addAll(pieces);
      strokes.replaceRange(i, i + 1, pieces);
      i += pieces.length - 1;
      changed = true;
    }
    return changed;
  }

  /// Returns the strokes that have been erased during this drag.
  ///
  /// Only use this for whole-stroke erasing, otherwise use [onPartialDragEnd].
  List<Stroke> onDragEnd() {
    final List<Stroke> erased = _erased;
    _erased = [];
    _created = [];
    return erased;
  }

  /// Returns the strokes that were erased during this drag,
  /// and the new pieces of those strokes that are left over.
  ({List<Stroke> erased, List<Stroke> created}) onPartialDragEnd() {
    final result = (erased: _erased, created: _created);
    _erased = [];
    _created = [];
    return result;
  }

  bool _canErase(Stroke stroke) {
    if (highlighterOnly && stroke.toolId != .highlighter) return false;
    return true;
  }

  void _markErased(Stroke stroke) {
    // A piece created earlier in this drag isn't in the history yet,
    // so forget about it instead of recording it as erased.
    if (!_created.remove(stroke)) _erased.add(stroke);
  }

  static bool _shouldStrokeBeErased(
    Offset eraserPos,
    Stroke stroke,
    double sqrSize,
  ) {
    if (stroke.length <= 3) {
      if (stroke.lowQualityPath.contains(eraserPos)) return true;
    }

    /// skip checking every few vertices for performance
    final int verticesToSkip = switch (stroke.lowQualityPolygon.length) {
      < 100 => 0,
      < 1000 => 1,
      _ => 2,
    };

    for (
      int i = 0;
      i < stroke.lowQualityPolygon.length;
      i += verticesToSkip + 1
    ) {
      final Offset strokeVertex = stroke.lowQualityPolygon[i];
      if (sqrDistanceBetween(strokeVertex, eraserPos) <= sqrSize) return true;
    }
    return false;
  }
}
