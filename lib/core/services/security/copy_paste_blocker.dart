import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wrap question content in this widget to disable text selection,
/// copy, context menus, and paste — prevents pasting questions into AI tools.
class CopyPasteBlocker extends StatelessWidget {
  final Widget child;

  const CopyPasteBlocker({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: GestureDetector(
        onSecondaryTap: () {
          // Block right-click context menu on desktop/web
        },
        onLongPress: () {
          // Clear clipboard on any attempt to copy/paste
          try {
            Clipboard.setData(const ClipboardData(text: ''));
          } catch (_) {}
        },
        child: ExcludeSemantics(
          child: child,
        ),
      ),
    );
  }
}
