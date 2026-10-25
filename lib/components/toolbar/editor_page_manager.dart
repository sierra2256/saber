import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/i18n/strings.g.dart';

/// A sidebar with page thumbnails that slides in from the side of the editor.
///
/// Tap a thumbnail to jump to that page, long-press and drag to reorder,
/// or use a page's menu to add, duplicate or delete pages.
class EditorPageManager extends StatefulWidget {
  const new({
    super.key,
    required this.coreInfo,
    required this.getCurrentPageIndex,
    required this.redrawAndSave,
    required this.insertPageAfter,
    required this.duplicatePage,
    required this.clearPage,
    required this.deletePage,
    required this.transformationController,
    required this.onClose,
  });

  final EditorCoreInfo coreInfo;
  final int Function() getCurrentPageIndex;
  final VoidCallback redrawAndSave;

  final void Function(int) insertPageAfter;
  final void Function(int) duplicatePage;
  final void Function(int) clearPage;
  final void Function(int) deletePage;

  final TransformationController transformationController;
  final VoidCallback onClose;

  static const width = 176.0;
  static const _thumbnailWidth = 112.0;

  @override
  State<EditorPageManager> createState() => _EditorPageManagerState();
}

class _EditorPageManagerState extends State<EditorPageManager> {
  late int currentPageIndex = widget.getCurrentPageIndex();

  @override
  void initState() {
    super.initState();
    widget.transformationController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(EditorPageManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformationController != widget.transformationController) {
      oldWidget.transformationController.removeListener(_onTransformChanged);
      widget.transformationController.addListener(_onTransformChanged);
    }
  }

  /// Highlights the page that is currently on screen.
  void _onTransformChanged() {
    final pageIndex = widget.getCurrentPageIndex();
    if (pageIndex == currentPageIndex) return;
    setState(() => currentPageIndex = pageIndex);
  }

  void scrollToPage(int pageIndex) => CanvasGestureDetector.scrollToPage(
    pageIndex: pageIndex,
    pages: widget.coreInfo.pages,
    screenWidth: MediaQuery.sizeOf(context).width,
    transformationController: widget.transformationController,
  );

  void reorderPage(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    widget.coreInfo.pages.insert(
      newIndex,
      widget.coreInfo.pages.removeAt(oldIndex),
    );

    // reassign pageIndex of pages' strokes and images
    for (int i = 0; i < widget.coreInfo.pages.length; i++) {
      final page = widget.coreInfo.pages[i];
      page.updatePageIndex(i);
    }

    widget.redrawAndSave();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final readOnly = widget.coreInfo.readOnly;
    final pages = widget.coreInfo.pages;

    return Material(
      color: colorScheme.surfaceContainer,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: .antiAlias,
      child: SizedBox(
        width: EditorPageManager.width,
        child: Column(
          children: [
            Padding(
              padding: const .only(left: 16, right: 4, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.editor.pages,
                      style: TextTheme.of(context).titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const .only(bottom: 8),
                itemCount: pages.length,
                onReorderItem: readOnly ? (_, _) {} : reorderPage,
                itemBuilder: (context, pageIndex) {
                  final isEmptyLastPage =
                      pageIndex == pages.length - 1 && pages[pageIndex].isEmpty;
                  final thumbnail = _PageThumbnail(
                    key: ValueKey(pages[pageIndex]),
                    coreInfo: widget.coreInfo,
                    pageIndex: pageIndex,
                    selected: pageIndex == currentPageIndex,
                    onTap: () => scrollToPage(pageIndex),
                    menu: readOnly
                        ? null
                        : _PageMenu(
                            pageIndex: pageIndex,
                            totalPages: pages.length,
                            isEmptyLastPage: isEmptyLastPage,
                            onAction: (action) => setState(() {
                              switch (action) {
                                case .insertAfter:
                                  widget.insertPageAfter(pageIndex);
                                  scrollToPage(pageIndex + 1);
                                case .duplicate:
                                  widget.duplicatePage(pageIndex);
                                  scrollToPage(pageIndex + 1);
                                case .clear:
                                  widget.clearPage(pageIndex);
                                  scrollToPage(pageIndex);
                                case .delete:
                                  widget.deletePage(pageIndex);
                                  scrollToPage(pageIndex);
                              }
                            }),
                          ),
                  );
                  if (readOnly) return thumbnail;
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(pages[pageIndex]),
                    index: pageIndex,
                    child: thumbnail,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.transformationController.removeListener(_onTransformChanged);
    super.dispose();
  }
}

class _PageThumbnail extends StatelessWidget {
  const new({
    super.key,
    required this.coreInfo,
    required this.pageIndex,
    required this.selected,
    required this.onTap,
    required this.menu,
  });

  final EditorCoreInfo coreInfo;
  final int pageIndex;
  final bool selected;
  final VoidCallback onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final page = coreInfo.pages[pageIndex];
    return Padding(
      padding: const .symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: .min,
        children: [
          Semantics(
            button: true,
            selected: selected,
            label: '${pageIndex + 1} / ${coreInfo.pages.length}',
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: EditorPageManager._thumbnailWidth,
                height:
                    EditorPageManager._thumbnailWidth *
                    page.size.height /
                    page.size.width,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                clipBehavior: .antiAlias,
                child: IgnorePointer(
                  child: FittedBox(
                    child: CanvasPreview(
                      pageIndex: pageIndex,
                      height: null,
                      coreInfo: coreInfo,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: .center,
            children: [
              Text(
                '${pageIndex + 1}',
                style: TextStyle(
                  color: selected ? colorScheme.primary : null,
                  fontWeight: selected ? .bold : null,
                ),
              ),
              ?menu,
            ],
          ),
        ],
      ),
    );
  }
}

enum _PageAction { insertAfter, duplicate, clear, delete }

class _PageMenu extends StatelessWidget {
  const new({
    required this.pageIndex,
    required this.totalPages,
    required this.isEmptyLastPage,
    required this.onAction,
  });

  final int pageIndex;
  final int totalPages;
  final bool isEmptyLastPage;
  final ValueChanged<_PageAction> onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PageAction>(
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: onAction,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: .insertAfter,
          child: ListTile(
            leading: const AdaptiveIcon(
              icon: Icons.insert_page_break,
              cupertinoIcon: CupertinoIcons.add,
            ),
            title: Text(t.editor.menu.insertPage),
          ),
        ),
        PopupMenuItem(
          value: .duplicate,
          child: ListTile(
            leading: const AdaptiveIcon(
              icon: Icons.content_copy,
              cupertinoIcon: CupertinoIcons.doc_on_clipboard,
            ),
            title: Text(t.editor.menu.duplicatePage),
          ),
        ),
        PopupMenuItem(
          value: .clear,
          enabled: !isEmptyLastPage,
          child: ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: Text(
              t.editor.menu.clearPage(
                page: pageIndex + 1,
                totalPages: totalPages,
              ),
            ),
          ),
        ),
        PopupMenuItem(
          value: .delete,
          enabled: !isEmptyLastPage,
          child: ListTile(
            leading: const AdaptiveIcon(
              icon: Icons.delete,
              cupertinoIcon: CupertinoIcons.delete,
            ),
            title: Text(t.editor.menu.deletePage),
          ),
        ),
      ],
    );
  }
}
