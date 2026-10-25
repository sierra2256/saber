import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/handwriting/handwriting_index.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

/// Keeps the [HandwritingIndex] up to date in the background.
///
/// Notes are indexed when the app starts and whenever they are saved
/// (or synced), and only pages whose handwriting changed are recognized.
class HandwritingIndexer {
  new({
    required this.index,
    this._recognizer,
    Future<EditorCoreInfo> Function(String filePath)? loadNote,
    this._fileOperations,
    Future<List<String>> Function()? getAllNotes,
    this.debounce = const Duration(seconds: 2),
  }) : _loadNote = loadNote ?? EditorCoreInfo.loadFromFilePath,
       _getAllNotes = getAllNotes ?? FileManager.getAllFiles;

  static final log = Logger('HandwritingIndexer');

  /// The indexer used by the app, created by [init].
  static HandwritingIndexer? instance;

  /// Creates [instance] and starts or stops it whenever
  /// [stows.handwritingRecognition] changes.
  static Future<void> init() async {
    if (!HandwritingRecognizer.instance.isSupported) return;
    final supportDir = await getApplicationSupportDirectory();
    final indexer = instance = HandwritingIndexer(
      index: HandwritingIndex(
        file: File(p.join(supportDir.path, 'handwriting_index.json')),
      ),
    );

    await stows.handwritingRecognition.waitUntilRead();
    void onPrefChanged() {
      if (stows.handwritingRecognition.value) {
        indexer.start();
      } else {
        indexer.stop(clearIndex: true);
      }
    }

    stows.handwritingRecognition.addListener(onPrefChanged);
    onPrefChanged();
  }

  final HandwritingIndex index;
  final HandwritingRecognizer? _recognizer;
  HandwritingRecognizer get recognizer =>
      _recognizer ?? HandwritingRecognizer.instance;
  final Future<EditorCoreInfo> Function(String filePath) _loadNote;
  final Stream<FileOperation>? _fileOperations;
  final Future<List<String>> Function() _getAllNotes;

  /// How long to wait after a note changes before indexing it,
  /// so a note isn't indexed many times while it's being saved.
  final Duration debounce;

  /// Whether notes are currently being indexed.
  final isIndexing = ValueNotifier(false);

  /// Notes waiting to be indexed, in order.
  final _queue = <String>{};
  final _debounceTimers = <String, Timer>{};
  StreamSubscription<FileOperation>? _subscription;
  var _started = false;

  /// Starts indexing all notes, and listens for changes.
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
  }

  /// Stops indexing, and deletes the index if [clearIndex] is true.
  Future<void> stop({bool clearIndex = false}) async {
    _started = false;
    await _subscription?.cancel();
    _subscription = null;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _queue.clear();
    if (clearIndex) await index.clear();
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
  void enqueue(String filePath) {
    if (!_started) return;
    if (Editor.isReservedPath(filePath)) return;
    _queue.add(filePath);
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
      isIndexing.value = true;
      try {
        while (_queue.isNotEmpty && _started) {
          final filePath = _queue.first;
          _queue.remove(filePath);
          await indexNote(filePath);
        }
      } finally {
        isIndexing.value = false;
        _processing = null;
      }
    }();
  }

  /// Recognizes the handwriting of any pages of the note at [filePath]
  /// that changed since they were last indexed.
  @visibleForTesting
  Future<void> indexNote(String filePath) async {
    final EditorCoreInfo coreInfo;
    try {
      coreInfo = await _loadNote(filePath);
    } catch (e) {
      log.warning('Failed to load $filePath for indexing: $e');
      return;
    }

    try {
      if (coreInfo.pages.isEmpty) {
        index.remove(filePath);
        return;
      }

      final oldPages = index.pagesOf(filePath) ?? const [];
      final newPages = <IndexedPage>[];
      for (int i = 0; i < coreInfo.pages.length; i++) {
        final strokes = coreInfo.pages[i].strokes;
        final signature = IndexedPage.signatureOf(strokes);
        final oldPage = i < oldPages.length ? oldPages[i] : null;
        if (oldPage?.signature == signature) {
          newPages.add(oldPage!);
          continue;
        }
        final text = await recognizer.recognize(strokes);
        if (!_started) return;
        newPages.add(IndexedPage(signature: signature, text: text));
      }
      index.setPages(filePath, newPages);
    } finally {
      coreInfo.dispose();
    }
  }
}
