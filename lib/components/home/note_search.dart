import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/handwriting/handwriting_index.dart';
import 'package:saber/data/handwriting/handwriting_indexer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

/// A search button for the home page app bars.
class NoteSearchButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t.handwriting.search.search,
      icon: const Icon(Icons.search),
      onPressed: () => showSearch(context: context, delegate: NoteSearch()),
    );
  }
}

/// Searches note names and, if handwriting recognition is turned on,
/// the handwriting in notes (see [HandwritingIndex]).
class NoteSearch extends SearchDelegate<void> {
  new({this._indexer, Future<List<String>> Function()? getAllNotes})
    : _getAllNotes = getAllNotes ?? FileManager.getAllFiles,
      super(searchFieldLabel: t.handwriting.search.hint);

  final HandwritingIndexer? _indexer;
  HandwritingIndexer? get indexer => _indexer ?? HandwritingIndexer.instance;

  final Future<List<String>> Function() _getAllNotes;
  late final _allNotes = _getAllNotes();

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => const BackButton();

  @override
  Widget buildResults(BuildContext context) => _buildResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildResults(context);

  Widget _buildResults(BuildContext context) {
    final indexer = stows.handwritingRecognition.value ? this.indexer : null;
    return Column(
      children: [
        if (indexer != null)
          ValueListenableBuilder(
            valueListenable: indexer.isIndexing,
            builder: (context, isIndexing, _) => isIndexing
                ? Tooltip(
                    message: t.handwriting.search.indexing,
                    child: const LinearProgressIndicator(),
                  )
                : const SizedBox.shrink(),
          ),
        Expanded(
          child: FutureBuilder(
            future: _allNotes,
            builder: (context, snapshot) {
              final needle = query.trim().toLowerCase();
              if (needle.isEmpty) return const SizedBox.shrink();

              final nameMatches = [
                for (final filePath in snapshot.data ?? const <String>[])
                  if (!Editor.isReservedPath(filePath) &&
                      p.basename(filePath).toLowerCase().contains(needle))
                    filePath,
              ];
              final handwritingMatches =
                  indexer?.index.search(needle) ?? const [];

              if (nameMatches.isEmpty && handwritingMatches.isEmpty) {
                return Center(child: Text(t.handwriting.search.noResults));
              }

              return ListView(
                children: [
                  for (final filePath in nameMatches)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(p.basename(filePath)),
                      subtitle: Text(p.dirname(filePath)),
                      onTap: () => _open(context, filePath),
                    ),
                  for (final result in handwritingMatches)
                    ListTile(
                      leading: const Icon(Icons.draw_outlined),
                      title: Text(p.basename(result.filePath)),
                      subtitle: Text(
                        '${t.handwriting.search.page(page: result.pageIndex + 1)}'
                        ' · ${result.snippet}',
                        maxLines: 2,
                        overflow: .ellipsis,
                      ),
                      onTap: () =>
                          _open(context, result.filePath, result.pageIndex),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, String filePath, [int? pageIndex]) {
    close(context, null);
    context.push(RoutePaths.editFilePath(filePath, pageIndex: pageIndex));
  }
}
