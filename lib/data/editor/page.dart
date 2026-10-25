import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show FragmentShader;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/todo.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:sbn/has_size.dart';

typedef CanvasKey = GlobalKey<State<InnerCanvas>>;

class EditorPage extends ChangeNotifier implements HasSize {
  static const double defaultWidth = 1000;
  static const double defaultHeight = defaultWidth * 1.4;
  static const defaultSize = Size(defaultWidth, defaultHeight);

  @override
  final Size size;

  late final CanvasKey innerCanvasKey = CanvasKey();
  RenderBox? _renderBox;
  RenderBox? get renderBox {
    return _renderBox ??=
        innerCanvasKey.currentState?.context.findRenderObject() as RenderBox?;
  }

  var _isRendered = false;
  bool get isRendered => _isRendered;
  set isRendered(bool isRendered) {
    if (isRendered == _isRendered) return;
    _isRendered = isRendered;

    // reset renderBox as renderObject has changed
    _renderBox = null;
  }

  FragmentShader get pencilShader => _pencilShader ??= PencilShader.create();
  FragmentShader? _pencilShader;

  final List<Stroke> strokes;
  final List<LaserStroke> laserStrokes;

  /// Tape strokes that have been tapped to reveal what's underneath.
  /// This isn't saved, so tape is hidden again when the note is reopened.
  final Set<Stroke> revealedTapes = {};

  /// The target area of the zoom writing box, if it's open on this page.
  Rect? zoomBoxTarget;
  final List<EditorImage> images;

  /// The to-do boxes on this page.
  ///
  /// This list is replaced (rather than modified) when it changes,
  /// so the old list can be kept for undo.
  List<TodoBox> todos;

  /// The to-do to highlight briefly, e.g. after opening it from the
  /// to-do overview. This isn't saved.
  int? highlightedTodoId;
  final QuillStruct quill;

  EditorImage? backgroundImage;

  bool get isEmpty =>
      strokes.isEmpty &&
      images.isEmpty &&
      todos.isEmpty &&
      quill.controller.document.isEmpty() &&
      backgroundImage == null;
  bool get isNotEmpty => !isEmpty;

  /// The height of the canvas cropped to the content.
  double previewHeight({required int lineHeight}) {
    // avoid dividing by zero (this should never happen)
    assert(size.height != 0);
    assert(size.width != 0);
    if (size.height == 0 || size.width == 0) {
      return 0;
    }

    // if we have a background image, show full height
    if (backgroundImage != null) {
      return size.height;
    }

    /// The maximum y value of any stroke, image, or text.
    double maxY = 0;
    for (final stroke in strokes) {
      maxY = max(maxY, stroke.maxY);
    }
    for (final image in images) {
      maxY = max(maxY, image.dstRect.bottom);
    }
    if (!quill.controller.document.isEmpty()) {
      // this does not account for text that wraps to the next line
      final int linesOfText = quill.controller.document
          .toPlainText()
          .split('\n')
          .length;
      maxY = max(maxY, linesOfText * lineHeight * 1.5); // ×1.5 fudge factor
    }

    /// The uncropped height of the page.
    /// In lots of cases, this is [Editor.defaultHeight].
    final fullHeight = size.height;

    /// The height of the canvas (cropped),
    /// adjusted to be between 10% and 100% of the full height.
    final croppedHeight = min(fullHeight, max(maxY, 0) + (0.1 * fullHeight));

    return croppedHeight;
  }

  new({
    Size? size,
    double? width,
    double? height,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    QuillStruct? quill,
    this.backgroundImage,
    List<TodoBox>? todos,
  }) : assert(
         (size == null) || (width == null && height == null),
         "size and width/height shouldn't both be specified",
       ),
       size = size ?? Size(width ?? defaultWidth, height ?? defaultHeight),
       strokes = strokes ?? [],
       laserStrokes = [],
       images = images ?? [],
       todos = todos ?? const [],
       quill =
           quill ??
           QuillStruct(
             controller: QuillController.basic(),
             focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
           );

  factory fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    required bool readOnly,
    required int fileVersion,
    required String sbnPath,
    required AssetCache assetCache,
  }) {
    final size = Size(json['w'] ?? defaultWidth, json['h'] ?? defaultHeight);
    return EditorPage(
      size: size,
      strokes: parseStrokesJson(
        json['s'] as List?,
        page: HasSize(size),
        onlyFirstPage: false,
        fileVersion: fileVersion,
      ),
      images: parseImagesJson(
        json['i'] as List?,
        inlineAssets: inlineAssets,
        isThumbnail: readOnly,
        onlyFirstPage: false,
        sbnPath: sbnPath,
        assetCache: assetCache,
      ),
      quill: QuillStruct(
        controller: json['q'] != null
            ? QuillController(
                document: Document.fromJson(json['q'] as List),
                selection: const TextSelection.collapsed(offset: 0),
              )
            : QuillController.basic(),
        focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
      ),
      backgroundImage: json['b'] != null
          ? parseImageJson(
              json['b'],
              inlineAssets: inlineAssets,
              isThumbnail: false,
              sbnPath: sbnPath,
              assetCache: assetCache,
            )
          : null,
      todos: [
        for (final todo in (json['td'] as List?) ?? const [])
          TodoBox.fromJson(Map<String, dynamic>.from(todo as Map)),
      ],
    );
  }

  Map<String, dynamic> toJson(
    OrderedAssetCache assets, {
    bool packStrokePoints = false,
  }) => {
    'w': size.width,
    'h': size.height,
    if (strokes.isNotEmpty)
      's': strokes
          .map((stroke) => stroke.toJson(packPoints: packStrokePoints))
          .toList(),
    if (images.isNotEmpty)
      'i': images.map((image) => image.toJson(assets)).toList(),
    if (!quill.controller.document.isEmpty())
      'q': quill.controller.document.toDelta().toJson(),
    if (backgroundImage != null) 'b': backgroundImage?.toJson(assets),
    if (todos.isNotEmpty) 'td': [for (final todo in todos) todo.toJson()],
  };

  /// A cheap hash of how this page looks, used to tell whether it changed,
  /// e.g. to skip regenerating a note's thumbnail.
  /// This is only stable within one run of the app.
  int get contentHash => Object.hash(
    size,
    Object.hashAll(strokes.map((stroke) => stroke.contentHash)),
    Object.hashAll(images.map((image) => Object.hash(image, image.dstRect))),
    backgroundImage,
    quill.controller.document.toPlainText(),
    Object.hashAll(todos),
  );

  /// Inserts a stroke, while keeping the strokes sorted by
  /// pen type and color.
  void insertStroke(Stroke newStroke) {
    final int newStrokeColor = newStroke.color.toARGB32();

    int index = 0;
    for (final stroke in strokes) {
      final penTypeComparison = stroke.toolId.id.compareTo(newStroke.toolId.id);
      final color = stroke.color.toARGB32();
      if (penTypeComparison > 0) {
        break; // this stroke's pen type comes after the new stroke's pen type
      } else if (stroke.toolId == .highlighter &&
          penTypeComparison == 0 &&
          color > newStrokeColor) {
        break; // this highlighter color comes after the new highlighter color
      }
      index++;
    }

    strokes.insert(index, newStroke);
  }

  /// Sorts the strokes by pen type and color.
  void sortStrokes() {
    strokes.sort((Stroke a, Stroke b) {
      final penTypeComparison = a.toolId.id.compareTo(b.toolId.id);
      if (penTypeComparison != 0) return penTypeComparison;
      if (a.toolId != .highlighter) return 0;
      return a.color.toARGB32().compareTo(b.color.toARGB32());
    });
  }

  static List<Stroke> parseStrokesJson(
    List<dynamic>? strokes, {
    required HasSize page,
    required bool onlyFirstPage,
    required int fileVersion,
  }) => (strokes ?? [])
      .map((dynamic stroke) {
        final map = stroke as Map<String, dynamic>;
        final pageIndex = map['i'] ?? 0;
        if (onlyFirstPage && pageIndex > 0) return null;
        return Stroke.fromJson(
          map,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      })
      .where((element) => element != null)
      .cast<Stroke>()
      .toList();

  static List<EditorImage> parseImagesJson(
    List<dynamic>? images, {
    required List<Uint8List>? inlineAssets,
    required bool isThumbnail,
    required bool onlyFirstPage,
    required String sbnPath,
    required AssetCache assetCache,
  }) =>
      images
          ?.cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> image) {
            if (onlyFirstPage && image['i'] > 0) return null;
            return parseImageJson(
              image,
              inlineAssets: inlineAssets,
              isThumbnail: isThumbnail,
              sbnPath: sbnPath,
              assetCache: assetCache,
            );
          })
          .where((element) => element != null)
          .cast<EditorImage>()
          .toList() ??
      [];

  static EditorImage parseImageJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    required bool isThumbnail,
    required String sbnPath,
    required AssetCache assetCache,
  }) => EditorImage.fromJson(
    json,
    inlineAssets: inlineAssets,
    isThumbnail: isThumbnail,
    sbnPath: sbnPath,
    assetCache: assetCache,
  );

  /// Triggers a redraw of the strokes. If you need to redraw images,
  /// call [setState] instead.
  /// Notified when the committed strokes change,
  /// but not while a new stroke is being drawn.
  /// See [redrawStrokes] and [redrawCurrentStroke].
  final strokesListenable = _RepaintNotifier();

  /// Redraws everything on the page, e.g. after strokes are erased or moved.
  void redrawStrokes() {
    notifyListeners();
    strokesListenable.notify();
  }

  /// Only redraws what's being drawn on top of the page
  /// (the current stroke, the lasso, laser strokes...),
  /// which is much cheaper than [redrawStrokes] on pages with many strokes.
  void redrawCurrentStroke() {
    notifyListeners();
  }

  /// Updates the `pageIndex` fields of this page's strokes/images.
  void updatePageIndex(int pageIndex) {
    for (final stroke in strokes) stroke.pageIndex = pageIndex;
    for (final stroke in laserStrokes) stroke.pageIndex = pageIndex;
    for (final image in images) image.pageIndex = pageIndex;
    backgroundImage?.pageIndex = pageIndex;
  }

  @override
  void dispose() {
    quill.dispose();
    _pencilShader?.dispose();
    isRendered = false;
    for (final image in images) {
      image.dispose();
    }
    backgroundImage?.dispose();
    strokesListenable.dispose();
    super.dispose();
  }

  /// [cloneForRasterization] creates some new resources that need to be
  /// disposed, but it also contains some resources from the original page
  /// that should not be disposed since they are still in use.
  ///
  /// Call this method instead of [dispose] to dispose only the resources
  /// exclusive to the cloned page.
  void disposeClonedData() {
    quill.dispose();
    _pencilShader?.dispose();
    isRendered = false;
    strokesListenable.dispose();
    super.dispose();
  }

  EditorPage copyWith({
    Size? size,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    QuillStruct? quill,
    EditorImage? backgroundImage,
    List<TodoBox>? todos,
  }) => EditorPage(
    size: size ?? this.size,
    strokes: strokes ?? this.strokes,
    images: images ?? this.images,
    quill: quill ?? this.quill,
    backgroundImage: backgroundImage ?? this.backgroundImage,
    todos: todos ?? this.todos,
  );

  /// Clones this page for use in a screenshot.
  ///
  /// Avoids bugs caused by the quill editor being attached to multiple
  /// contexts, and filters out strokes that shouldn't be rasterized.
  ///
  /// Make sure to call [disposeClonedData] on the returned page when
  /// you're done with it.
  EditorPage cloneForRasterization({bool rasterizeAllStrokes = false}) {
    return copyWith(
      strokes: rasterizeAllStrokes
          ? strokes
          : strokes.where(EditorExporter.shouldRasterizeStroke).toList(),
      quill: quill.cloneForScreenshot(),
    );
  }
}

class QuillStruct {
  final QuillController controller;
  late final FocusNode focusNode;
  StreamSubscription? changeSubscription;

  new({required this.controller, required this.focusNode});

  void dispose() {
    changeSubscription?.cancel();
    focusNode.dispose();
    controller.dispose();
  }

  QuillStruct cloneForScreenshot() => QuillStruct(
    controller: QuillController(
      document: Document.fromDelta(controller.document.toDelta()),
      selection: const TextSelection.collapsed(offset: 0),
    ),
    focusNode: FocusNode(debugLabel: 'Screenshot Quill Focus Node'),
  );
}

class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
