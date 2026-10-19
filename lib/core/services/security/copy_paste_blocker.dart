import 'package:flutter/material.dart';

/// Wrap question content in this widget to disable text selection,
/// copy, and paste — prevents pasting questions into AI tools.
class CopyPasteBlocker extends StatelessWidget {
  final Widget child;

  const CopyPasteBlocker({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(child: child);
  }
}
