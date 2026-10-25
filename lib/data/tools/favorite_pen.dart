import 'package:flutter/material.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:sbn/tool_id.dart';

/// A saved tool + color + width combination,
/// e.g. "blue fountain pen 3" or "yellow highlighter 40".
///
/// Favorites are stored in [stows.favoritePens].
class FavoritePen {
  const new({required this.toolId, required this.color, required this.size});

  new fromPen(Pen pen)
    : toolId = pen.toolId,
      color = pen.color,
      size = pen.options.size;

  factory fromJson(Map<String, dynamic> json) => FavoritePen(
    toolId: .parsePenType(json['t'] as String?, fallback: .fountainPen),
    color: Color(json['c'] as int),
    size: (json['s'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    't': toolId.id,
    'c': color.toARGB32(),
    's': size,
  };

  final ToolId toolId;
  final Color color;
  final double size;

  Object get icon => switch (toolId) {
    .highlighter => Highlighter.highlighterIcon,
    .pencil => Pencil.pencilIcon,
    .shapePen => ShapePen.shapePenIcon,
    .ballpointPen => Pen.ballpointPenIcon,
    _ => Pen.fountainPenIcon,
  };

  /// The maximum number of favorites that can be saved.
  static const maxCount = 8;

  /// Switches the relevant pen (e.g. [Pen.currentPen]) to this favorite's
  /// pen type, color and size, and returns it.
  Pen apply() {
    final Pen pen;
    switch (toolId) {
      case .highlighter:
        pen = Highlighter.currentHighlighter;
      case .pencil:
        pen = Pencil.currentPencil;
      case .shapePen:
        if (Pen.currentPen is! ShapePen) Pen.currentPen = ShapePen();
        pen = Pen.currentPen;
      case .ballpointPen:
        if (Pen.currentPen.toolId != .ballpointPen) {
          Pen.currentPen = Pen.ballpointPen();
        }
        pen = Pen.currentPen;
      default:
        if (Pen.currentPen.toolId != .fountainPen) {
          Pen.currentPen = Pen.fountainPen();
        }
        pen = Pen.currentPen;
    }
    pen.color = color;
    pen.options.size = size;
    return pen;
  }

  /// Whether [pen] currently has this favorite's type, color and size.
  bool matches(Pen pen) =>
      pen.toolId == toolId &&
      pen.color.toARGB32() == color.toARGB32() &&
      pen.options.size == size;

  @override
  bool operator ==(Object other) =>
      other is FavoritePen &&
      other.toolId == toolId &&
      other.color.toARGB32() == color.toARGB32() &&
      other.size == size;

  @override
  int get hashCode => Object.hash(toolId, color.toARGB32(), size);
}
