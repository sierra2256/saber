import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
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

  static const _fractions = [0.1, 0.25, 0.5];
  static const _dotDiameters = [4.0, 8.0, 13.0];

  static double presetSize(Pen pen, double fraction) {
    final steps = (pen.sizeStepsBetweenMinAndMax * fraction).round();
    return pen.sizeMin + steps * pen.sizeStep;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Flex(
      direction: axis,
      mainAxisSize: .min,
      children: [
        for (int i = 0; i < _fractions.length; ++i)
          Builder(
            builder: (context) {
              final size = presetSize(pen, _fractions[i]);
              final selected = pen.options.size == size;
              return _QuickOption(
                tooltip: '${t.editor.penOptions.size}: ${size.round()}',
                selected: selected,
                onTap: () {
                  pen.options.size = size;
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

class _QuickOption extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
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
