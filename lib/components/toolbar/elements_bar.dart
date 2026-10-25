import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/data/editor/canvas_element.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// A library of saved elements (see [CanvasElement]) shown above the toolbar.
///
/// Tap an element to insert it on the current page,
/// or long-press and drag it to where it should go.
class ElementsBar extends StatefulWidget {
  const new({
    super.key,
    required this.axis,
    required this.insertElement,
    required this.invert,
  });

  final Axis axis;
  final ValueChanged<CanvasElement> insertElement;
  final bool invert;

  /// The size of each element preview, which is also the size of
  /// the drag feedback.
  static const previewSize = 56.0;

  @override
  State<ElementsBar> createState() => _ElementsBarState();
}

class _ElementsBarState extends State<ElementsBar> {
  /// Decoded elements, keyed by their encoded string.
  final _cache = <String, CanvasElement?>{};

  /// When true, a delete button is shown on each element.
  var editing = false;

  CanvasElement? _decode(String encoded) => _cache.putIfAbsent(encoded, () {
    try {
      return CanvasElement.decode(encoded);
    } catch (_) {
      return null;
    }
  });

  void _remove(String encoded) {
    stows.savedElements.value = List.of(stows.savedElements.value)
      ..remove(encoded);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return ValueListenableBuilder(
      valueListenable: stows.savedElements,
      builder: (context, savedElements, _) {
        if (savedElements.isEmpty) {
          return Padding(
            padding: const .symmetric(horizontal: 16, vertical: 12),
            child: Text(
              t.editor.elements.empty,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: widget.axis,
          padding: const .all(4),
          child: Flex(
            direction: widget.axis,
            mainAxisSize: .min,
            children: [
              for (final encoded in savedElements)
                if (_decode(encoded) case final element?)
                  _ElementTile(
                    element: element,
                    invert: widget.invert,
                    editing: editing,
                    onTap: () => widget.insertElement(element),
                    onDelete: () => _remove(encoded),
                  ),
              IconButton(
                tooltip: editing
                    ? MaterialLocalizations.of(context).okButtonLabel
                    : t.editor.elements.edit,
                onPressed: () => setState(() => editing = !editing),
                icon: Icon(editing ? Icons.check : Icons.edit_outlined),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ElementTile extends StatelessWidget {
  const new({
    required this.element,
    required this.invert,
    required this.editing,
    required this.onTap,
    required this.onDelete,
  });

  final CanvasElement element;
  final bool invert;
  final bool editing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final preview = ElementPreview(element: element, invert: invert);
    return Padding(
      padding: const .all(2),
      child: Stack(
        clipBehavior: .none,
        children: [
          LongPressDraggable<CanvasElement>(
            data: element,
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(opacity: 0.8, child: preview),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: preview),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: editing ? null : onTap,
              child: preview,
            ),
          ),
          if (editing)
            Positioned(
              top: -4,
              right: -4,
              child: Material(
                color: colorScheme.errorContainer,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onDelete,
                  child: Padding(
                    padding: const .all(2),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: colorScheme.onErrorContainer,
                      semanticLabel: t.editor.favoritePens.remove,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small preview of a [CanvasElement].
class ElementPreview extends StatelessWidget {
  const new({super.key, required this.element, required this.invert});

  final CanvasElement element;
  final bool invert;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: ElementsBar.previewSize,
      child: Padding(
        padding: const .all(6),
        child: CustomPaint(
          painter: _ElementPainter(element: element, invert: invert),
        ),
      ),
    );
  }
}

class _ElementPainter extends CustomPainter {
  const new({required this.element, required this.invert});

  final CanvasElement element;
  final bool invert;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = element.bounds;
    if (bounds.isEmpty) return;

    final scale = min(size.width / bounds.width, size.height / bounds.height);
    canvas.translate(
      (size.width - bounds.width * scale) / 2,
      (size.height - bounds.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);

    final paint = Paint();
    for (final stroke in element.strokes) {
      paint.color = stroke.color.withInversion(invert);
      if (stroke is CircleStroke || stroke is RectangleStroke) {
        paint
          ..style = .stroke
          ..strokeWidth = stroke.options.size;
        if (stroke is CircleStroke) {
          canvas.drawCircle(stroke.center, stroke.radius, paint);
        } else if (stroke is RectangleStroke) {
          canvas.drawRect(stroke.rect, paint);
        }
        paint.style = .fill;
      } else {
        canvas.drawPath(stroke.highQualityPath, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ElementPainter oldDelegate) =>
      element != oldDelegate.element || invert != oldDelegate.invert;
}
