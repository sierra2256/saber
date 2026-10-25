import 'package:flutter/material.dart';

/// A rounded panel that floats over the page, so the page stays visible
/// around the toolbar (like GoodNotes).
class FloatingPanel extends StatelessWidget {
  const new({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Center(
      child: Padding(
        padding: const .all(6),
        child: Material(
          color: colorScheme.surfaceContainerLow,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: const .all(.circular(16)),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: .antiAlias,
          child: child,
        ),
      ),
    );
  }
}
