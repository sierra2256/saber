import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Where a to-do comes from.
enum TodoKind {
  /// A to-do box drawn on the page, see [TodoBox].
  drawn,

  /// A checklist item in the typed text of a page.
  typed,
}

/// A to-do in a note, see [TodoIndex].
@immutable
class IndexedTodo {
  const new({
    required this.kind,
    required this.id,
    required this.pageIndex,
    required this.top,
    required this.closed,
    this.closedAt,
    this.label,
    this.labelSignature = 0,
  });

  factory fromJson(Map<String, dynamic> json) => IndexedTodo(
    kind: TodoKind.values.byName(json['k'] as String),
    id: (json['id'] as num).toInt(),
    pageIndex: (json['p'] as num).toInt(),
    top: (json['y'] as num).toDouble(),
    closed: json['x'] as bool,
    closedAt: json['c'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((json['c'] as num).toInt()),
    label: json['l'] as String?,
    labelSignature: (json['ls'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'k': kind.name,
    'id': id,
    'p': pageIndex,
    'y': top,
    'x': closed,
    if (closedAt != null) 'c': closedAt!.millisecondsSinceEpoch,
    if (label != null) 'l': label,
    if (labelSignature != 0) 'ls': labelSignature,
  };

  final TodoKind kind;

  /// For [TodoKind.drawn], the [TodoBox.id].
  /// For [TodoKind.typed], the index of the checklist item on its page.
  final int id;

  final int pageIndex;

  /// How far down the page the to-do is, used to sort to-dos.
  /// For typed to-dos, this is the line number.
  final double top;

  final bool closed;

  /// When a drawn to-do was closed. Typed to-dos don't have this.
  final DateTime? closedAt;

  /// The typed text, or the recognized handwriting if handwriting
  /// recognition is on. Null if there's no text.
  final String? label;

  /// A hash of the label's handwriting, so it's only recognized again
  /// when it changes.
  final int labelSignature;

  IndexedTodo copyWith({String? label}) => IndexedTodo(
    kind: kind,
    id: id,
    pageIndex: pageIndex,
    top: top,
    closed: closed,
    closedAt: closedAt,
    label: label ?? this.label,
    labelSignature: labelSignature,
  );

  @override
  bool operator ==(Object other) =>
      other is IndexedTodo &&
      other.kind == kind &&
      other.id == id &&
      other.pageIndex == pageIndex &&
      other.top == top &&
      other.closed == closed &&
      other.closedAt == closedAt &&
      other.label == label &&
      other.labelSignature == labelSignature;

  @override
  int get hashCode => Object.hash(
    kind,
    id,
    pageIndex,
    top,
    closed,
    closedAt,
    label,
    labelSignature,
  );
}

/// The to-dos of one note, see [TodoIndex].
class IndexedNoteTodos {
  const new({required this.stamp, required this.todos});

  factory fromJson(Map<String, dynamic> json) => IndexedNoteTodos(
    stamp: json['s'] as String,
    todos: [
      for (final todo in json['t'] as List)
        IndexedTodo.fromJson(Map<String, dynamic>.from(todo as Map)),
    ],
  );

  Map<String, dynamic> toJson() => {
    's': stamp,
    't': [for (final todo in todos) todo.toJson()],
  };

  /// The note file's modification time and size when it was indexed.
  /// The note only needs to be indexed again if this changes.
  final String stamp;

  final List<IndexedTodo> todos;

  int get openCount => todos.where((todo) => !todo.closed).length;
}

/// The to-dos in each note, so open to-dos can be counted per folder
/// and listed without opening every note.
///
/// This is stored locally and never synced: each device builds its own.
class TodoIndex extends ChangeNotifier {
  new({required this.file});

  static final log = Logger('TodoIndex');

  /// The index file, outside of the (synced) notes folder.
  final File file;

  /// The to-dos of each note, keyed by the note's file path.
  final _notes = <String, IndexedNoteTodos>{};

  var _loaded = false;
  Timer? _saveTimer;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString()) as Map;
      for (final MapEntry(:key, :value) in json.entries) {
        _notes[key as String] = IndexedNoteTodos.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
      }
      notifyListeners();
    } catch (e) {
      log.warning('Failed to load the to-do index, starting over: $e');
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
      log.warning('Failed to save the to-do index: $e');
    }
  }

  Iterable<String> get filePaths => _notes.keys;

  /// All indexed notes, including those without to-dos.
  Map<String, IndexedNoteTodos> get notes => UnmodifiableMapView(_notes);

  IndexedNoteTodos? noteOf(String filePath) => _notes[filePath];

  void setNote(String filePath, IndexedNoteTodos note) {
    final old = _notes[filePath];
    if (old?.stamp == note.stamp && listEquals(old?.todos, note.todos)) {
      return;
    }
    _notes[filePath] = note;
    _scheduleSave();
    notifyListeners();
  }

  void remove(String filePath) {
    if (_notes.remove(filePath) == null) return;
    _scheduleSave();
    notifyListeners();
  }

  /// The number of open to-dos in the note at [filePath].
  int openCountOf(String filePath) => _notes[filePath]?.openCount ?? 0;

  /// The number of open to-dos in all notes in [folderPath]
  /// and its subfolders.
  int openCountInFolder(String folderPath) {
    final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    var count = 0;
    for (final MapEntry(key: filePath, value: note) in _notes.entries) {
      if (filePath.startsWith(prefix)) count += note.openCount;
    }
    return count;
  }

  /// The number of open to-dos in all notes.
  int get openCount =>
      _notes.values.fold(0, (count, note) => count + note.openCount);

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
