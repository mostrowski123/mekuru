import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/free_books/data/models/aozora_work.dart';
import 'package:mekuru/features/free_books/data/services/aozora_catalog.dart';
import 'package:mekuru/features/free_books/presentation/providers/free_books_providers.dart';
import 'package:mekuru/features/free_books/presentation/widgets/free_book_actions.dart';
import 'package:mekuru/features/free_books/presentation/widgets/free_books_search_field.dart';
import 'package:mekuru/features/stats/presentation/stats_formatting.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Aozora Bunko: search, filters and sort over the bundled catalog.
class AozoraTab extends ConsumerWidget {
  const AozoraTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final results = ref.watch(aozoraResultsProvider);
    return Column(
      children: [
        FreeBooksSearchField(
          initialText: ref.read(aozoraQueryProvider).text,
          hintText: l10n.freeBooksSearchHint,
          onChanged: (text) => ref
              .read(aozoraQueryProvider.notifier)
              .update((query) => query.copyWith(text: text)),
        ),
        const _FilterBar(),
        Expanded(
          child: results.when(
            data: (works) => Column(
              children: [
                _CountRow(count: works.length),
                Expanded(
                  child: works.isEmpty
                      ? const FreeBooksNoResults()
                      : ListView.builder(
                          itemCount: works.length,
                          itemBuilder: (context, i) =>
                              _WorkTile(work: works[i]),
                        ),
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.freeBooksCatalogFailed)),
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(aozoraQueryProvider);
    final notifier = ref.read(aozoraQueryProvider.notifier);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _SheetChip(
            icon: Icons.sort,
            label: _sortLabel(l10n, query.sort),
            selected: false,
            onTap: () => showSettingsOptionPickerSheet<AozoraSort>(
              context: context,
              title: l10n.librarySortBy,
              values: AozoraSort.values,
              selected: query.sort,
              labelOf: (sort) => _sortLabel(l10n, sort),
              onSelected: (sort) =>
                  notifier.update((q) => q.copyWith(sort: sort)),
            ),
          ),
          _SheetChip(
            label: l10n.freeBooksLevel,
            selected: query.levels.isNotEmpty,
            onTap: () => _showMultiSelectSheet<int>(
              context: context,
              title: l10n.freeBooksLevel,
              note: l10n.freeBooksLevelEstimateNote,
              values: const [5, 4, 3, 2, 1, 0],
              labelOf: (level) => _levelLabel(l10n, level),
              selectedOf: (q) => q.levels,
              apply: (q, levels) => q.copyWith(levels: levels),
            ),
          ),
          _SheetChip(
            label: l10n.freeBooksLength,
            selected: query.lengths.isNotEmpty,
            onTap: () => _showMultiSelectSheet<AozoraLength>(
              context: context,
              title: l10n.freeBooksLength,
              note: ref.read(readingPaceProvider).personal
                  ? l10n.freeBooksLengthNotePersonal
                  : l10n.freeBooksLengthNoteDefault,
              values: AozoraLength.values,
              labelOf: (length) => _lengthLabel(l10n, length),
              selectedOf: (q) => q.lengths,
              apply: (q, lengths) => q.copyWith(lengths: lengths),
            ),
          ),
          _SheetChip(
            label: l10n.freeBooksGenre,
            selected: query.genres.isNotEmpty,
            onTap: () => _showMultiSelectSheet<AozoraGenre>(
              context: context,
              title: l10n.freeBooksGenre,
              values: AozoraGenre.values,
              labelOf: (genre) => _genreLabel(l10n, genre),
              selectedOf: (q) => q.genres,
              apply: (q, genres) => q.copyWith(genres: genres),
            ),
          ),
          _SheetChip(
            label: l10n.freeBooksSpelling,
            selected: query.spellings.isNotEmpty,
            onTap: () => _showMultiSelectSheet<AozoraSpelling>(
              context: context,
              title: l10n.freeBooksSpelling,
              note: l10n.freeBooksSpellingNote,
              values: AozoraSpelling.values,
              labelOf: (spelling) => _spellingLabel(l10n, spelling),
              selectedOf: (q) => q.spellings,
              apply: (q, spellings) => q.copyWith(spellings: spellings),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(l10n.freeBooksHideInLibrary),
              selected: query.hideInLibrary,
              onSelected: (hide) =>
                  notifier.update((q) => q.copyWith(hideInLibrary: hide)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chip that opens a picker sheet.
class _SheetChip extends StatelessWidget {
  const _SheetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      avatar: icon == null ? null : Icon(icon, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(label), const Icon(Icons.arrow_drop_down, size: 18)],
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    ),
  );
}

Future<void> _showMultiSelectSheet<T>({
  required BuildContext context,
  required String title,
  String? note,
  required List<T> values,
  required String Function(T value) labelOf,
  required Set<T> Function(AozoraQuery query) selectedOf,
  required AozoraQuery Function(AozoraQuery query, Set<T> selected) apply,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheetContext) => Consumer(
    builder: (context, ref, _) {
      final theme = Theme.of(context);
      final query = ref.watch(aozoraQueryProvider);
      final selected = selectedOf(query);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            for (final value in values)
              CheckboxListTile(
                value: selected.contains(value),
                title: Text(labelOf(value)),
                onChanged: (on) {
                  AppHaptics.light();
                  final next = {...selected};
                  on == true ? next.add(value) : next.remove(value);
                  ref.read(aozoraQueryProvider.notifier).state = apply(
                    query,
                    next,
                  );
                },
              ),
          ],
        ),
      );
    },
  ),
);

class _CountRow extends ConsumerWidget {
  const _CountRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(aozoraQueryProvider);
    final notifier = ref.read(aozoraQueryProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.freeBooksResultCount(count: count),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (query.hasFilters)
            TextButton(
              onPressed: () => notifier.state = query.cleared(),
              child: Text(l10n.freeBooksClearFilters),
            )
          else
            TextButton(
              onPressed: () => notifier.state = AozoraQuery.easyPicks.copyWith(
                text: query.text,
              ),
              child: Text(l10n.freeBooksEasyPicks),
            ),
        ],
      ),
    );
  }
}

class _WorkTile extends ConsumerWidget {
  const _WorkTile({required this.work});

  final AozoraWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pace = ref.watch(readingPaceProvider).charsPerMinute;
    final downloading = ref.watch(
      freeBookDownloadProvider.select(
        (map) => map.containsKey(aozoraDownloadKey(work)),
      ),
    );
    final inLibrary = ref.watch(
      libraryBooksByKeyProvider.select(
        (byKey) => libraryCopy(byKey, work.displayTitle, 'epub') != null,
      ),
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      isThreeLine: true,
      title: Text(
        work.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              work.titleReading,
              work.authorReading,
            ].where((s) => s.isNotEmpty).join(' · '),
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            [
              work.author,
              _levelLabel(l10n, work.jlptEstimate),
              _readingTime(l10n, work, pace),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: downloading
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : inLibrary
          ? Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
              semanticLabel: l10n.freeBooksInLibrary,
            )
          : null,
      onTap: () {
        AppHaptics.light();
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _WorkSheet(work: work),
        );
      },
    );
  }
}

/// Details of one Aozora work, with Download or Read.
class _WorkSheet extends ConsumerWidget {
  const _WorkSheet({required this.work});

  final AozoraWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pace = ref.watch(readingPaceProvider);
    final progress = ref.watch(
      freeBookDownloadProvider.select((map) => map[aozoraDownloadKey(work)]),
    );
    final copy = ref.watch(
      libraryBooksByKeyProvider.select(
        (byKey) => libraryCopy(byKey, work.displayTitle, 'epub'),
      ),
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final time = _readingTime(l10n, work, pace.charsPerMinute);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(work.displayTitle, style: theme.textTheme.headlineSmall),
            if (work.titleReading.isNotEmpty)
              Text(work.titleReading, style: muted),
            const SizedBox(height: 12),
            Text(work.author, style: theme.textTheme.titleMedium),
            if (work.authorReading.isNotEmpty)
              Text(work.authorReading, style: muted),
            const SizedBox(height: 16),
            _InfoRow(
              label: l10n.freeBooksLength,
              value: pace.personal
                  ? l10n.freeBooksLengthAtYourPace(
                      time: time,
                      characters: work.charCount,
                    )
                  : l10n.freeBooksLengthAtLearnerPace(
                      time: time,
                      characters: work.charCount,
                    ),
            ),
            _InfoRow(
              label: l10n.freeBooksEstimatedLevel,
              value: _levelLabel(l10n, work.jlptEstimate),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.freeBooksLevelEstimateNote, style: muted),
            ),
            _InfoRow(
              label: l10n.freeBooksSpelling,
              value: _spellingLabel(l10n, work.spelling),
            ),
            _InfoRow(
              label: l10n.freeBooksGenre,
              value: _genreLabel(l10n, work.genre),
            ),
            const SizedBox(height: 16),
            FreeBookActions(
              viewLabel: l10n.freeBooksViewOnAozora,
              viewUrl: work.cardUrl,
              copy: copy,
              progress: progress,
              onDownload: () => ref
                  .read(freeBookDownloadProvider.notifier)
                  .downloadAozora(work),
            ),
            const SizedBox(height: 12),
            Text(l10n.freeBooksAozoraAttribution, style: muted),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// "~N3", or "Beyond N1" for level 0.
String _levelLabel(AppLocalizations l10n, int level) => level == 0
    ? l10n.freeBooksLevelBeyondN1
    : l10n.freeBooksLevelEstimate(level: level);

/// Reading time at [pace], never under a minute ("0m" would read as empty).
String _readingTime(AppLocalizations l10n, AozoraWork work, double pace) =>
    formatDuration(
      l10n,
      math.max(
        Duration.millisecondsPerMinute,
        (readingMinutes(work, pace) * Duration.millisecondsPerMinute).round(),
      ),
    );

String _sortLabel(AppLocalizations l10n, AozoraSort sort) => switch (sort) {
  AozoraSort.popular => l10n.freeBooksSortPopular,
  AozoraSort.easiest => l10n.freeBooksSortEasiest,
  AozoraSort.hardest => l10n.freeBooksSortHardest,
  AozoraSort.shortest => l10n.freeBooksSortShortest,
  AozoraSort.longest => l10n.freeBooksSortLongest,
  AozoraSort.title => l10n.freeBooksSortByTitle,
  AozoraSort.author => l10n.freeBooksSortByAuthor,
};

String _lengthLabel(AppLocalizations l10n, AozoraLength length) =>
    switch (length) {
      AozoraLength.under10Minutes => l10n.freeBooksLengthUnder10Minutes,
      AozoraLength.under30Minutes => l10n.freeBooksLengthUnder30Minutes,
      AozoraLength.under1Hour => l10n.freeBooksLengthUnder1Hour,
      AozoraLength.under3Hours => l10n.freeBooksLengthUnder3Hours,
      AozoraLength.longer => l10n.freeBooksLengthLonger,
    };

String _genreLabel(AppLocalizations l10n, AozoraGenre genre) => switch (genre) {
  AozoraGenre.fiction => l10n.freeBooksGenreFiction,
  AozoraGenre.children => l10n.freeBooksGenreChildren,
  AozoraGenre.poetry => l10n.freeBooksGenrePoetry,
  AozoraGenre.plays => l10n.freeBooksGenrePlays,
  AozoraGenre.essays => l10n.freeBooksGenreEssays,
  AozoraGenre.diaries => l10n.freeBooksGenreDiaries,
  AozoraGenre.history => l10n.freeBooksGenreHistory,
  AozoraGenre.philosophy => l10n.freeBooksGenrePhilosophy,
  AozoraGenre.nonfiction => l10n.freeBooksGenreNonfiction,
  AozoraGenre.other => l10n.freeBooksGenreOther,
};

String _spellingLabel(AppLocalizations l10n, AozoraSpelling spelling) =>
    switch (spelling) {
      AozoraSpelling.modern => l10n.freeBooksSpellingModern,
      AozoraSpelling.oldKana => l10n.freeBooksSpellingOldKana,
      AozoraSpelling.oldKanji => l10n.freeBooksSpellingOldKanji,
      AozoraSpelling.other => l10n.freeBooksSpellingOther,
    };
