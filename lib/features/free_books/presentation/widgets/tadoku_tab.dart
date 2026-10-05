import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/free_books/data/models/tadoku_book.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/free_books/presentation/widgets/free_book_actions.dart';
import 'package:mekuru/features/free_books/presentation/widgets/free_books_search_field.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/download_status.dart';

/// Graded readers by NPO Tadoku Supporters: level chips, search and a grid
/// of covers.
class TadokuTab extends ConsumerWidget {
  const TadokuTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final results = ref.watch(tadokuResultsProvider);
    return Column(
      children: [
        FreeBooksSearchField(
          initialText: ref.read(tadokuQueryProvider).text,
          hintText: l10n.freeBooksTadokuSearchHint,
          onChanged: (text) => ref
              .read(tadokuQueryProvider.notifier)
              .update((query) => query.copyWith(text: text)),
        ),
        const _LevelBar(),
        Expanded(
          child: results.when(
            data: (books) => books.isEmpty
                ? const FreeBooksNoResults()
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.56,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: books.length,
                    itemBuilder: (context, i) => _ReaderTile(book: books[i]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.freeBooksCatalogFailed)),
          ),
        ),
      ],
    );
  }
}

class _LevelBar extends ConsumerWidget {
  const _LevelBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(tadokuQueryProvider);
    final notifier = ref.read(tadokuQueryProvider.notifier);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final level in const [-1, 0, 1, 2, 3, 4, 5])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(_levelLabel(l10n, level)),
                selected: query.levels.contains(level),
                onSelected: (on) => notifier.update(
                  (q) => q.copyWith(
                    levels: on
                        ? {...q.levels, level}
                        : ({...q.levels}..remove(level)),
                  ),
                ),
              ),
            ),
          FilterChip(
            label: Text(l10n.freeBooksHideInLibrary),
            selected: query.hideInLibrary,
            onSelected: (hide) =>
                notifier.update((q) => q.copyWith(hideInLibrary: hide)),
          ),
        ],
      ),
    );
  }
}

class _ReaderTile extends ConsumerWidget {
  const _ReaderTile({required this.book});

  final TadokuBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final key = tadokuDownloadKey(book);
    final downloading = ref.watch(
      freeBookDownloadProvider.select((map) => map.containsKey(key)),
    );
    final inLibrary = ref.watch(
      freeBooksInLibraryProvider.select((books) => books.containsKey(key)),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        AppHaptics.light();
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _ReaderSheet(book: book),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Cover(book: book),
                Positioned(
                  left: 4,
                  top: 4,
                  child: _Badge(_levelLabel(l10n, book.level)),
                ),
                if (!book.hasText)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: _Badge(l10n.freeBooksTadokuPagesOnly),
                  ),
                if (downloading)
                  // Only the spinner follows the progress.
                  Center(
                    child: Consumer(
                      builder: (_, ref, _) {
                        final progress = ref.watch(
                          freeBookDownloadProvider.select((map) => map[key]),
                        );
                        return CircularProgressIndicator(
                          value: progress != null && progress > 0
                              ? progress
                              : null,
                        );
                      },
                    ),
                  )
                else if (inLibrary)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      semanticLabel: l10n.freeBooksInLibrary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A book's cover, with a plain placeholder until (or unless) it loads.
class _Cover extends ConsumerWidget {
  const _Cover({required this.book});

  final TadokuBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.menu_book_outlined, color: colors.onSurfaceVariant),
    );
    final file = ref.watch(tadokuCoverProvider(book.coverUrl)).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: file == null
          ? placeholder
          : Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

/// Details of one graded reader, with Download or Read, and its credit.
class _ReaderSheet extends ConsumerWidget {
  const _ReaderSheet({required this.book});

  final TadokuBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final key = tadokuDownloadKey(book);
    final progress = ref.watch(
      freeBookDownloadProvider.select((map) => map[key]),
    );
    final copy = ref.watch(
      freeBooksInLibraryProvider.select((books) => books[key]),
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: AspectRatio(
                    aspectRatio: 0.7,
                    child: _Cover(book: book),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title, style: theme.textTheme.titleLarge),
                      Text(book.titleReading, style: muted),
                      const SizedBox(height: 8),
                      Text(
                        _levelLabel(l10n, book.level),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        [
                          l10n.serverBrowsePageCount(count: book.pageCount),
                          if (book.charCount > 0)
                            l10n.freeBooksTadokuCharacters(
                              characters: book.charCount,
                            ),
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!book.hasText) ...[
              Text(
                l10n.freeBooksTadokuPagesOnlyNote,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            if (book.hasAudio) ...[
              Text(l10n.freeBooksTadokuAudio, style: muted),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            FreeBookActions(
              viewLabel: l10n.freeBooksViewOnTadoku,
              viewUrl: book.pageUrl,
              copy: copy,
              progress: progress,
              onDownload: () => ref
                  .read(freeBookDownloadProvider.notifier)
                  .downloadTadoku(book),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.freeBooksTadokuAttribution(publisher: tadokuPublisher),
              style: muted,
            ),
            const SizedBox(height: 4),
            DownloadAttributionText(
              linkText: l10n.freeBooksTadokuLicense,
              url: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
            ),
          ],
        ),
      ),
    );
  }
}

/// The JLPT level tadoku.org states for each of its levels (only 1 to 5
/// state one).
const _jlptByLevel = {1: 'N5', 2: 'N4', 3: 'N3', 4: 'N3–N2', 5: 'N2–N1'};

/// "Start", "L0", or "L2 · N4".
String _levelLabel(AppLocalizations l10n, int level) {
  if (level < 0) return l10n.freeBooksTadokuLevelStart;
  final jlpt = _jlptByLevel[level];
  return jlpt == null
      ? l10n.freeBooksTadokuLevel(level: level)
      : l10n.freeBooksTadokuLevelJlpt(level: level, jlpt: jlpt);
}
