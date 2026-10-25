import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/i18n/strings.g.dart';

/// A tool that can be picked in the [PenRadialMenu].
class PenMenuTool {
  const new({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onSelected,
  });

  /// An [IconData] or [FaIconData].
  final Object icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onSelected;
}

/// A round menu that pops up where the stylus is
/// (by pressing the stylus button twice, like in Samsung Notes),
/// to quickly change the pen type, color and thickness.
///
/// Tools are around the top, colors around the bottom,
/// and thickness presets are in the middle.
/// Tapping outside of the menu closes it.
class PenRadialMenu extends StatelessWidget {
  const new({
    super.key,
    required this.center,
    required this.tools,
    required this.colors,
    required this.currentColor,
    required this.onColorSelected,
    required this.sizes,
    required this.currentSize,
    required this.onSizeSelected,
    required this.invert,
    required this.onClose,
  });

  /// Where the menu is centered, in the coordinates of this widget.
  /// The menu is moved to stay on screen.
  final Offset center;

  final List<PenMenuTool> tools;

  final List<Color> colors;
  final Color? currentColor;
  final ValueChanged<Color>? onColorSelected;

  /// The thickness presets, or empty if the tool doesn't have any.
  final List<double> sizes;
  final double? currentSize;
  final ValueChanged<double> onSizeSelected;

  final bool invert;
  final VoidCallback onClose;

  static const radius = 130.0;

  /// The key of the round menu itself.
  static const circleKey = ValueKey('PenRadialMenu.circle');
  static const _itemRadius = 92.0;
  static const _itemSize = 40.0;

  /// The angle (in radians) left empty on each side
  /// between the tools at the top and the colors at the bottom.
  static const _gap = 0.5;
  static const _sizeDots = [6.0, 11.0, 17.0];

  /// The positions of [count] items spread evenly along an arc
  /// from [startAngle] to [endAngle] (in radians, clockwise from the right).
  static List<Offset> arc(int count, double startAngle, double endAngle) => [
    for (int i = 0; i < count; i++)
      Offset.fromDirection(
        count == 1
            ? (startAngle + endAngle) / 2
            : startAngle + (endAngle - startAngle) * i / (count - 1),
        _itemRadius,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // keep the menu on screen
        final menuCenter = Offset(
          center.dx.clamp(radius, max(radius, constraints.maxWidth - radius)),
          center.dy.clamp(radius, max(radius, constraints.maxHeight - radius)),
        );

        final toolPositions = arc(tools.length, pi + _gap, 2 * pi - _gap);
        final colorPositions = arc(colors.length, pi - _gap, _gap);
        const sizeSpacing = _itemSize + 6;

        Widget positioned(Offset offset, Widget child) => Positioned(
          left: radius + offset.dx - _itemSize / 2,
          top: radius + offset.dy - _itemSize / 2,
          width: _itemSize,
          height: _itemSize,
          child: child,
        );

        return Stack(
          children: [
            // tapping (or drawing) outside of the menu closes it
            Positioned.fill(
              child: Listener(
                behavior: .opaque,
                onPointerDown: (_) => onClose(),
              ),
            ),
            Positioned(
              left: menuCenter.dx - radius,
              top: menuCenter.dy - radius,
              width: radius * 2,
              height: radius * 2,
              child: Semantics(
                label: t.editor.penMenu.title,
                child: GestureDetector(
                  // don't close when tapping between the buttons
                  onTap: () {},
                  child: Material(
                    key: circleKey,
                    color: colorScheme.surfaceContainerHigh,
                    elevation: 6,
                    shape: CircleBorder(
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    child: Stack(
                      children: [
                        for (int i = 0; i < tools.length; i++)
                          positioned(
                            toolPositions[i],
                            _MenuButton(
                              tooltip: tools[i].tooltip,
                              selected: tools[i].selected,
                              onTap: tools[i].onSelected,
                              child: UniIcon(
                                tools[i].icon,
                                size: 18,
                                color: tools[i].selected
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        for (int i = 0; i < colors.length; i++)
                          positioned(
                            colorPositions[i],
                            _MenuButton(
                              tooltip: ColorBar.findColorName(colors[i]),
                              selected:
                                  currentColor?.withAlpha(255).toARGB32() ==
                                  colors[i].toARGB32(),
                              onTap: onColorSelected == null
                                  ? null
                                  : () => onColorSelected!(colors[i]),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colors[i].withInversion(invert),
                                  shape: .circle,
                                  border: Border.all(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        for (int i = 0; i < sizes.length; i++)
                          positioned(
                            Offset(
                              (i - (sizes.length - 1) / 2) * sizeSpacing,
                              0,
                            ),
                            _MenuButton(
                              tooltip:
                                  '${t.editor.penOptions.size}: '
                                  '${sizes[i].round()}',
                              selected: currentSize == sizes[i],
                              onTap: () => onSizeSelected(sizes[i]),
                              child: Container(
                                width: _sizeDots[min(i, _sizeDots.length - 1)],
                                height: _sizeDots[min(i, _sizeDots.length - 1)],
                                decoration: BoxDecoration(
                                  color: currentSize == sizes[i]
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurfaceVariant,
                                  shape: .circle,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MenuButton extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? colorScheme.primary : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: .antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }
}
