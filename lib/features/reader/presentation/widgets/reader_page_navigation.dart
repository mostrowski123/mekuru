import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:mekuru/features/reader/presentation/reader_interaction_logic.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Screen-reader access to a reader's page area, shared by the EPUB and
/// manga readers. Activating it shows or hides the controls, and Next page /
/// Previous page actions turn pages. Without it a reader could only be
/// driven by tapping a screen position, which TalkBack and VoiceOver can't
/// aim: their activation lands at a fixed point instead.
class ReaderPageSemantics extends StatelessWidget {
  const ReaderPageSemantics({
    super.key,
    required this.label,
    required this.onIntent,
    required this.child,
  });

  /// Where the reader is, e.g. "Page 3 of 120".
  final String label;
  final ValueChanged<ReaderNavigationIntent> onIntent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: label,
      onTap: () => onIntent(ReaderNavigationIntent.toggleControls),
      onTapHint: l10n.readerShowHideControls,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.readerNextPage): () =>
            onIntent(ReaderNavigationIntent.goForward),
        CustomSemanticsAction(label: l10n.readerPreviousPage): () =>
            onIntent(ReaderNavigationIntent.goBackward),
      },
      child: child,
    );
  }
}
