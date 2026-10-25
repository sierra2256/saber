import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/export_bar.dart';
import 'package:saber/components/toolbar/favorite_pens.dart';
import 'package:saber/components/toolbar/floating_panel.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/quick_options.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';

class Toolbar extends StatefulWidget {
  const new({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.quillFocus,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.undo,
    required this.isUndoPossible,
    required this.redo,
    required this.isRedoPossible,
    required this.toggleFingerDrawing,
    required this.pickPhoto,
    required this.paste,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
    this.leading,
    required this.insertPage,
    required this.showPages,
    required this.showNoteSettings,
    this.rename,
  });

  final bool readOnly;

  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;

  final ValueNotifier<QuillStruct?> quillFocus;
  final bool textEditing;
  final VoidCallback toggleTextEditing;

  final VoidCallback undo;
  final bool isUndoPossible;
  final VoidCallback redo;
  final bool isRedoPossible;

  final VoidCallback toggleFingerDrawing;

  final VoidCallback pickPhoto;

  final VoidCallback paste;

  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  /// Shown at the start of the toolbar, e.g. the back button and note title.
  final Widget? leading;

  final VoidCallback insertPage;
  final VoidCallback showPages;
  final VoidCallback showNoteSettings;

  /// Shown in the overflow menu when the title doesn't fit in the toolbar.
  final VoidCallback? rename;

  @override
  State<Toolbar> createState() => _ToolbarState();

  static const _buttonPaddingHorizontal = EdgeInsets.symmetric(horizontal: 2);
  static const _buttonPaddingVertical = EdgeInsets.symmetric(vertical: 6);
}

class _ToolbarState extends State<Toolbar> {
  ValueNotifier<bool> showExportOptions = ValueNotifier(false);
  ValueNotifier<bool> showColorOptions = ValueNotifier(false);
  ValueNotifier<ToolOptions> toolOptionsType = ValueNotifier(ToolOptions.hide);

  @override
  void initState() {
    _assignKeybindings();

    DynamicMaterialApp.addFullscreenListener(_setState);

    super.initState();
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlF;
  Keybinding? _ctrlE;
  Keybinding? _ctrlC;
  Keybinding? _ctrlShiftS;
  Keybinding? _f11;
  Keybinding? _ctrlV;
  void _assignKeybindings() {
    _ctrlF = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyF),
    ], inclusive: true);
    _ctrlE = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyE),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _ctrlShiftS = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyS),
    ], inclusive: true);
    _f11 = Keybinding([KeyCode.from(LogicalKeyboardKey.f11)], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);

    Keybinder.bind(_ctrlF!, widget.toggleFingerDrawing);
    Keybinder.bind(_ctrlE!, toggleEraser);
    Keybinder.bind(_ctrlC!, toggleColorOptions);
    Keybinder.bind(_ctrlShiftS!, toggleExportBar);
    Keybinder.bind(_f11!, toggleFullscreen);
    Keybinder.bind(_ctrlV!, widget.paste);
  }

  void _removeKeybindings() {
    if (_ctrlF != null) Keybinder.remove(_ctrlF!);
    if (_ctrlE != null) Keybinder.remove(_ctrlE!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_ctrlShiftS != null) Keybinder.remove(_ctrlShiftS!);
    if (_f11 != null) Keybinder.remove(_f11!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
  }

  void toggleEraser() {
    toolOptionsType.value = .hide;
    widget.setTool(Eraser()); // this toggles eraser
  }

  void toggleColorOptions() {
    showColorOptions.value = !showColorOptions.value;
  }

  void toggleExportBar() {
    showExportOptions.value = !showExportOptions.value;
  }

  void toggleFullscreen() async {
    DynamicMaterialApp.setFullscreen(
      !DynamicMaterialApp.isFullscreen,
      updateSystem: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;

    final isToolbarVertical =
        stows.editorToolbarAlignment.value == AxisDirection.left ||
        stows.editorToolbarAlignment.value == AxisDirection.right;

    final toolbarAxis = isToolbarVertical ? Axis.vertical : Axis.horizontal;

    final buttonPadding = isToolbarVertical
        ? Toolbar._buttonPaddingVertical
        : Toolbar._buttonPaddingHorizontal;

    final currentColor = switch (widget.currentTool) {
      final Pen pen => pen.color,
      final Select select => select.getDominantStrokeColor(),
      _ => null,
    };

    if (widget.currentTool == Select.currentSelect) {
      // Enable selection bar only when selection is done
      toolOptionsType.value = Select.currentSelect.doneSelecting
          ? .select
          : .hide;
    }

    final bars = <Widget>[
      ValueListenableBuilder(
        valueListenable: showExportOptions,
        builder: (context, showExportOptions, child) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: !showExportOptions,
            child: child!,
          );
        },
        child: FloatingPanel(
          child: ExportBar(
            axis: toolbarAxis,
            toggleExportBar: toggleExportBar,
            exportAsSba: widget.exportAsSba,
            exportAsPdf: widget.exportAsPdf,
            exportAsPng: widget.exportAsPng,
          ),
        ),
      ),
      ValueListenableBuilder(
        valueListenable: toolOptionsType,
        builder: (context, toolOptionsType, _) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: toolOptionsType == .hide,
            child: FloatingPanel(
              child: switch (toolOptionsType) {
                .hide => const SizedBox.square(
                  dimension: SizePicker.smallLength,
                ),
                .pen => PenModal(
                  getTool: () => Pen.currentPen,
                  setTool: widget.setTool,
                ),
                .highlighter => PenModal(
                  getTool: () => Highlighter.currentHighlighter,
                  setTool: widget.setTool,
                ),
                .pencil => PenModal(
                  getTool: () => Pencil.currentPencil,
                  setTool: widget.setTool,
                ),
                .select => SelectionBar(
                  duplicateSelection: widget.duplicateSelection,
                  deleteSelection: widget.deleteSelection,
                ),
              },
            ),
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: showColorOptions,
        builder: (context, showColorOptions, child) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: !showColorOptions,
            child: child!,
          );
        },
        child: FloatingPanel(
          child: ColorBar(
            axis: toolbarAxis,
            setColor: widget.setColor,
            currentColor: currentColor,
            invert: invert,
          ),
        ),
      ),
      ValueListenableBuilder(
        valueListenable: widget.quillFocus,
        builder: (context, quill, _) {
          final baseButtonStyle =
              IconButtonTheme.of(context).style ?? const ButtonStyle();

          final iconTheme = QuillIconTheme(
            iconButtonUnselectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                foregroundColor: WidgetStateProperty.all(colorScheme.primary),
              ),
            ),
            iconButtonSelectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(colorScheme.primary),
                foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
              ),
            ),
          );
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: false,
            collapsed: !widget.textEditing || quill == null,
            child: quill != null
                ? FloatingPanel(
                    child: QuillSimpleToolbar(
                      controller: quill.controller,
                      config: QuillSimpleToolbarConfig(
                        axis: isToolbarVertical
                            ? Axis.vertical
                            : Axis.horizontal,
                        buttonOptions: QuillSimpleToolbarButtonOptions(
                          base: QuillToolbarBaseButtonOptions(
                            iconTheme: iconTheme,
                          ),
                        ),
                        // scrollable on Android and iOS
                        multiRowsDisplay:
                            !Platform.isAndroid && !Platform.isIOS,
                        showUndo: false,
                        showRedo: false,
                        showFontSize: false,
                        showFontFamily: false,
                        showClearFormat: false,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
      FloatingPanel(
        child: Padding(
          padding: const .symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            direction: toolbarAxis,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                _ToolbarDivider(axis: toolbarAxis),
              ],
              _ToolbarGroup(
                axis: toolbarAxis,
                children: [
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.undo,
                    enabled: !widget.readOnly && widget.isUndoPossible,
                    onPressed: widget.undo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.undo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_left,
                    ),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.redo,
                    enabled: !widget.readOnly && widget.isRedoPossible,
                    onPressed: widget.redo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.redo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_right,
                    ),
                  ),
                ],
              ),
              _ToolbarDivider(axis: toolbarAxis),
              _ToolbarGroup(
                axis: toolbarAxis,
                children: [
                  ToolbarIconButton(
                    tooltip: Pen.currentPen.name,
                    selected: widget.currentTool == Pen.currentPen,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (widget.currentTool == Pen.currentPen) {
                        if (toolOptionsType.value == .pen) {
                          toolOptionsType.value = .hide;
                        } else {
                          toolOptionsType.value = .pen;
                        }
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(Pen.currentPen);
                      }
                    },
                    padding: buttonPadding,
                    child: UniIcon(Pen.currentPen.icon, size: 16),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.pens.pencil,
                    selected: widget.currentTool == Pencil.currentPencil,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (widget.currentTool == Pencil.currentPencil) {
                        if (toolOptionsType.value == .pencil) {
                          toolOptionsType.value = .hide;
                        } else {
                          toolOptionsType.value = .pencil;
                        }
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(Pencil.currentPencil);
                      }
                    },
                    padding: buttonPadding,
                    child: const FaIcon(Pencil.pencilIcon, size: 16),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.pens.highlighter,
                    selected:
                        widget.currentTool == Highlighter.currentHighlighter,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      if (widget.currentTool ==
                          Highlighter.currentHighlighter) {
                        if (toolOptionsType.value == .highlighter) {
                          toolOptionsType.value = .hide;
                        } else {
                          toolOptionsType.value = .highlighter;
                        }
                      } else {
                        toolOptionsType.value = .hide;
                        widget.setTool(Highlighter.currentHighlighter);
                      }
                    },
                    padding: buttonPadding,
                    child: const FaIcon(Highlighter.highlighterIcon, size: 16),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.toggleEraser,
                    selected: widget.currentTool is Eraser,
                    enabled: !widget.readOnly,
                    onPressed: toggleEraser,
                    padding: buttonPadding,
                    child: const FaIcon(FontAwesomeIcons.eraser, size: 16),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.select,
                    selected: widget.currentTool is Select,
                    enabled: !widget.readOnly,
                    onPressed: () {
                      toolOptionsType.value = .hide;
                      widget.setTool(Select.currentSelect);
                    },
                    padding: buttonPadding,
                    child: Icon(
                      CupertinoIcons.lasso,
                      shadows: !widget.readOnly
                          ? [
                              BoxShadow(
                                color: widget.currentTool is Select
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                                blurRadius: 0.1,
                                spreadRadius: 10,
                                blurStyle: BlurStyle.solid,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.text,
                    selected: widget.textEditing,
                    enabled: !widget.readOnly,
                    onPressed: widget.toggleTextEditing,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.text_fields,
                      cupertinoIcon: CupertinoIcons.text_cursor,
                    ),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.photo,
                    enabled: !widget.readOnly,
                    onPressed: widget.pickPhoto,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.photo,
                      cupertinoIcon: CupertinoIcons.photo,
                    ),
                  ),
                ],
              ),
              if (currentColor != null && !widget.readOnly) ...[
                _ToolbarDivider(axis: toolbarAxis),
                _ToolbarGroup(
                  axis: toolbarAxis,
                  children: [
                    QuickColors(
                      axis: toolbarAxis,
                      currentColor: currentColor,
                      setColor: widget.setColor,
                      invert: invert,
                    ),
                    ValueListenableBuilder(
                      valueListenable: showColorOptions,
                      builder: (context, showColorOptions, child) {
                        return ToolbarIconButton(
                          tooltip: t.editor.toolbar.toggleColors,
                          selected: showColorOptions,
                          enabled: !widget.readOnly,
                          onPressed: toggleColorOptions,
                          padding: buttonPadding,
                          child: child!,
                        );
                      },
                      child: const Icon(Icons.palette_outlined),
                    ),
                    if (widget.currentTool case final Pen pen)
                      QuickSizes(
                        axis: toolbarAxis,
                        pen: pen,
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ],
              if (!widget.readOnly &&
                  (widget.currentTool is Pen ||
                      stows.favoritePens.value.isNotEmpty)) ...[
                _ToolbarDivider(axis: toolbarAxis),
                FavoritePens(
                  axis: toolbarAxis,
                  currentTool: widget.currentTool,
                  setTool: (tool) {
                    toolOptionsType.value = .hide;
                    widget.setTool(tool);
                  },
                  invert: invert,
                  padding: buttonPadding,
                ),
              ],
              if (widget.currentTool is Eraser && !widget.readOnly) ...[
                _ToolbarDivider(axis: toolbarAxis),
                QuickEraserOptions(
                  axis: toolbarAxis,
                  onChanged: () => setState(() {}),
                ),
              ],
              _ToolbarDivider(axis: toolbarAxis),
              _ToolbarGroup(
                axis: toolbarAxis,
                children: [
                  ToolbarIconButton(
                    tooltip: t.editor.pages,
                    onPressed: widget.showPages,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.grid_view,
                      cupertinoIcon: CupertinoIcons.rectangle_grid_2x2,
                    ),
                  ),
                  _buildMoreMenu(buttonPadding),
                ],
              ),
            ],
          ),
        ),
      ),
    ];

    return Flex(
      mainAxisSize: .min,
      direction: isToolbarVertical ? Axis.horizontal : Axis.vertical,
      textDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.left => .rtl,
        AxisDirection.right => .ltr,
        _ => null,
      },
      verticalDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.down => VerticalDirection.down,
        AxisDirection.up => VerticalDirection.up,
        _ => VerticalDirection.down,
      },
      children: bars,
    );
  }

  /// Less frequently used actions, kept out of the toolbar to save space.
  Widget _buildMoreMenu(EdgeInsets buttonPadding) {
    return ValueListenableBuilder(
      valueListenable: stows.editorFingerDrawing,
      builder: (context, fingerDrawing, _) => MenuAnchor(
        menuChildren: [
          if (widget.rename != null)
            MenuItemButton(
              leadingIcon: const Icon(Icons.edit),
              onPressed: widget.readOnly ? null : widget.rename,
              child: Text(t.home.renameNote.renameNote),
            ),
          MenuItemButton(
            leadingIcon: const AdaptiveIcon(
              icon: Icons.insert_page_break,
              cupertinoIcon: CupertinoIcons.add,
            ),
            onPressed: widget.readOnly ? null : widget.insertPage,
            child: Text(t.editor.menu.insertPage),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Symbols.stylus_laser_pointer),
            trailingIcon: widget.currentTool == LaserPointer.currentLaserPointer
                ? const Icon(Icons.check)
                : null,
            // even in read-only mode
            onPressed: () {
              toolOptionsType.value = .hide;
              widget.setTool(LaserPointer.currentLaserPointer);
            },
            child: Text(t.editor.pens.laserPointer),
          ),
          if (!stows.hideFingerDrawingToggle.value)
            MenuItemButton(
              leadingIcon: const Icon(CupertinoIcons.hand_draw),
              trailingIcon: fingerDrawing ? const Icon(Icons.check) : null,
              onPressed: widget.readOnly ? null : widget.toggleFingerDrawing,
              child: Text(t.editor.toolbar.toggleFingerDrawing),
            ),
          MenuItemButton(
            leadingIcon: AdaptiveIcon(
              icon: DynamicMaterialApp.isFullscreen
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              cupertinoIcon: DynamicMaterialApp.isFullscreen
                  ? CupertinoIcons.fullscreen_exit
                  : CupertinoIcons.fullscreen,
            ),
            onPressed: widget.readOnly ? null : toggleFullscreen,
            child: Text(t.editor.toolbar.fullscreen),
          ),
          MenuItemButton(
            leadingIcon: const AdaptiveIcon(
              icon: Icons.share,
              cupertinoIcon: CupertinoIcons.share,
            ),
            onPressed: widget.readOnly ? null : toggleExportBar,
            child: Text(t.editor.toolbar.export),
          ),
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.tune),
            onPressed: widget.showNoteSettings,
            child: Text(t.home.tabs.settings),
          ),
        ],
        builder: (context, controller, _) => ToolbarIconButton(
          tooltip: MaterialLocalizations.of(context).showMenuTooltip,
          selected: controller.isOpen,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          padding: buttonPadding,
          child: const AdaptiveIcon(
            icon: Icons.more_vert,
            cupertinoIcon: CupertinoIcons.ellipsis_vertical,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_setState);
    DynamicMaterialApp.setFullscreen(false, updateSystem: true);

    _removeKeybindings();
    super.dispose();
  }
}

/// A group of related toolbar buttons, kept together when the toolbar wraps.
class _ToolbarGroup extends StatelessWidget {
  const new({required this.axis, required this.children});

  final Axis axis;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: axis,
      mainAxisSize: .min,
      crossAxisAlignment: .center,
      children: children,
    );
  }
}

/// A thin line separating toolbar groups.
class _ToolbarDivider extends StatelessWidget {
  const new({required this.axis});

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final color = ColorScheme.of(context).outlineVariant;
    return Padding(
      padding: axis == Axis.horizontal
          ? const .symmetric(horizontal: 4)
          : const .symmetric(vertical: 4),
      child: axis == Axis.horizontal
          ? SizedBox(
              height: 24,
              child: VerticalDivider(width: 1, thickness: 1, color: color),
            )
          : SizedBox(
              width: 24,
              child: Divider(height: 1, thickness: 1, color: color),
            ),
    );
  }
}

enum ToolOptions { hide, pen, highlighter, pencil, select }
