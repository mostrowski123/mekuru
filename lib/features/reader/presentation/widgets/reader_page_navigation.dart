import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
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

/// What [key] does in a reader. The arrow and page keys and the space bar,
/// which keyboards and Bluetooth page turners send, always turn pages; the
/// volume buttons follow [volumeKeys].
ReaderNavigationIntent readerKeyIntent(
  LogicalKeyboardKey key, {
  required ReaderDirection direction,
  required VolumeKeyPageTurn volumeKeys,
  bool shift = false,
}) {
  const forward = ReaderNavigationIntent.goForward;
  const backward = ReaderNavigationIntent.goBackward;
  if (key == LogicalKeyboardKey.audioVolumeDown ||
      key == LogicalKeyboardKey.audioVolumeUp) {
    final down = key == LogicalKeyboardKey.audioVolumeDown;
    return switch (volumeKeys) {
      VolumeKeyPageTurn.off => ReaderNavigationIntent.none,
      VolumeKeyPageTurn.downNext => down ? forward : backward,
      VolumeKeyPageTurn.upNext => down ? backward : forward,
    };
  }
  // Left and right follow the page: a right-to-left book's next page is on
  // the left, as with the tap zones.
  final rtl = direction == ReaderDirection.rtl;
  if (key == LogicalKeyboardKey.arrowLeft) return rtl ? forward : backward;
  if (key == LogicalKeyboardKey.arrowRight) return rtl ? backward : forward;
  if (key == LogicalKeyboardKey.space) return shift ? backward : forward;
  if (key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.arrowDown) {
    return forward;
  }
  if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.arrowUp) {
    return backward;
  }
  return ReaderNavigationIntent.none;
}

/// The page-turn keys under the names the EPUB page's own key events use.
/// The page forwards them when it has keyboard focus itself, which on iOS
/// it takes after a tap into the text.
const domPageTurnKeys = {
  'ArrowLeft': LogicalKeyboardKey.arrowLeft,
  'ArrowRight': LogicalKeyboardKey.arrowRight,
  'ArrowUp': LogicalKeyboardKey.arrowUp,
  'ArrowDown': LogicalKeyboardKey.arrowDown,
  'PageUp': LogicalKeyboardKey.pageUp,
  'PageDown': LogicalKeyboardKey.pageDown,
  ' ': LogicalKeyboardKey.space,
};

/// Turns pages from keys while a reader is the focused route (see
/// [readerKeyIntent]).
class ReaderKeyNavigation extends StatelessWidget {
  const ReaderKeyNavigation({
    super.key,
    required this.direction,
    required this.volumeKeys,
    required this.onIntent,
    required this.child,
  });

  final ReaderDirection direction;
  final VolumeKeyPageTurn volumeKeys;
  final ValueChanged<ReaderNavigationIntent> onIntent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // iOS doesn't let apps take over the volume buttons.
    final volume = defaultTargetPlatform == TargetPlatform.android
        ? volumeKeys
        : VolumeKeyPageTurn.off;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final intent = readerKeyIntent(
          event.logicalKey,
          direction: direction,
          volumeKeys: volume,
          shift: HardwareKeyboard.instance.isShiftPressed,
        );
        if (intent == ReaderNavigationIntent.none) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) onIntent(intent);
        // Swallow repeats and releases as well: an unhandled repeat of a
        // held volume button would still change the volume.
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
