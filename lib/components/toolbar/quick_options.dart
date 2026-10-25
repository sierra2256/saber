import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/i18n/strings.g.dart';

/// A compact row of color swatches shown inline in the toolbar,
/// similar to the quick colors in GoodNotes.
///
/// Uses the pinned and recent colors, falling back to the presets.
class QuickColors extends StatelessWidget {
  const new({
    super.key,
    required this.axis,
    required this.currentColor,
    required this.setColor,
    required this.invert,
  });

  final Axis axis;
  final Color? currentColor;
  final ValueChanged<Color> setColor;
  final bool invert;

  static const count = 3;

  static List<Color> get colors {
    final colors = <Color>[];
    void add(Color color) {
      color = color.withAlpha(255);
      if (colors.length >= count) return;
      if (colors.any((c) => c.toARGB32() == color.toARGB32())) return;
      colors.add(color);
    }

    for (final colorString in stows.pinnedColors.value) {
      add(Color(int.parse(colorString)));
    }
    for (final colorString in stows.recentColorsPositioned.value.reversed) {
      add(Color(int.parse(colorString)));
    }
    for (final namedColor in ColorBar.colorPresets) {
      add(namedColor.color);
    }
    return colors;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final selectedArgb = currentColor?.withAlpha(255).toARGB32();
    return Flex(
      direction: axis,
      mainAxisSize: .min,
      children: [
        for (final color in colors)
          _QuickOption(
            tooltip: ColorBar.findColorName(color),
            selected: selectedArgb == color.toARGB32(),
            onTap: () => setColor(color),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color.withInversion(invert),
                shape: .circle,
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Three stroke width presets (fine, medium, thick) shown inline
/// in the toolbar, similar to GoodNotes.
///
/// Long-press a preset to replace it with the current width.
/// The full size slider is still available by tapping the active pen again.
class QuickSizes extends StatelessWidget {
  const new({
    super.key,
    required this.axis,
    required this.pen,
    required this.onChanged,
  });

  final Axis axis;
  final Pen pen;
  final VoidCallback onChanged;

  static const _dotDiameters = [4.0, 8.0, 13.0];

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final presets = WidthPresets.of(pen);
    return Flex(
      direction: axis,
      mainAxisSize: .min,
      children: [
        for (int i = 0; i < presets.length; ++i)
          Builder(
            builder: (context) {
              final size = presets[i];
              final selected = pen.options.size == size;
              return _QuickOption(
                tooltip: '${t.editor.penOptions.size}: ${size.round()}',
                selected: selected,
                onTap: () {
                  pen.options.size = size;
                  onChanged();
                },
                onLongPress: () {
                  HapticFeedback.selectionClick();
                  WidthPresets.set(pen, i, pen.options.size);
                  onChanged();
                },
                child: SizedBox.square(
                  dimension: 20,
                  child: Center(
                    child: Container(
                      width: _dotDiameters[i],
                      height: _dotDiameters[i],
                      decoration: BoxDecoration(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        shape: .circle,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The stroke width presets used by [QuickSizes],
/// stored per tool type (pen, pencil, highlighter) in [stows.widthPresets].
abstract final class WidthPresets {
  /// The default presets, chosen so that each tool's
  /// default width (see [Pen.defaultOptions]) is the middle preset.
  static const defaults = <String, List<double>>{
    'pen': [2, 5, 10],
    'pencil': [2, 5, 9],
    'highlighter': [30, 50, 80],
  };

  /// The key used to store [pen]'s presets.
  /// The fountain pen, ballpoint pen and shape pen share their presets.
  static String keyOf(Pen pen) => switch (pen) {
    Highlighter() => 'highlighter',
    Pencil() => 'pencil',
    _ => 'pen',
  };

  /// The three presets for [pen], from thinnest to thickest.
  static List<double> of(Pen pen) {
    final key = keyOf(pen);
    final custom = stows.widthPresets.value[key];
    if (custom != null && custom.length == defaults[key]!.length) {
      return custom;
    }
    return defaults[key]!;
  }

  /// Replaces the preset at [index] with [size].
  ///
  /// The presets are kept sorted so that the dots stay
  /// in order from thinnest to thickest.
  static void set(Pen pen, int index, double size) {
    final presets = List.of(of(pen));
    presets[index] = size;
    presets.sort();
    stows.widthPresets.value = {
      ...stows.widthPresets.value,
      keyOf(pen): presets,
    };
  }
}

class _QuickOption extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const .all(2),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const .all(4),
            decoration: BoxDecoration(
              shape: .circle,
              border: Border.all(
                color: selected ? colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
