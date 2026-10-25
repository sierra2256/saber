import 'package:flutter/material.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/quick_options.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/favorite_pen.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// The user's favorite pens (see [FavoritePen]) shown in the toolbar.
///
/// Tap a favorite to switch to it, long-press to replace or remove it.
/// The add button saves the current pen as a new favorite.
class FavoritePens extends StatelessWidget {
  const new({
    super.key,
    required this.axis,
    required this.currentTool,
    required this.setTool,
    required this.invert,
    required this.padding,
  });

  final Axis axis;
  final Tool currentTool;
  final ValueChanged<Tool> setTool;
  final bool invert;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: stows.favoritePens,
      builder: (context, favorites, _) {
        final currentPen = currentTool is Pen ? currentTool as Pen : null;
        final canAdd =
            currentPen != null &&
            favorites.length < FavoritePen.maxCount &&
            !favorites.any((favorite) => favorite.matches(currentPen));
        return Flex(
          direction: axis,
          mainAxisSize: .min,
          children: [
            for (int i = 0; i < favorites.length; ++i)
              _FavoritePenButton(
                favorite: favorites[i],
                selected:
                    currentPen != null && favorites[i].matches(currentPen),
                invert: invert,
                onTap: () => setTool(favorites[i].apply()),
                onLongPress: () => _showOptions(context, i, currentPen),
              ),
            if (canAdd)
              ToolbarIconButton(
                tooltip: t.editor.favoritePens.add,
                onPressed: () => _add(currentPen),
                padding: padding,
                child: const Icon(Icons.star_border),
              ),
          ],
        );
      },
    );
  }

  static void _add(Pen pen) {
    stows.favoritePens.value = [
      ...stows.favoritePens.value,
      FavoritePen.fromPen(pen),
    ];
  }

  static void _replace(int index, FavoritePen favorite) {
    stows.favoritePens.value = List.of(stows.favoritePens.value)
      ..[index] = favorite;
  }

  static void _remove(int index) {
    stows.favoritePens.value = List.of(stows.favoritePens.value)
      ..removeAt(index);
  }

  Future<void> _showOptions(
    BuildContext context,
    int index,
    Pen? currentPen,
  ) async {
    final action = await showDialog<_FavoriteAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t.editor.favoritePens.title),
        children: [
          if (currentPen != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, _FavoriteAction.replace),
              child: Text(t.editor.favoritePens.replace),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _FavoriteAction.remove),
            child: Text(t.editor.favoritePens.remove),
          ),
        ],
      ),
    );
    switch (action) {
      case .replace:
        _replace(index, FavoritePen.fromPen(currentPen!));
      case .remove:
        _remove(index);
      case null:
        break;
    }
  }
}

enum _FavoriteAction { replace, remove }

class _FavoritePenButton extends StatelessWidget {
  const new({
    required this.favorite,
    required this.selected,
    required this.invert,
    required this.onTap,
    required this.onLongPress,
  });

  final FavoritePen favorite;
  final bool selected;
  final bool invert;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = favorite.color.withAlpha(255).withInversion(invert);
    final dotSize = (favorite.size / 4).clamp(3.0, 8.0);
    return QuickOption(
      tooltip:
          '${ColorBar.findColorName(favorite.color.withAlpha(255))}, '
          '${favorite.size.round()}',
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox.square(
        dimension: 20,
        child: Stack(
          alignment: .center,
          clipBehavior: .none,
          children: [
            UniIcon(favorite.icon, size: 14, color: color),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(color: color, shape: .circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
