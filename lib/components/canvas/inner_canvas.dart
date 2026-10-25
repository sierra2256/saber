import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/canvas_background_pattern.dart';
import 'package:sbn/quill_styles.dart';

class InnerCanvas extends StatefulWidget {
  const new({
    super.key,
    required this.pageIndex,
    this.redrawPageListenable,
    required this.width,
    required this.height,
    this.showPageIndicator = true,
    this.textEditing = false,
    required this.coreInfo,
    required this.currentStroke,
    required this.currentStrokeDetectedShape,
    required this.currentSelection,
    this.setAsBackground,
    this.onRenderObjectChange,
    required this.currentToolIsSelect,
    required this.currentScale,
  });

  final int pageIndex;
  final Listenable? redrawPageListenable;
  final double width;
  final double height;
  final bool showPageIndicator;
  final bool textEditing;
  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  final RecognizedUnistroke? currentStrokeDetectedShape;
  final SelectResult? currentSelection;
  final void Function(EditorImage image)? setAsBackground;
  final ValueChanged<RenderObject>? onRenderObjectChange;

  final bool currentToolIsSelect;

  final double currentScale;

  static const defaultBackgroundColor = Color(0xFFFCFCFC);

  @override
  State<InnerCanvas> createState() => _InnerCanvasState();
}

class _InnerCanvasState extends State<InnerCanvas> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;
    final invert = stows.editorAutoInvert.value && brightness == .dark;
    final Color backgroundColor =
        widget.coreInfo.backgroundColor ?? InnerCanvas.defaultBackgroundColor;

    if (widget.coreInfo.pages.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final page = widget.coreInfo.pages[widget.pageIndex];

    final quillEditor = widget.coreInfo.pages.isNotEmpty
        ? QuillEditor(
            controller:
                widget.coreInfo.pages[widget.pageIndex].quill.controller,
            config: QuillEditorConfig(
              customStyles: SaberQuillStyles.get(
                invert: invert,
                secondary: colorScheme.secondary,
                lineHeight: widget.coreInfo.lineHeight,
              ),
              scrollable: false,
              autoFocus: false,
              expands: true,
              placeholder: widget.textEditing
                  ? t.editor.quill.typeSomething
                  : null,
              showCursor: true,
              keyboardAppearance: invert ? .dark : .light,
              padding: .only(
                top: widget.coreInfo.lineHeight * 1.2,
                left: widget.coreInfo.lineHeight * 0.5,
                right: widget.coreInfo.lineHeight * 0.5,
                bottom: widget.coreInfo.lineHeight * 0.5,
              ),
              showCodeBlockLineNumbers: false,
            ),
            scrollController: ScrollController(),
            focusNode: widget.coreInfo.pages[widget.pageIndex].quill.focusNode,
          )
        : null;

    CanvasPainter painter(
      Set<CanvasPainterLayer> layers, {
      required Listenable? repaint,
    }) => CanvasPainter(
      repaint: repaint,
      layers: layers,
      invert: invert,
      strokes: page.strokes,
      laserStrokes: page.laserStrokes,
      currentStroke: widget.currentStroke,
      currentSelection: widget.currentSelection,
      primaryColor: colorScheme.primary,
      page: page,
      showPageIndicator: widget.showPageIndicator,
      pageIndex: widget.pageIndex,
      totalPages: widget.coreInfo.pages.length,
      currentScale: widget.currentScale,
      defaultTextStyle: theme.textTheme.bodyMedium!,
    );

    // Committed strokes only repaint when they change, not while drawing
    final strokesRepaint = widget.redrawPageListenable != null
        ? page.strokesListenable
        : null;

    // Each layer has its own repaint boundary, so drawing a new stroke
    // only repaints the overlay, not every stroke on the page.
    return RepaintBoundary(
      child: Stack(
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: CanvasBackgroundPainter(
                invert: invert,
                backgroundColor: () {
                  if (page.backgroundImage != null) {
                    return Colors.white;
                  } else {
                    return backgroundColor;
                  }
                }(),
                backgroundPattern: () {
                  if (page.backgroundImage != null) {
                    return CanvasBackgroundPattern.none;
                  } else {
                    return widget.coreInfo.backgroundPattern;
                  }
                }(),
                lineHeight: widget.coreInfo.lineHeight,
                lineThickness: widget.coreInfo.lineThickness,
                primaryColor: colorScheme.primary,
                secondaryColor: colorScheme.secondary,
              ),
              // Highlighters are in the same layer as the background,
              // images and text, since they blend with them.
              foregroundPainter: painter(const {
                CanvasPainterLayer.highlighters,
              }, repaint: strokesRepaint),
              isComplex: true,
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: DeferredPointerHandler(
                  child: Stack(
                    children: [
                      if (page.backgroundImage != null)
                        CanvasImage(
                          filePath: widget.coreInfo.filePath,
                          image: page.backgroundImage!,
                          pageSize: Size(widget.width, widget.height),
                          setAsBackground: null,
                          isBackground: true,
                          readOnly: true,
                        ),
                      Positioned(
                        top: 0,
                        left: 0,
                        width: widget.width,
                        height: widget.height,
                        child: IgnorePointer(
                          ignoring:
                              widget.coreInfo.readOnly || !widget.textEditing,
                          child: quillEditor,
                        ),
                      ),
                      for (int i = 0; i < page.images.length; i++)
                        CanvasImage(
                          filePath: widget.coreInfo.filePath,
                          image: page.images[i],
                          pageSize: Size(widget.width, widget.height),
                          setAsBackground: widget.setAsBackground,
                          readOnly:
                              widget.coreInfo.readOnly ||
                              !widget.currentToolIsSelect,
                          selected:
                              widget.currentSelection?.images.contains(
                                page.images[i],
                              ) ??
                              false,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: painter(const {
                    CanvasPainterLayer.ink,
                  }, repaint: strokesRepaint),
                  isComplex: true,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: painter(const {
                    CanvasPainterLayer.overlay,
                  }, repaint: widget.redrawPageListenable),
                  willChange: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
