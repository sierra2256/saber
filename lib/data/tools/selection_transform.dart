import 'dart:math';
import 'dart:ui';

import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/select.dart';
import 'package:sbn/change.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// The handles shown around a lasso selection.
enum SelectionHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,

  /// Rotates the selection around its center.
  rotate;

  bool get isCorner => this != rotate;

  /// The radius of a handle on screen, in logical pixels.
  static const radius = 7.0;

  /// The radius around a handle that can be touched to grab it,
  /// in logical pixels.
  static const touchRadius = 24.0;

  /// The distance of the [rotate] handle above the selection bounds,
  /// in logical pixels.
  static const rotateHandleDistance = 32.0;

  /// The bounds of the selected strokes and images,
  /// which the handles are placed around.
  static Rect? boundsOf(SelectResult selection) {
    Rect? bounds;
    for (final stroke in selection.strokes) {
      final strokeBounds = stroke.lowQualityPath.getBounds();
      bounds = bounds?.expandToInclude(strokeBounds) ?? strokeBounds;
    }
    for (final image in selection.images) {
      bounds = bounds?.expandToInclude(image.dstRect) ?? image.dstRect;
    }
    return bounds;
  }

  /// Whether the selection can be rotated.
  ///
  /// Images can't be rotated, so selections with images can only be scaled.
  static bool canRotate(SelectResult selection) => selection.images.isEmpty;

  /// The position of this handle in page coordinates,
  /// given the selection [bounds] and the canvas [scale] (zoom level).
  Offset positionIn(Rect bounds, double scale) => switch (this) {
    topLeft => bounds.topLeft,
    topRight => bounds.topRight,
    bottomLeft => bounds.bottomLeft,
    bottomRight => bounds.bottomRight,
    rotate => bounds.topCenter - Offset(0, rotateHandleDistance / scale),
  };

  /// Returns the handle at [position] (in page coordinates), if any.
  static SelectionHandle? hitTest(
    Offset position,
    SelectResult selection,
    double scale,
  ) {
    final bounds = boundsOf(selection);
    if (bounds == null) return null;

    final sqrTouchRadius = square(touchRadius / scale);
    SelectionHandle? closest;
    var closestSqrDistance = double.infinity;
    for (final handle in values) {
      if (handle == rotate && !canRotate(selection)) continue;
      final sqrDistance =
          (handle.positionIn(bounds, scale) - position).distanceSquared;
      if (sqrDistance <= sqrTouchRadius && sqrDistance < closestSqrDistance) {
        closest = handle;
        closestSqrDistance = sqrDistance;
      }
    }
    return closest;
  }

  static double square(double x) => x * x;
}

/// Scales or rotates a lasso selection while a [SelectionHandle] is dragged.
///
/// The transform is always applied to the strokes and images as they were
/// when the drag started, to avoid accumulating rounding errors.
class SelectionTransformer {
  new({
    required this.handle,
    required this.select,
    required this.page,
    required this.startPosition,
  }) : originalStrokes = List.of(select.selectResult.strokes),
       originalImageRects = {
         for (final image in select.selectResult.images) image: image.dstRect,
       },
       originalPath = select.selectResult.path,
       _currentStrokes = List.of(select.selectResult.strokes) {
    final bounds = SelectionHandle.boundsOf(select.selectResult)!;
    pivot = switch (handle) {
      .topLeft => bounds.bottomRight,
      .topRight => bounds.bottomLeft,
      .bottomLeft => bounds.topRight,
      .bottomRight => bounds.topLeft,
      .rotate => bounds.center,
    };
  }

  final SelectionHandle handle;
  final Select select;
  final EditorPage page;
  final Offset startPosition;

  final List<Stroke> originalStrokes;
  final Map<EditorImage, Rect> originalImageRects;
  final Path originalPath;

  /// The point that stays fixed while transforming:
  /// the opposite corner when scaling, or the center when rotating.
  late final Offset pivot;

  /// The strokes currently on the page, replacing [originalStrokes].
  List<Stroke> _currentStrokes;

  var scale = 1.0;
  var rotation = 0.0;

  /// The smallest allowed scale factor.
  static const minScale = 0.05;

  /// Updates the transform for the handle being dragged to [position].
  void update(Offset position) {
    if (handle.isCorner) {
      // Keep the aspect ratio by projecting onto the diagonal
      final diagonal = startPosition - pivot;
      final sqrLength = diagonal.distanceSquared;
      if (sqrLength == 0) return;
      final delta = position - pivot;
      scale = max(
        minScale,
        (delta.dx * diagonal.dx + delta.dy * diagonal.dy) / sqrLength,
      );
    } else {
      rotation =
          (position - pivot).direction - (startPosition - pivot).direction;
    }
    _apply();
  }

  void _apply() {
    final newStrokes = [
      for (final stroke in originalStrokes)
        stroke.transformed(pivot: pivot, scale: scale, rotation: rotation),
    ];
    for (int i = 0; i < newStrokes.length; i++) {
      final index = page.strokes.indexOf(_currentStrokes[i]);
      if (index >= 0) page.strokes[index] = newStrokes[i];
    }
    _currentStrokes = newStrokes;

    for (final MapEntry(key: image, value: rect)
        in originalImageRects.entries) {
      image.dstRect = Rect.fromPoints(
        transformPoint(rect.topLeft, pivot: pivot, scale: scale),
        transformPoint(rect.bottomRight, pivot: pivot, scale: scale),
      );
    }

    // Update the selection in place, since the canvas painter
    // holds a reference to it while dragging.
    select.selectResult.strokes
      ..clear()
      ..addAll(newStrokes);
    select.selectResult.path = originalPath.transform(matrix.storage);
  }

  /// The transform as a matrix, used to transform the selection path.
  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
    ..rotateZ(rotation)
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);

  bool get hasChanged => scale != 1 || rotation != 0;

  /// The strokes that replaced [originalStrokes].
  List<Stroke> get newStrokes => _currentStrokes;

  /// The changes to the images' positions and sizes.
  Map<EditorImage, Change<Rect>> get imageRectChanges => {
    for (final MapEntry(key: image, value: rect) in originalImageRects.entries)
      image: Change(previous: rect, current: image.dstRect),
  };

  /// Scales [point] by [scale] and rotates it by [rotation] around [pivot].
  static Offset transformPoint(
    Offset point, {
    required Offset pivot,
    double scale = 1,
    double rotation = 0,
  }) {
    final d = (point - pivot) * scale;
    if (rotation == 0) return pivot + d;
    final c = cos(rotation), s = sin(rotation);
    return pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }
}
