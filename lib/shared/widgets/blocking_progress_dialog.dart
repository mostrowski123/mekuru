import 'package:flutter/material.dart';

/// Shows a non-dismissible spinner dialog with [message] next to it.
///
/// Progress is indeterminate — the callers run their work through compute or
/// a worker isolate, which has no channel to stream progress through. Dismiss
/// with `Navigator.of(context).pop()` when the work completes.
void showBlockingProgressDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}
