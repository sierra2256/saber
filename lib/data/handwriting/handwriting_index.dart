import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';

/// The recognized handwriting of one page, see [HandwritingIndex].
class IndexedPage {
  const new({required this.signature, required this.text});

  factory fromJson(Map<String, dynamic> json) =>
      IndexedPage(signature: json['s'] as int, text: json['t'] as String);

  Map<String, dynamic> toJson() => {'s': signature, 't': text};

  /// A hash of the page's handwriting, see [signatureOf].
  /// The page only needs to be recognized again if this changes.
  final int signature;

  /// The recognized text.
  final String text;

  /// Returns a hash of the handwriting in [strokes],
  /// which is the same across app restarts.
  static int signatureOf(Iterable<Stroke> strokes) {
    // FNV-1a, since [Object.hash] isn't guaranteed to be stable
    var hash = 0x811c9dc5;
    void add(int value) {
      hash = ((hash ^ (value & 0xffffffff)) * 0x01000193) & 0xffffffff;
    }

    for (final stroke in strokes) {
      if (!HandwritingRecognizer.isHandwriting(stroke)) continue;
      add(stroke.toolId.index);
      for (final point in stroke.centerline) {
        add((point.dx * 10).round());
        add((point.dy * 10).round());
      }
    }
    return hash;
  }
}

/// A search result from [HandwritingIndex.search].
class HandwritingSearchResult {
  const new({
    required this.filePath,
    required this.pageIndex,
    required this.snippet,
  });

  final String filePath;
  final int pageIndex;

  /// The text around the match.
  final String snippet;
}

/// The recognized handwriting of each note, so notes can be searched
/// for handwritten words.
///
/// This is stored locally and never synced: each device builds its own.
class HandwritingIndex {
  new({required this.file});

  static final log = Logger('HandwritingIndex');

  /// The index file, outside of the (synced) notes folder.
  final File file;

  /// The pages of each note, keyed by the note's file path.
  final _notes = <String, List<IndexedPage>>{};

  var _loaded = false;
  Timer? _saveTimer;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString()) as Map;
      for (final MapEntry(:key, :value) in json.entries) {
        _notes[key as String] = [
          for (final page in value as List)
            IndexedPage.fromJson(Map<String, dynamic>.from(page as Map)),
        ];
      }
    } catch (e) {
      log.warning('Failed to load the handwriting index, starting over: $e');
      _notes.clear();
    }
  }

  /// Saves the index after a short delay, so many changes are
  /// saved together.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_notes));
    } catch (e) {
      log.warning('Failed to save the handwriting index: $e');
    }
  }

  Iterable<String> get filePaths => _notes.keys;

  List<IndexedPage>? pagesOf(String filePath) => _notes[filePath];

  void setPages(String filePath, List<IndexedPage> pages) {
    _notes[filePath] = pages;
    _scheduleSave();
  }

  void remove(String filePath) {
    if (_notes.remove(filePath) != null) _scheduleSave();
  }

  /// Removes everything from the index, e.g. when handwriting
  /// recognition is turned off.
  Future<void> clear() async {
    _saveTimer?.cancel();
    _notes.clear();
    try {
      if (file.existsSync()) await file.delete();
    } catch (e) {
      log.warning('Failed to delete the handwriting index: $e');
    }
  }

  /// The number of characters shown on each side of a match.
  static const snippetContext = 30;

  /// Finds pages whose handwriting contains [query] (ignoring case).
  List<HandwritingSearchResult> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final results = <HandwritingSearchResult>[];
    for (final MapEntry(key: filePath, value: pages) in _notes.entries) {
      for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
        final text = pages[pageIndex].text.replaceAll('\n', ' ');
        final index = text.toLowerCase().indexOf(needle);
        if (index < 0) continue;

        final start = (index - snippetContext).clamp(0, text.length);
        final end = (index + needle.length + snippetContext).clamp(
          0,
          text.length,
        );
        results.add(
          HandwritingSearchResult(
            filePath: filePath,
            pageIndex: pageIndex,
            snippet:
                '${start > 0 ? '…' : ''}'
                '${text.substring(start, end)}'
                '${end < text.length ? '…' : ''}',
          ),
        );
      }
    }
    return results;
  }
}
