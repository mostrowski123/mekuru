// ignore_for_file: discarded_futures
import 'package:flutter/material.dart';

/// Shows a non-dismissible spinner dialog with [message] next to it, and
/// returns the function that closes it.
///
/// Progress is indeterminate — the callers run their work through compute or
/// a worker isolate, which has no channel to stream progress through. The
/// close function works after [context] is gone (a library tile can be
/// rebuilt while its export runs), so the spinner never outlives the work.
VoidCallback showBlockingProgressDialog(BuildContext context, String message) {
  final navigator = Navigator.of(context, rootNavigator: true);
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
  return () => navigator.pop();
}
