import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/features/reader/data/models/highlight_color.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:share_plus/share_plus.dart';

/// Floating action bar shown when text is selected or a sentence is long-pressed.
///
/// [mode] controls which buttons are shown:
/// - [SelectionBarMode.highlight]: color dots for creating a highlight (text selection)
/// - [SelectionBarMode.sentence]: Copy, Highlight, Share buttons (sentence selection)
enum SelectionBarMode { highlight, sentence }

class SelectionActionBar extends StatelessWidget {
  final Rect anchorRect;
  final String selectedText;
  final SelectionBarMode mode;
  final bool isLocked;
  final void Function(HighlightColor color)? onHighlight;
  final VoidCallback? onLockedTap;
  final VoidCallback? onDismiss;

  const SelectionActionBar({
    super.key,
    required this.anchorRect,
    required this.selectedText,
    required this.mode,
    this.isLocked = false,
    this.onHighlight,
    this.onLockedTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const barHeight = 48.0;
    const barPadding = 8.0;

    // Position the bar above the selection if there's room, otherwise below
    final above = anchorRect.top - barHeight - barPadding;
    final below = anchorRect.bottom + barPadding;
    final top = above >= MediaQuery.of(context).padding.top ? above : below;

    // Center horizontally on the selection, clamped to screen bounds
    final barWidth = mode == SelectionBarMode.sentence ? 200.0 : 220.0;
    var left = anchorRect.center.dx - barWidth / 2;
    left = left.clamp(8.0, screenSize.width - barWidth - 8.0);

    return Positioned(
      top: top,
      left: left,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: mode == SelectionBarMode.sentence
              ? _buildSentenceBar(context)
              : _buildHighlightBar(context),
        ),
      ),
    );
  }

  Widget _buildHighlightBar(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in HighlightColor.values)
          _ColorDot(
            color: isLocked ? Colors.grey : color.color,
            onTap: () {
              if (isLocked) {
                onLockedTap?.call();
                return;
              }
              onHighlight?.call(color);
            },
          ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onDismiss,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildSentenceBar(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy,
          label: context.l10n.commonCopy,
          onTap: () {
            Clipboard.setData(ClipboardData(text: selectedText));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.readerCopiedToClipboard),
                duration: Duration(seconds: 1),
              ),
            );
            onDismiss?.call();
          },
        ),
        _ActionButton(
          icon: Icons.highlight,
          label: context.l10n.readerHighlightSelectionTooltip,
          onTap: () {
            if (isLocked) {
              onLockedTap?.call();
              return;
            }
            onHighlight?.call(HighlightColor.yellow);
          },
        ),
        _ActionButton(
          icon: Icons.share,
          label: context.l10n.commonShare,
          onTap: () {
            SharePlus.instance.share(ShareParams(text: selectedText));
            onDismiss?.call();
          },
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _ColorDot({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 1,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
