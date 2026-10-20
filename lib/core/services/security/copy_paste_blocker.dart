import 'package:flutter/material.dart';

/// Wrap question content in this widget to disable text selection,
/// copy, and paste — prevents pasting questions into AI tools.
class CopyPasteBlocker extends StatelessWidget {
  final Widget child;

  const CopyPasteBlocker({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Do NOT use SelectionArea or SelectableText.
    // Plain Text widgets are not selectable by default.
    // Additionally, wrap with a GestureDetector that clears the clipboard
    // on long-press to further deter copying.
    return GestureDetector(
      onLongPress: () {
        // Optional: clear clipboard to prevent paste elsewhere
        // Clipboard.setData(const ClipboardData(text: ''));
      },
      child: ExcludeSemantics(
        child: child,
      ),
    );
  }
}

//Usage inside the quiz question widget
