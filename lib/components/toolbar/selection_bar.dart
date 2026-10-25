import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;
  final VoidCallback? saveSelectionAsElement;
  final VoidCallback? convertSelectionToText;
  final VoidCallback? copySelectionToOtherSide;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
    this.saveSelectionAsElement,
    this.convertSelectionToText,
    this.copySelectionToOtherSide,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      mainAxisAlignment: .center,
      children: [
        IconButton(
          onPressed: duplicateSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.duplicate,
          icon: const AdaptiveIcon(
            icon: Icons.content_copy,
            cupertinoIcon: CupertinoIcons.doc_on_clipboard,
          ),
        ),
        IconButton(
          onPressed: deleteSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.delete,
          icon: const AdaptiveIcon(
            icon: Icons.delete,
            cupertinoIcon: CupertinoIcons.delete,
          ),
        ),
        IconButton(
          onPressed: saveSelectionAsElement,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.saveAsElement,
          icon: const Icon(Icons.bookmark_add_outlined),
        ),
        if (copySelectionToOtherSide != null)
          IconButton(
            onPressed: copySelectionToOtherSide,
            style: TextButton.styleFrom(
              foregroundColor: ColorScheme.of(context).secondary,
              backgroundColor: Colors.transparent,
              shape: const CircleBorder(),
            ),
            tooltip: t.editor.splitView.copyToOtherSide,
            icon: const Icon(Icons.move_up),
          ),
        if (convertSelectionToText != null)
          IconButton(
            onPressed: convertSelectionToText,
            style: TextButton.styleFrom(
              foregroundColor: ColorScheme.of(context).secondary,
              backgroundColor: Colors.transparent,
              shape: const CircleBorder(),
            ),
            tooltip: t.handwriting.convert.convertToText,
            icon: const Icon(Icons.text_snippet_outlined),
          ),
      ],
    );
  }
}
