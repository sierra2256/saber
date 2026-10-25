import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/editor/editor_pane.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

/// Two notes side by side, e.g. a note next to an imported PDF.
///
/// Strokes can be copied from one side to the other
/// (see [EditorState.copySelectionToOtherSide]).
class SplitEditorPage extends StatefulWidget {
  const new({
    super.key,
    required this.leftPath,
    required this.rightPath,
    this.rightPdfPath,
  });

  final String leftPath;
  final String rightPath;

  /// A PDF to import into the right note, see [Editor.pdfPath].
  final String? rightPdfPath;

  /// Asks which note to show next to [editor]'s note,
  /// then replaces the editor with a split view.
  static Future<void> open(BuildContext context, EditorState editor) async {
    final choice = await showDialog<NoteChoice>(
      context: context,
      builder: (context) =>
          _NotePickerDialog(exclude: editor.coreInfo.filePath),
    );
    if (choice == null || !context.mounted) return;

    // make sure the note is saved before it's opened again
    await editor.flushSave();
    if (!context.mounted) return;

    final leftPath = editor.coreInfo.filePath;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => SplitEditorPage(
          leftPath: leftPath,
          rightPath: choice.path,
          rightPdfPath: choice.pdfPath,
        ),
      ),
    );
  }

  /// The split view around [context], if any.
  static SplitEditorPageState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SplitViewScope>()?.state;

  @override
  State<SplitEditorPage> createState() => SplitEditorPageState();
}

/// A note to open in the split view, chosen by the user.
typedef NoteChoice = ({String path, String? pdfPath});

class SplitEditorPageState extends State<SplitEditorPage> {
  final _editorKeys = [GlobalKey<EditorState>(), GlobalKey<EditorState>()];

  /// Which pane was used last, so keyboard shortcuts go to it.
  final activePane = ValueNotifier(0);
  late final _isActive = [
    for (int i = 0; i < 2; i++) _PaneActive(activePane, i),
  ];

  /// The fraction of the width taken by the left pane.
  var ratio = 0.5;
  static const minRatio = 0.25, maxRatio = 0.75;
  static const dividerWidth = 12.0;

  /// The editor on the other side from [editor].
  EditorState? otherEditor(EditorState editor) {
    final left = _editorKeys[0].currentState;
    final right = _editorKeys[1].currentState;
    if (identical(editor, left)) return right;
    if (identical(editor, right)) return left;
    return null;
  }

  /// Closes the split view, keeping only [keep]'s note open.
  Future<void> close({required EditorState keep}) async {
    await Future.wait([
      for (final key in _editorKeys)
        if (key.currentState case final editor?) editor.flushSave(),
    ]);
    if (!mounted) return;

    final path = keep.coreInfo.filePath;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: RouteSettings(name: RoutePaths.editFilePath(path)),
        builder: (context) => Editor(path: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return _SplitViewScope(
      state: this,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth - dividerWidth;
            final leftWidth = available * ratio;
            return Row(
              children: [
                _pane(context, 0, Size(leftWidth, constraints.maxHeight)),
                GestureDetector(
                  behavior: .opaque,
                  onHorizontalDragUpdate: (details) => setState(() {
                    ratio = ((leftWidth + details.delta.dx) / available).clamp(
                      minRatio,
                      maxRatio,
                    );
                  }),
                  onDoubleTap: () => setState(() => ratio = 0.5),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: SizedBox(
                      width: dividerWidth,
                      child: ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Container(
                            width: 4,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.outline,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _pane(
                  context,
                  1,
                  Size(available - leftWidth, constraints.maxHeight),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pane(BuildContext context, int index, Size size) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox.fromSize(
      size: size,
      child: Listener(
        // the pane that was touched last receives keyboard shortcuts
        onPointerDown: (_) => activePane.value = index,
        behavior: .translucent,
        child: EditorPane(
          isActive: _isActive[index],
          // The editor lays out pages using the screen size,
          // so tell it the size of its pane instead.
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: size),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Editor(
                    key: _editorKeys[index],
                    path: index == 0 ? widget.leftPath : widget.rightPath,
                    pdfPath: index == 1 ? widget.rightPdfPath : null,
                  ),
                ),
                // a thin line above the active pane
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: ValueListenableBuilder(
                      valueListenable: _isActive[index],
                      builder: (context, isActive, _) => Container(
                        height: 3,
                        color: isActive
                            ? colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final isActive in _isActive) {
      isActive.dispose();
    }
    activePane.dispose();
    super.dispose();
  }
}

class _SplitViewScope extends InheritedWidget {
  const new({required this.state, required super.child});

  final SplitEditorPageState state;

  @override
  bool updateShouldNotify(_SplitViewScope oldWidget) =>
      state != oldWidget.state;
}

/// Whether pane [index] is the active one.
class _PaneActive extends ValueNotifier<bool> {
  new(this.activePane, this.index) : super(activePane.value == index) {
    activePane.addListener(_update);
  }

  final ValueListenable<int> activePane;
  final int index;

  void _update() => value = activePane.value == index;

  @override
  void dispose() {
    activePane.removeListener(_update);
    super.dispose();
  }
}

/// Picks a note (or a PDF to import) to show in the split view.
class _NotePickerDialog extends StatefulWidget {
  const new({required this.exclude});

  /// The note that's already open, which can't be opened twice.
  final String exclude;

  @override
  State<_NotePickerDialog> createState() => _NotePickerDialogState();
}

class _NotePickerDialogState extends State<_NotePickerDialog> {
  late final _notes = FileManager.getAllFiles().then(
    (notes) => [
      for (final note in notes)
        if (note != widget.exclude && !Editor.isReservedPath(note)) note,
    ]..sort((a, b) => p.basename(a).compareTo(p.basename(b))),
  );
  var query = '';

  Future<void> _newNote() async {
    final path = await FileManager.newFilePath('/');
    if (!mounted) return;
    Navigator.pop<NoteChoice>(context, (path: path, pdfPath: null));
  }

  Future<void> _importPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final pdfPath = file?.path;
    if (pdfPath == null) return;
    final name = p.basenameWithoutExtension(file!.name);
    final path = await FileManager.suffixFilePathToMakeItUnique('/$name');
    if (!mounted) return;
    Navigator.pop<NoteChoice>(context, (path: path, pdfPath: pdfPath));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.editor.splitView.chooseNote),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.editor.splitView.search,
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            Expanded(
              child: FutureBuilder(
                future: _notes,
                builder: (context, snapshot) {
                  final needle = query.trim().toLowerCase();
                  final notes = [
                    for (final note in snapshot.data ?? const <String>[])
                      if (p.basename(note).toLowerCase().contains(needle)) note,
                  ];
                  return ListView(
                    children: [
                      for (final note in notes)
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(p.basename(note)),
                          subtitle: Text(p.dirname(note)),
                          onTap: () => Navigator.pop<NoteChoice>(context, (
                            path: note,
                            pdfPath: null,
                          )),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _importPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(t.editor.splitView.importPdf),
        ),
        TextButton.icon(
          onPressed: _newNote,
          icon: const Icon(Icons.note_add_outlined),
          label: Text(t.editor.splitView.newNote),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.common.cancel),
        ),
      ],
    );
  }
}
