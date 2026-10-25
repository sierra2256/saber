import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/zoom_box.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/canvas_background_pattern.dart';

/// A magnified writing strip (like GoodNotes' Zoom Window):
/// you write large in the strip and it appears small on the page,
/// in the target area of [zoomBox], which moves forward as you write.
class ZoomWritingBox extends StatefulWidget {
  const new({
    super.key,
    required this.zoomBox,
    required this.coreInfo,
    required this.getCurrentStroke,
    required this.onDrawStart,
    required this.onDrawUpdate,
    required this.onDrawEnd,
    required this.updatePointerData,
    required this.onTargetChanged,
    required this.onClose,
  });

  final ZoomBox zoomBox;
  final EditorCoreInfo coreInfo;

  /// The stroke being drawn by this editor, if any.
  final Stroke? Function() getCurrentStroke;

  /// Called with positions in page coordinates.
  final ValueChanged<Offset> onDrawStart;
  final ValueChanged<Offset> onDrawUpdate;
  final VoidCallback onDrawEnd;
  final void Function(PointerDeviceKind kind, double? pressure)
  updatePointerData;

  /// Called when the target area on the page moves.
  final ValueChanged<Rect> onTargetChanged;
  final VoidCallback onClose;

  static const height = 180.0;

  /// The key of the area you write in.
  @visibleForTesting
  static const stripKey = ValueKey('ZoomWritingBox.strip');

  @override
  State<ZoomWritingBox> createState() => _ZoomWritingBoxState();
}

class _ZoomWritingBoxState extends State<ZoomWritingBox> {
  var boxSize = Size.zero;

  /// The pointer currently drawing in the box, if any.
  int? _pointer;

  /// The rightmost point of the current stroke, in page coordinates.
  var _strokeRight = 0.0;

  EditorPage get page => widget.coreInfo.pages[widget.zoomBox.pageIndex];

  void _notifyTargetChanged() {
    if (boxSize.isEmpty) return;
    widget.onTargetChanged(widget.zoomBox.targetFor(boxSize));
  }

  void _move(void Function() move) {
    setState(move);
    _notifyTargetChanged();
  }

  bool _canDraw(PointerEvent event) =>
      stows.editorFingerDrawing.value ||
      event.kind == .stylus ||
      event.kind == .invertedStylus;

  double? _pressure(PointerEvent event) {
    if (event.kind != .stylus && event.kind != .invertedStylus) return null;
    if (event.pressureMin == event.pressureMax) return null;
    return (event.pressure - event.pressureMin) /
        (event.pressureMax - event.pressureMin);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null || !_canDraw(event)) return;
    _pointer = event.pointer;
    widget.updatePointerData(event.kind, _pressure(event));
    final position = widget.zoomBox.toPage(event.localPosition, boxSize);
    _strokeRight = position.dx;
    widget.onDrawStart(position);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    widget.updatePointerData(event.kind, _pressure(event));
    final position = widget.zoomBox.toPage(event.localPosition, boxSize);
    _strokeRight = max(_strokeRight, position.dx);
    widget.onDrawUpdate(position);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    widget.updatePointerData(event.kind, null);
    widget.onDrawEnd();
    if (widget.zoomBox.advanceAfterStroke(_strokeRight, boxSize)) {
      _move(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final zoomBox = widget.zoomBox;
    return Material(
      color: colorScheme.surfaceContainer,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: .antiAlias,
      child: SizedBox(
        height: ZoomWritingBox.height,
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final newSize = constraints.biggest;
                  if (newSize != boxSize) {
                    boxSize = newSize;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _notifyTargetChanged(),
                    );
                  }
                  return Listener(
                    key: ZoomWritingBox.stripKey,
                    behavior: .opaque,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerUp,
                    child: ClipRect(
                      child: CustomPaint(
                        size: boxSize,
                        painter: _ZoomBoxPainter(
                          zoomBox: zoomBox,
                          page: page,
                          coreInfo: widget.coreInfo,
                          getCurrentStroke: widget.getCurrentStroke,
                          invert:
                              stows.editorAutoInvert.value &&
                              Theme.brightnessOf(context) == .dark,
                          primaryColor: colorScheme.primary,
                          secondaryColor: colorScheme.secondary,
                          defaultTextStyle: TextTheme.of(context).bodyMedium!,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SingleChildScrollView(
              child: Column(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                  IconButton(
                    tooltip: t.editor.zoomBox.lineUp,
                    onPressed: () => _move(zoomBox.lineUp),
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: t.editor.zoomBox.back,
                    onPressed: () => _move(() => zoomBox.back(boxSize)),
                    icon: const Icon(Icons.keyboard_arrow_left),
                  ),
                  IconButton(
                    tooltip: t.editor.zoomBox.forward,
                    onPressed: () => _move(() => zoomBox.forward(boxSize)),
                    icon: const Icon(Icons.keyboard_arrow_right),
                  ),
                  IconButton(
                    tooltip: t.editor.zoomBox.newLine,
                    onPressed: () => _move(zoomBox.newLine),
                    icon: const Icon(Icons.keyboard_return),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the target area of the page, magnified,
/// using the same painters as the page itself.
class _ZoomBoxPainter extends CustomPainter {
  new({
    required this.zoomBox,
    required this.page,
    required this.coreInfo,
    required this.getCurrentStroke,
    required this.invert,
    required this.primaryColor,
    required this.secondaryColor,
    required this.defaultTextStyle,
  }) : super(repaint: page);

  final ZoomBox zoomBox;
  final EditorPage page;
  final EditorCoreInfo coreInfo;
  final Stroke? Function() getCurrentStroke;
  final bool invert;
  final Color primaryColor;
  final Color secondaryColor;
  final TextStyle defaultTextStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = zoomBox.scaleFor(size);

    canvas.save();
    canvas.scale(scale);
    canvas.translate(-zoomBox.position.dx, -zoomBox.position.dy);

    CanvasBackgroundPainter(
      invert: invert,
      backgroundColor: page.backgroundImage != null
          ? Colors.white
          : coreInfo.backgroundColor ?? InnerCanvas.defaultBackgroundColor,
      backgroundPattern: page.backgroundImage != null
          ? CanvasBackgroundPattern.none
          : coreInfo.backgroundPattern,
      lineHeight: coreInfo.lineHeight,
      lineThickness: coreInfo.lineThickness,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    ).paint(canvas, page.size);

    final currentStroke = getCurrentStroke();
    CanvasPainter(
      invert: invert,
      strokes: page.strokes,
      laserStrokes: page.laserStrokes,
      currentStroke: currentStroke?.pageIndex == zoomBox.pageIndex
          ? currentStroke
          : null,
      currentSelection: null,
      primaryColor: primaryColor,
      page: page,
      showPageIndicator: false,
      showZoomBoxTarget: false,
      pageIndex: zoomBox.pageIndex,
      totalPages: coreInfo.pages.length,
      currentScale: scale,
      defaultTextStyle: defaultTextStyle,
    ).paint(canvas, page.size);

    canvas.restore();

    // Show where the target will move forward
    final advanceX = size.width * ZoomBox.advanceThreshold;
    canvas.drawRect(
      Rect.fromLTRB(advanceX, 0, size.width, size.height),
      Paint()..color = primaryColor.withValues(alpha: 0.06),
    );
    canvas.drawLine(
      Offset(advanceX, 0),
      Offset(advanceX, size.height),
      Paint()
        ..color = primaryColor.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ZoomBoxPainter oldDelegate) => true;
}
