import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:sbn/tool_id.dart';

/// A to-do box on a page, see [EditorPage.todos].
///
/// The handwriting to the right of the box, on the same line,
/// is the to-do's label (see [labelStrokes]).
/// Tapping the box closes the to-do, which ticks the box
/// and greys out and strikes through the label.
@immutable
class TodoBox {
  const new({required this.id, required this.rect, this.closedAt});

  /// Creates a new, open to-do box centered at [center].
  factory at(Offset center, double size) => TodoBox(
    id: _random.nextInt(1 << 31),
    rect: Rect.fromCenter(center: center, width: size, height: size),
  );

  factory fromJson(Map<String, dynamic> json) => TodoBox(
    id: (json['id'] as num).toInt(),
    rect: Rect.fromLTWH(
      (json['l'] as num).toDouble(),
      (json['t'] as num).toDouble(),
      (json['s'] as num).toDouble(),
      (json['s'] as num).toDouble(),
    ),
    closedAt: json['c'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((json['c'] as num).toInt()),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'l': rect.left,
    't': rect.top,
    's': rect.width,
    if (closedAt != null) 'c': closedAt!.millisecondsSinceEpoch,
  };

  static final _random = Random();

  /// Identifies this to-do within its page.
  final int id;

  /// The box, which is always square.
  final Rect rect;

  /// When the to-do was closed, or null if it's open.
  final DateTime? closedAt;

  bool get isClosed => closedAt != null;

  /// The default size of a box for a page with [lineHeight].
  static double sizeFor(int lineHeight) =>
      (lineHeight * 0.6).clamp(16, 60).toDouble();

  /// Returns this to-do closed at [now], or reopened if it was closed.
  TodoBox toggled(DateTime now) =>
      TodoBox(id: id, rect: rect, closedAt: isClosed ? null : now);

  /// Whether [position] is on (or very near) the box.
  bool contains(Offset position) =>
      rect.inflate(rect.width * 0.35).contains(position);

  /// Whether a rectangle drawn with the shape pen should become a to-do box:
  /// it must be roughly square and not much bigger than the line height.
  static bool looksLikeBox(Rect rect, int lineHeight) {
    if (rect.isEmpty) return false;
    final aspectRatio = rect.width / rect.height;
    if (aspectRatio < 0.7 || aspectRatio > 1.4) return false;
    return max(rect.width, rect.height) <= lineHeight * 1.5;
  }

  /// The area to the right of the box, on the same line, where its label
  /// is: up to the next box on the same line, or the edge of the page.
  Rect labelRegion(double pageWidth, Iterable<TodoBox> boxesOnPage) {
    var right = pageWidth;
    for (final other in boxesOnPage) {
      if (other.id == id) continue;
      if (other.rect.left <= rect.right) continue;
      final sameLine =
          other.rect.top < rect.bottom && other.rect.bottom > rect.top;
      if (sameLine) right = min(right, other.rect.left);
    }
    return Rect.fromLTRB(
      rect.right,
      rect.top - rect.height * 0.6,
      right,
      rect.bottom + rect.height * 0.6,
    );
  }

  /// The handwritten strokes that make up this to-do's label.
  List<Stroke> labelStrokes(
    Iterable<Stroke> strokes,
    double pageWidth,
    Iterable<TodoBox> boxesOnPage,
  ) {
    final region = labelRegion(pageWidth, boxesOnPage);
    return [
      for (final stroke in strokes)
        if (isLabelStroke(stroke) &&
            region.contains(stroke.lowQualityPath.getBounds().center) &&
            stroke.lowQualityPath.getBounds().left >=
                rect.right - rect.width * 0.5)
          stroke,
    ];
  }

  /// Where to strike through this to-do's label, or null if it has none.
  (Offset start, Offset end)? strikeThrough(
    Iterable<Stroke> strokes,
    double pageWidth,
    Iterable<TodoBox> boxesOnPage,
  ) {
    final label = labelStrokes(strokes, pageWidth, boxesOnPage);
    if (label.isEmpty) return null;
    var bounds = label.first.lowQualityPath.getBounds();
    for (final stroke in label.skip(1)) {
      bounds = bounds.expandToInclude(stroke.lowQualityPath.getBounds());
    }
    final y = min(bounds.center.dy, rect.bottom);
    return (Offset(bounds.left, y), Offset(bounds.right, y));
  }

  /// Whether [stroke] can be part of a label, i.e. writing
  /// rather than a highlighter, tape or a shape.
  static bool isLabelStroke(Stroke stroke) {
    if (stroke is CircleStroke || stroke is RectangleStroke) return false;
    return switch (stroke.toolId) {
      ToolId.highlighter || ToolId.tape || ToolId.laserPointer => false,
      _ => true,
    };
  }

  /// The strokes in the labels of the closed to-dos in [todos],
  /// which are drawn greyed out.
  static Set<Stroke> closedLabelStrokes(
    List<Stroke> strokes,
    List<TodoBox> todos,
    double pageWidth,
  ) => {
    for (final todo in todos)
      if (todo.isClosed) ...todo.labelStrokes(strokes, pageWidth, todos),
  };

  @override
  bool operator ==(Object other) =>
      other is TodoBox &&
      other.id == id &&
      other.rect == rect &&
      other.closedAt == closedAt;

  @override
  int get hashCode => Object.hash(id, rect, closedAt);
}
