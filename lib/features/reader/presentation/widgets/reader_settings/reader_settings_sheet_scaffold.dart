import 'package:flutter/material.dart';

/// Opens a reader quick-settings bottom sheet with the sizing and scroll
/// behavior shared by the EPUB and manga readers. Always scroll-controlled so
/// the inner [DraggableScrollableSheet] can expand past half height.
Future<void> showReaderSettingsSheet({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: builder,
  );
}

/// Scaffold for the reader quick-settings sheets: a draggable, scrollable
/// half-height sheet with a title row and an optional jump to the full
/// settings screen.
class ReaderSettingsSheetScaffold extends StatelessWidget {
  const ReaderSettingsSheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.onOpenAllSettings,
    this.allSettingsTooltip,
  });

  final String title;
  final List<Widget> children;

  /// When set, renders a trailing button in the title row that jumps to the
  /// full reading settings screen.
  final VoidCallback? onOpenAllSettings;
  final String? allSettingsTooltip;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          controller: scrollController,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (onOpenAllSettings != null)
                  IconButton(
                    tooltip: allSettingsTooltip,
                    icon: const Icon(Icons.tune),
                    onPressed: onOpenAllSettings,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}
