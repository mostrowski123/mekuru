import 'package:flutter/material.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Stands where a list or a text that could not be read would be. It says so
/// in the user's language; [error] itself goes to telemetry as [event], once
/// per error, never on screen.
class LoadFailedText extends StatefulWidget {
  const LoadFailedText(
    this.error, {
    super.key,
    required this.event,
    this.reason,
  });

  final Object error;
  final String event;

  /// Why it could not load, already worded, to say instead of that it could
  /// not.
  final String? reason;

  @override
  State<LoadFailedText> createState() => _LoadFailedTextState();
}

class _LoadFailedTextState extends State<LoadFailedText> {
  @override
  void initState() {
    super.initState();
    logFailure(widget.event, widget.error);
  }

  @override
  void didUpdateWidget(LoadFailedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.error, widget.error)) {
      logFailure(widget.event, widget.error);
    }
  }

  @override
  Widget build(BuildContext context) => Text(
    widget.reason ?? context.l10n.commonLoadFailed,
    textAlign: TextAlign.center,
  );
}
