import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/data/tools/tape.dart';

/// The parts of a page that [CanvasPainter] draws.
///
/// The editor draws each layer separately, so that drawing a new stroke
/// only repaints [overlay] instead of every stroke on the page.
enum CanvasPainterLayer {
  /// Highlighter strokes, which blend with what's below them
  /// (the page background, images and text), and the page indicator.
  ///
  /// The page indicator is drawn here, in the same layer as images and
  /// text, so that it repaints with them (e.g. when fonts finish loading).
  highlighters,

  /// All other strokes and tape.
  ink,

  /// What changes while drawing: the current stroke, the detected shape,
  /// laser strokes, the selection and the zoom writing box's target.
  overlay;

  static const all = {highlighters, ink, overlay};
}

class CanvasPainter extends CustomPainter {
  const new({
    super.repaint,
    this.layers = CanvasPainterLayer.all,
    this.invert = false,
    required this.strokes,
    required this.laserStrokes,
    required this.currentStroke,
    required this.currentSelection,
    required this.primaryColor,
    required this.page,
    required this.showPageIndicator,
    this.showZoomBoxTarget = true,
    required this.pageIndex,
    required this.totalPages,
    required this.currentScale,
    required this.defaultTextStyle,
  });

  final Set<CanvasPainterLayer> layers;
  final bool invert;
  final List<Stroke> strokes;
  final List<LaserStroke> laserStrokes;
  final Stroke? currentStroke;
  final SelectResult? currentSelection;
  final Color primaryColor;
  final EditorPage page;
  final bool showPageIndicator;

  /// Whether to show the target area of the zoom writing box,
  /// see [EditorPage.zoomBoxTarget].
  final bool showZoomBoxTarget;
  final int pageIndex;
  final int totalPages;
  final double currentScale;
  final TextStyle defaultTextStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;

    if (layers.contains(CanvasPainterLayer.highlighters)) {
      _drawHighlighterStrokes(canvas, canvasRect);
      _drawPageIndicator(canvas, size);
    }
    if (layers.contains(CanvasPainterLayer.ink)) {
      _drawNonHighlighterStrokes(canvas);
      _drawTapes(canvas);
    }
    if (layers.contains(CanvasPainterLayer.overlay)) {
      for (final stroke in laserStrokes) _drawLaserStroke(canvas, stroke);
      _drawCurrentStroke(canvas);
      _drawDetectedShape(canvas);
      _drawSelection(canvas);
      _drawZoomBoxTarget(canvas);
    }
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) {
    // Strokes can change in place (e.g. when moved or recolored),
    // and these layers only rebuild occasionally (not while drawing),
    // so always repaint them when they rebuild.
    if (layers.contains(CanvasPainterLayer.highlighters) ||
        layers.contains(CanvasPainterLayer.ink)) {
      return true;
    }
    return false ||
        // Current stroke is being drawn, so always repaint if present
        (currentStroke != null || oldDelegate.currentStroke != null) ||
        // Laser strokes are always fading out, so always repaint if present
        (laserStrokes.isNotEmpty || oldDelegate.laserStrokes.isNotEmpty) ||
        // Check for any other changes
        invert != oldDelegate.invert ||
        strokes.length != oldDelegate.strokes.length ||
        currentSelection != oldDelegate.currentSelection ||
        primaryColor != oldDelegate.primaryColor ||
        page != oldDelegate.page ||
        showPageIndicator != oldDelegate.showPageIndicator ||
        pageIndex != oldDelegate.pageIndex ||
        totalPages != oldDelegate.totalPages ||
        currentScale != oldDelegate.currentScale;
  }

  void _drawHighlighterStrokes(Canvas canvas, Rect canvasRect) {
    final layerPaint = Paint()
      ..blendMode = invert ? BlendMode.lighten : BlendMode.darken
      ..color = Colors.white.withAlpha(Highlighter.alpha);
    bool needToRestoreCanvasLayer = false;

    Color? lastColor;
    for (final stroke in strokes) {
      if (stroke.toolId != .highlighter) continue;

      final color = stroke.color.withValues(alpha: 1).withInversion(invert);

      if (color != lastColor) {
        // new layer for each color
        if (needToRestoreCanvasLayer) canvas.restore();
        canvas.saveLayer(canvasRect, layerPaint);

        needToRestoreCanvasLayer = true;
        lastColor = color;
      }

      canvas.drawPath(_selectPath(stroke), Paint()..color = color);
    }

    if (needToRestoreCanvasLayer) canvas.restore();
  }

  void _drawNonHighlighterStrokes(Canvas canvas) {
    late final paint = Paint();

    for (final stroke in strokes) {
      if (stroke.toolId == .highlighter) continue;
      if (stroke.toolId == .tape) continue;

      var color = stroke.color.withInversion(invert);
      if (currentSelection?.strokes.contains(stroke) ?? false) {
        color = Color.lerp(color, primaryColor, 0.5)!;
      }

      paint.color = color;
      paint.shader = null;
      paint.maskFilter = null;
      if (stroke.toolId == .pencil) {
        if (shouldUsePencilShader(stroke.options.size)) {
          paint.color = Colors.white;
          paint.shader = page.pencilShader
            ..setFloat(0, color.r)
            ..setFloat(1, color.g)
            ..setFloat(2, color.b);
          paint.maskFilter = _getPencilMaskFilter(stroke.options.size);
        } else {
          // Fast imitation of pencil when zoomed out
          final background = invert ? Colors.black : Colors.white;
          paint.color = Color.lerp(background, color, 0.6)!;
        }
      }

      late final shapePaint = Paint()
        ..color = paint.color
        ..style = .stroke
        ..strokeWidth = stroke.options.size;

      if (stroke is CircleStroke) {
        canvas.drawCircle(stroke.center, stroke.radius, shapePaint);
      } else if (stroke is RectangleStroke) {
        final strokeSize = stroke.options.size;
        canvas.drawRRect(
          RRect.fromRectAndRadius(stroke.rect, Radius.circular(strokeSize / 4)),
          shapePaint,
        );
      } else {
        canvas.drawPath(_selectPath(stroke), paint);
      }
    }
  }

  /// Tape is drawn on top of everything else so it covers the page.
  void _drawTapes(Canvas canvas) {
    final paint = Paint();
    for (final stroke in strokes) {
      if (stroke.toolId != .tape) continue;

      var color = stroke.color.withInversion(invert);
      if (page.revealedTapes.contains(stroke)) {
        color = color.withAlpha(Tape.revealedAlpha);
      }
      if (currentSelection?.strokes.contains(stroke) ?? false) {
        color = Color.lerp(color, primaryColor, 0.5)!;
      }
      paint.color = color;
      canvas.drawPath(_selectPath(stroke), paint);
    }
  }

  void _drawCurrentStroke(Canvas canvas) {
    if (currentStroke == null) return;

    if (currentStroke! is LaserStroke) {
      return _drawLaserStroke(canvas, currentStroke as LaserStroke);
    }

    final color = currentStroke!.color.withInversion(invert);
    final paint = Paint();

    paint.color = color;
    paint.shader = null;
    paint.maskFilter = null;
    if (currentStroke!.toolId == .pencil) {
      paint.color = Colors.white;
      paint.shader = page.pencilShader
        ..setFloat(0, color.r)
        ..setFloat(1, color.g)
        ..setFloat(2, color.b);
      paint.maskFilter = _getPencilMaskFilter(currentStroke!.options.size);
    }

    // Current stroke always uses high quality
    canvas.drawPath(currentStroke!.highQualityPath, paint);
  }

  void _drawLaserStroke(Canvas canvas, LaserStroke stroke) {
    canvas.drawPath(
      _selectPath(stroke),
      Paint()
        ..color = stroke.color.withInversion(invert)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.solid,
          stroke.options.size * 0.4,
        ),
    );
    canvas.drawPath(stroke.innerPath, Paint()..color = const Color(0xDDffffff));
  }

  void _drawDetectedShape(Canvas canvas) {
    final shape = ShapePen.detectedShape;
    if (shape == null) return;

    final color = currentStroke?.color.withInversion(invert) ?? Colors.black;
    final shapePaint = Paint()
      ..color = Color.lerp(color, primaryColor, 0.5)!.withValues(alpha: 0.7)
      ..style = .stroke
      ..strokeWidth = currentStroke?.options.size ?? 3;

    switch (shape.name) {
      case null:
        break;
      case DefaultUnistrokeNames.line:
        var (firstPoint, lastPoint) = shape.convertToLine();
        if (stows.snapLinesToAxes.value) {
          (firstPoint, lastPoint) = Stroke.snapLine(
            firstPoint is PointVector
                ? firstPoint
                : PointVector.fromOffset(offset: firstPoint),
            lastPoint is PointVector
                ? lastPoint
                : PointVector.fromOffset(offset: lastPoint),
          );
        }
        canvas.drawLine(firstPoint, lastPoint, shapePaint);
      case DefaultUnistrokeNames.rectangle:
        final rect = shape.convertToRect();
        canvas.drawRect(rect, shapePaint);
      case DefaultUnistrokeNames.circle:
        final (center, radius) = shape.convertToCircle();
        canvas.drawCircle(center, radius, shapePaint);
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        final polygon = shape.convertToCanonicalPolygon();
        canvas.drawPath(Path()..addPolygon(polygon, true), shapePaint);
    }
  }

  void _drawSelection(Canvas canvas) {
    if (currentSelection == null) return;

    // draw translucent fill
    canvas.drawPath(
      currentSelection!.path,
      Paint()..color = primaryColor.withValues(alpha: 0.1),
    );

    // draw dashed stroke
    canvas.drawPath(
      dashPath(
        currentSelection!.path,
        dashArray: CircularIntervalList([10, 10]),
      ),
      Paint()
        ..color = primaryColor
        ..strokeWidth = 3
        ..style = .stroke,
    );

    _drawSelectionHandles(canvas, currentSelection!);
  }

  /// Draws a bounding box with handles to resize and rotate the selection.
  void _drawSelectionHandles(Canvas canvas, SelectResult selection) {
    final bounds = SelectionHandle.boundsOf(selection);
    if (bounds == null) return;

    final scale = currentScale > 0 ? currentScale : 1.0;
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 1 / scale
      ..style = .stroke;
    final fillPaint = Paint()..color = Colors.white;

    canvas.drawRect(bounds, linePaint);

    final radius = SelectionHandle.radius / scale;
    for (final handle in SelectionHandle.values) {
      if (handle == .rotate) {
        if (!SelectionHandle.canRotate(selection)) continue;
        canvas.drawLine(
          bounds.topCenter,
          handle.positionIn(bounds, scale),
          linePaint,
        );
      }
      final position = handle.positionIn(bounds, scale);
      canvas.drawCircle(position, radius, fillPaint);
      canvas.drawCircle(position, radius, linePaint..strokeWidth = 2 / scale);
      linePaint.strokeWidth = 1 / scale;
    }
  }

  void _drawZoomBoxTarget(Canvas canvas) {
    if (!showZoomBoxTarget) return;
    final target = page.zoomBoxTarget;
    if (target == null) return;

    final scale = currentScale > 0 ? currentScale : 1.0;
    canvas.drawRect(
      target,
      Paint()..color = primaryColor.withValues(alpha: 0.08),
    );
    canvas.drawRect(
      target,
      Paint()
        ..color = primaryColor
        ..strokeWidth = 2 / scale
        ..style = .stroke,
    );
  }

  static const double _pageIndicatorFontSize = 20;
  static const double _pageIndicatorPadding = 5;
  void _drawPageIndicator(Canvas canvas, Size pageSize) {
    if (!showPageIndicator) return;

    final style = ui.ParagraphStyle(
      textAlign: .end,
      textDirection: .ltr,
      maxLines: 1,
    );

    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: Colors.black.withInversion(invert).withValues(alpha: 0.5),
          fontSize: _pageIndicatorFontSize,
          fontFamily: defaultTextStyle.fontFamily,
          fontFamilyFallback: defaultTextStyle.fontFamilyFallback,
        ),
      )
      ..addText('${pageIndex + 1} / $totalPages');

    final paragraph = builder.build();
    paragraph.layout(
      ui.ParagraphConstraints(
        width: pageSize.width - 2 * _pageIndicatorPadding,
      ),
    );

    canvas.drawParagraph(
      paragraph,
      Offset(
        _pageIndicatorPadding,
        pageSize.height - _pageIndicatorPadding - _pageIndicatorFontSize * 1.2,
      ),
    );
  }

  static MaskFilter _getPencilMaskFilter(double size) =>
      MaskFilter.blur(BlurStyle.normal, min(size * 0.2, 3));
  bool shouldUsePencilShader(double strokeSize) =>
      currentScale >= _zoomThreshold && (strokeSize * currentScale) >= 3;

  static const _zoomThreshold = 0.9;
  Path _selectPath(Stroke stroke) => switch (currentScale) {
    < _zoomThreshold => stroke.lowQualityPath,
    _ => stroke.highQualityPath,
  };
}
