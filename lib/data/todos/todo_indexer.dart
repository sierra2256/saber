import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/handwriting/handwriting_index.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/todos/todo_index.dart';
import 'package:saber/pages/editor/editor.dart';

/// Keeps the [TodoIndex] up to date in the background.
///
/// Notes are indexed when the app starts (only those that changed since
/// they were last indexed) and whenever they are saved or synced.
class TodoIndexer {
  new({
    required this.index,
    this._recognizer,
    Future<EditorCoreInfo> Function(String filePath)? loadNote,
    Future<String?> Function(String filePath)? stampOf,
    this._fileOperations,
    Future<List<String>> Function()? getAllNotes,
    bool Function()? recognitionEnabled,
    this.labelImagesDir,
    this.debounce = const Duration(seconds: 2),
  }) : _loadNote = loadNote ?? EditorCoreInfo.loadFromFilePath,
       _stampOf = stampOf ?? fileStampOf,
       _getAllNotes = getAllNotes ?? FileManager.getAllFiles,
       _recognitionEnabled =
           recognitionEnabled ?? (() => stows.handwritingRecognition.value);

  static final log = Logger('TodoIndexer');

  /// The indexer used by the app, created by [init].
  static TodoIndexer? instance;

  /// The app's [TodoIndex], or null before [init].
  static TodoIndex? get appIndex => instance?.index;

  /// Creates and starts [instance].
  static Future<void> init() async {
    final supportDir = await getApplicationSupportDirectory();
    final indexer = instance = TodoIndexer(
      index: TodoIndex(file: File(p.join(supportDir.path, 'todo_index.json'))),
      labelImagesDir: Directory(p.join(supportDir.path, 'todo_labels')),
    );

    // Recognize (or forget) the labels' handwriting
    // when handwriting recognition is turned on (or off)
    await stows.handwritingRecognition.waitUntilRead();
    stows.handwritingRecognition.addListener(indexer.reindexAll);

    await indexer.start();
  }

  final TodoIndex index;
  final HandwritingRecognizer? _recognizer;
  HandwritingRecognizer get recognizer =>
      _recognizer ?? HandwritingRecognizer.instance;
  final Future<EditorCoreInfo> Function(String filePath) _loadNote;
  final Future<String?> Function(String filePath) _stampOf;
  final Stream<FileOperation>? _fileOperations;
  final Future<List<String>> Function() _getAllNotes;
  final bool Function() _recognitionEnabled;

  /// Where pictures of the labels' handwriting are kept, see [labelImageOf].
  /// If null, no pictures are made.
  final Directory? labelImagesDir;

  /// How long to wait after a note changes before indexing it,
  /// so a note isn't indexed many times while it's being saved.
  final Duration debounce;

  /// Notes waiting to be indexed, in order.
  final _queue = <String>{};

  /// Notes in [_queue] to index even if their file didn't change.
  final _forced = <String>{};
  final _debounceTimers = <String, Timer>{};
  StreamSubscription<FileOperation>? _subscription;
  var _started = false;

  /// The modification time and size of the note at [filePath],
  /// or null if it doesn't exist.
  static Future<String?> fileStampOf(String filePath) async {
    for (final extension in [Editor.extension, Editor.extensionOldJson]) {
      final file = FileManager.getFile('$filePath$extension');
      if (!file.existsSync()) continue;
      final stat = file.statSync();
      return '${stat.modified.millisecondsSinceEpoch}:${stat.size}';
    }
    return null;
  }

  /// Indexes all notes that changed, and listens for changes.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await index.load();

    _subscription = (_fileOperations ?? FileManager.fileWriteStream.stream)
        .listen(_onFileOperation);

    final notes = await _getAllNotes();
    if (!_started) return;
    // forget notes that no longer exist
    final existing = notes.toSet();
    for (final filePath in index.filePaths.toList()) {
      if (!existing.contains(filePath)) index.remove(filePath);
    }
    notes.forEach(enqueue);
    unawaited(idle.then((_) => _deleteUnusedLabelImages()));
  }

  /// The picture of [todo]'s handwritten label, shown in the to-do
  /// overview when its handwriting isn't recognized.
  /// Null if there is no label, or no picture of it.
  File? labelImageOf(String filePath, IndexedTodo todo) {
    final dir = labelImagesDir;
    if (dir == null || todo.kind != .drawn || todo.labelSignature == 0) {
      return null;
    }
    final file = File(p.join(dir.path, _labelImageName(filePath, todo)));
    return file.existsSync() ? file : null;
  }

  /// The file name of the picture of [todo]'s label. It changes when
  /// the label changes, since it includes [IndexedTodo.labelSignature].
  static String _labelImageName(String filePath, IndexedTodo todo) =>
      '${_hashOf(filePath)}_${todo.pageIndex}_${todo.id}_'
      '${todo.labelSignature}.png';

  /// A hash of [text] that is the same across app restarts (FNV-1a).
  static String _hashOf(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  /// Deletes pictures of labels that changed or were removed.
  Future<void> _deleteUnusedLabelImages() async {
    final dir = labelImagesDir;
    if (dir == null || !dir.existsSync() || !_started) return;
    final used = <String>{
      for (final MapEntry(key: filePath, value: note) in index.notes.entries)
        for (final todo in note.todos)
          if (todo.kind == .drawn && todo.labelSignature != 0)
            _labelImageName(filePath, todo),
    };
    try {
      for (final file in dir.listSync().whereType<File>()) {
        if (!used.contains(p.basename(file.path))) file.deleteSync();
      }
    } catch (e) {
      log.warning('Failed to delete unused to-do label pictures: $e');
    }
  }

  /// Draws [strokes] as a picture [height] pixels high.
  @visibleForTesting
  static Future<Uint8List?> renderLabel(
    List<Stroke> strokes, {
    double height = 48,
  }) async {
    if (strokes.isEmpty) return null;
    var bounds = strokes.first.highQualityPath.getBounds();
    for (final stroke in strokes.skip(1)) {
      bounds = bounds.expandToInclude(stroke.highQualityPath.getBounds());
    }
    bounds = bounds.inflate(4);
    final scale = (height / bounds.height).clamp(0.1, 2.0);
    final width = (bounds.width * scale).clamp(1.0, 800.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    for (final stroke in strokes) {
      canvas.drawPath(
        stroke.highQualityPath,
        Paint()..color = stroke.color.withValues(alpha: 1),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      width.ceil(),
      (bounds.height * scale).ceil(),
    );
    picture.dispose();
    try {
      final bytes = await image.toByteData(format: .png);
      return bytes?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> stop() async {
    _started = false;
    await _subscription?.cancel();
    _subscription = null;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _queue.clear();
    _forced.clear();
  }

  /// Indexes all notes with to-dos again, e.g. to recognize their labels.
  void reindexAll() {
    for (final MapEntry(key: filePath, value: note) in index.notes.entries) {
      if (note.todos.any((todo) => todo.kind == .drawn)) {
        enqueue(filePath, force: true);
      }
    }
  }

  void _onFileOperation(FileOperation operation) {
    final filePath = operation.filePath;
    // ignore assets and thumbnails, e.g. "note.sbn2.0" or "note.sbn2.p"
    if (FileManager.assetFileRegex.hasMatch(filePath)) return;

    switch (operation.type) {
      case .delete:
        _debounceTimers.remove(filePath)?.cancel();
        _queue.remove(filePath);
        index.remove(filePath);
      case .write:
        _debounceTimers[filePath]?.cancel();
        _debounceTimers[filePath] = Timer(debounce, () {
          _debounceTimers.remove(filePath);
          enqueue(filePath);
        });
    }
  }

  /// Adds a note to the queue of notes to index.
  /// Unless [force] is true, it is skipped if it didn't change
  /// since it was last indexed.
  void enqueue(String filePath, {bool force = false}) {
    if (!_started) return;
    if (Editor.isReservedPath(filePath)) return;
    _queue.add(filePath);
    if (force) _forced.add(filePath);
    unawaited(_processQueue());
  }

  Future<void>? _processing;

  /// Completes when the queue is empty.
  @visibleForTesting
  Future<void> get idle async {
    while (_processing != null) {
      await _processing;
    }
  }

  Future<void> _processQueue() {
    return _processing ??= () async {
      try {
        while (_queue.isNotEmpty && _started) {
          final filePath = _queue.first;
          _queue.remove(filePath);
          final force = _forced.remove(filePath);
          await indexNote(filePath, force: force);
        }
      } finally {
        _processing = null;
      }
    }();
  }

  /// Finds the to-dos in the note at [filePath],
  /// unless it didn't change since it was last indexed.
  @visibleForTesting
  Future<void> indexNote(String filePath, {bool force = false}) async {
    final stamp = await _stampOf(filePath);
    if (stamp == null) {
      index.remove(filePath);
      return;
    }
    final old = index.noteOf(filePath);
    if (!force && old?.stamp == stamp) return;

    final EditorCoreInfo coreInfo;
    try {
      coreInfo = await _loadNote(filePath);
    } catch (e) {
      log.warning('Failed to load $filePath for indexing: $e');
      return;
    }

    try {
      final todos = await todosOf(
        coreInfo,
        previous: old?.todos,
        filePath: filePath,
      );
      if (!_started) return;
      // (notes without to-dos are kept too, so they aren't loaded again)
      index.setNote(filePath, IndexedNoteTodos(stamp: stamp, todos: todos));
    } finally {
      coreInfo.dispose();
    }
  }

  /// The to-dos in [coreInfo]: the drawn to-do boxes,
  /// and the checklist items in the typed text.
  ///
  /// The labels of drawn to-dos are recognized if handwriting recognition
  /// is on, reusing the labels in [previous] that didn't change.
  @visibleForTesting
  Future<List<IndexedTodo>> todosOf(
    EditorCoreInfo coreInfo, {
    List<IndexedTodo>? previous,
    String? filePath,
  }) async {
    final recognize =
        _recognitionEnabled() &&
        recognizer.isSupported &&
        await recognizer.isModelDownloaded();
    final previousLabels = {
      for (final todo in previous ?? const <IndexedTodo>[])
        if (todo.kind == .drawn && todo.label != null)
          (todo.pageIndex, todo.id, todo.labelSignature): todo.label!,
    };

    final todos = <IndexedTodo>[];
    for (var pageIndex = 0; pageIndex < coreInfo.pages.length; pageIndex++) {
      final page = coreInfo.pages[pageIndex];
      for (final todo in page.todos) {
        final labelStrokes = todo.labelStrokes(
          page.strokes,
          page.size.width,
          page.todos,
        );
        final signature = labelStrokes.isEmpty
            ? 0
            : IndexedPage.signatureOf(labelStrokes);
        String? label;
        if (recognize && signature != 0) {
          label =
              previousLabels[(pageIndex, todo.id, signature)] ??
              await recognizer.recognize(labelStrokes);
          if (label.isEmpty) label = null;
        }
        final indexed = IndexedTodo(
          kind: .drawn,
          id: todo.id,
          pageIndex: pageIndex,
          top: todo.rect.top,
          closed: todo.isClosed,
          closedAt: todo.closedAt,
          label: label?.replaceAll('\n', ' '),
          labelSignature: signature,
        );
        todos.add(indexed);
        if (label == null && filePath != null) {
          await _saveLabelImage(filePath, indexed, labelStrokes);
        }
      }

      todos.addAll(
        typedTodosOf(page.quill.controller.document.toDelta(), pageIndex),
      );
    }
    return todos;
  }

  Future<void> _saveLabelImage(
    String filePath,
    IndexedTodo todo,
    List<Stroke> labelStrokes,
  ) async {
    final dir = labelImagesDir;
    if (dir == null || labelStrokes.isEmpty) return;
    if (labelImageOf(filePath, todo) != null) return; // already saved
    try {
      final bytes = await renderLabel(labelStrokes);
      if (bytes == null) return;
      await dir.create(recursive: true);
      await File(p.join(dir.path, _labelImageName(filePath, todo)))
          .writeAsBytes(bytes);
    } catch (e) {
      log.warning('Failed to save a picture of a to-do label: $e');
    }
  }

  /// The checklist items in [delta], the typed text of page [pageIndex].
  static List<IndexedTodo> typedTodosOf(Delta delta, int pageIndex) {
    final todos = <IndexedTodo>[];
    final line = StringBuffer();
    var lineNumber = 0;
    for (final op in delta.toList()) {
      final data = op.data;
      if (data is! String) continue;
      final parts = data.split('\n');
      for (var i = 0; i < parts.length; i++) {
        line.write(parts[i]);
        if (i == parts.length - 1) break;

        // end of a line, whose format is in this newline's attributes
        final list = op.attributes?['list'];
        if (list == 'checked' || list == 'unchecked') {
          final text = line.toString().trim();
          todos.add(
            IndexedTodo(
              kind: .typed,
              id: todos.length,
              pageIndex: pageIndex,
              top: lineNumber.toDouble(),
              closed: list == 'checked',
              label: text.isEmpty ? null : text,
            ),
          );
        }
        line.clear();
        lineNumber++;
      }
    }
    return todos;
  }
}
