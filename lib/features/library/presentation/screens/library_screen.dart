// ignore_for_file: discarded_futures, unawaited_futures
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' show max;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_reorderable_grid_view/entities/reorderable_animation_config.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tilt/flutter_tilt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/platform/capabilities.dart';
import 'package:mekuru/core/platform/file_pick.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/free_books/presentation/screens/free_books_screen.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/services/epub_parser.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/widgets/book_cover_image.dart';
import 'package:mekuru/features/library/presentation/widgets/collection_widgets.dart';
import 'package:mekuru/features/library/presentation/widgets/epub_manga_convert_action.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_cache_store.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/library/presentation/widgets/manga_cbz_export_action.dart';
import 'package:mekuru/features/library/presentation/widgets/manga_manifest_picker_sheet.dart';
import 'package:mekuru/features/library/presentation/widgets/continue_reading_card.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/bookmarks_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_progress_overlay.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/features/settings/presentation/widgets/low_ram_mode_prompts.dart';
import 'package:mekuru/features/settings/presentation/widgets/starter_pack_card.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_browse_screen.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/theme/app_theme.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/load_failed_text.dart';
import 'package:mekuru/shared/utils/pending_drag_order.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/widgets/glass_tab_bar.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// How many covers fit across a window [width] points wide. On iOS a wide
/// window (the open iPhone Duo, an iPad) shows more covers at a phone's size;
/// Android keeps three at any width. [chosen] is the Library Columns setting
/// and wins when it is not 0 (Auto).
@visibleForTesting
int libraryGridColumns(double width, [int chosen = 0]) => chosen > 0
    ? chosen
    : defaultTargetPlatform == TargetPlatform.iOS
    ? max(3, width ~/ 180)
    : 3;

/// The cover grid of the library page and of a folder: the same columns,
/// spacing and cover shape in both.
SliverGridDelegate _libraryGridDelegate(BuildContext context, WidgetRef ref) =>
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: libraryGridColumns(
        MediaQuery.sizeOf(context).width,
        ref.watch(libraryColumnsProvider),
      ),
      childAspectRatio: 0.65,
      crossAxisSpacing: 12,
      mainAxisSpacing: 16,
    );

/// The book the user most recently read, or null when none has been opened
/// yet. Derived from the already-watched book list so it stays reactive and
/// independent of the user's chosen sort order.
@visibleForTesting
Book? mostRecentlyReadBook(List<Book> books) {
  Book? recent;
  for (final book in books) {
    final lastReadAt = book.lastReadAt;
    if (lastReadAt == null) continue;
    if (recent == null || lastReadAt.isAfter(recent.lastReadAt!)) {
      recent = book;
    }
  }
  return recent;
}

/// The library page's tiles in order: favorite folders, favorite books, the
/// other folders, the other books. Each group keeps the order it came in
/// (folders by name, books by the selected sort). Every element is a
/// [Collection] or a [Book].
@visibleForTesting
List<Object> libraryGridEntries({
  required List<Collection> collections,
  required List<Book> looseBooks,
}) => [
  ...collections.where((c) => c.isFavorite),
  ...looseBooks.where((b) => b.isFavorite),
  ...collections.where((c) => !c.isFavorite),
  ...looseBooks.where((b) => !b.isFavorite),
];

/// The key of an entry's tile on the library page.
ValueKey<String> _gridTileKey(Object entry) => switch (entry) {
  Collection(:final id) => ValueKey('folder-tile-$id'),
  Book(:final id) => ValueKey('book-tile-$id'),
  _ => throw ArgumentError.value(entry, 'entry'),
};

/// Library screen displaying imported books in a grid view.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  // Multi-select mode over loose books (foldered books are selected inside
  // their folder). Vocabulary-screen pattern.
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_offerLowRamMode());
  }

  /// Once the books have loaded, so the offer never covers a loading library.
  Future<void> _offerLowRamMode() async {
    try {
      await ref.read(booksProvider.future);
    } catch (_) {
      return; // The library shows the error.
    }
    if (mounted) await offerLowRamMode(context, ref);
  }

  void _enterSelectionMode() {
    AppHaptics.light();
    setState(() {
      _isSelectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int bookId) {
    setState(() {
      _selectedIds.contains(bookId)
          ? _selectedIds.remove(bookId)
          : _selectedIds.add(bookId);
    });
  }

  Future<void> _addSelectedToCollection() async {
    await showCollectionPickSheet(context, {..._selectedIds});
    if (mounted) _exitSelectionMode();
  }

  AppBar _buildSelectionAppBar(List<Book> looseBooks) {
    final l10n = context.l10n;
    final allSelected =
        looseBooks.isNotEmpty &&
        looseBooks.every((b) => _selectedIds.contains(b.id));
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.commonClose,
        onPressed: _exitSelectionMode,
      ),
      title: Text(l10n.librarySelectedCount(count: _selectedIds.length)),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected
              ? l10n.libraryDeselectAllTooltip
              : l10n.librarySelectAllTooltip,
          onPressed: () => setState(() {
            allSelected
                ? _selectedIds.clear()
                : _selectedIds.addAll(looseBooks.map((b) => b.id));
          }),
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: l10n.libraryAddToCollectionAction,
          onPressed: _selectedIds.isEmpty ? null : _addSelectedToCollection,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Load persisted sort order on first build.
    ref.read(librarySortProvider.notifier).loadPersistedSort();

    final booksAsync = ref.watch(booksProvider);
    final importState = ref.watch(bookImportProvider);
    final sortOrder = ref.watch(librarySortProvider);

    // Hoisted out of the async branch so the selection app bar can see
    // them. looseBooks is inherently folder-free, which is exactly what
    // select-all must cover.
    final books = booksAsync.value ?? const <Book>[];
    final memberships =
        ref.watch(bookCollectionsProvider).value ?? const <BookCollection>[];
    final inAnyFolder = {for (final m in memberships) m.bookId};
    final looseBooks = [
      for (final b in books)
        if (!inAnyFolder.contains(b.id)) b,
    ];

    return Scaffold(
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(looseBooks)
          : AppBar(
              title: Text(l10n.navLibrary),
              actions: [
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  tooltip: l10n.commonHelp,
                  onPressed: () => _showHelpDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: l10n.librarySelectTooltip,
                  onPressed: _enterSelectionMode,
                ),
                IconButton(
                  icon: const Icon(Icons.sort),
                  tooltip: l10n.librarySortTooltip(
                    label: librarySortLabel(l10n, sortOrder),
                  ),
                  onPressed: () {
                    AppHaptics.light();
                    _showSortPicker(context, ref, sortOrder);
                  },
                ),
                // The way into Settings (and back to its tabs) when the bar
                // has none.
                if (!ref.watch(
                  homeTabsProvider.select((layout) => layout.settingsInBar),
                ))
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: l10n.settingsTitle,
                    onPressed: () => Navigator.of(context).push(
                      namedRoute('settings', (_) => const SettingsScreen()),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _isSelectionMode
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: glassTabBarInset(context)),
              child: FloatingActionButton(
                onPressed: importState.isImporting
                    ? null
                    : () => _showImportChoice(context, ref),
                tooltip: l10n.commonImport,
                child: const Icon(Icons.add),
              ),
            ),
      body: Column(
        children: [
          if (importState.isImporting) ...[
            LinearProgressIndicator(value: importState.progress),
            if (importState.batchTotal != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  l10n.libraryBatchImportProgress(
                    current: importState.batchCurrent ?? 0,
                    total: importState.batchTotal!,
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
          if (importState.error != null)
            _buildBanner(
              context,
              icon: Icons.error_outline,
              color: Theme.of(context).colorScheme.errorContainer,
              textColor: Theme.of(context).colorScheme.onErrorContainer,
              message: importState.error!(l10n),
              onDismiss: () =>
                  ref.read(bookImportProvider.notifier).clearState(),
            ),
          if (importState.successMessage != null)
            _buildBanner(
              context,
              icon: Icons.check_circle_outline,
              color: Colors.green.withValues(alpha: 0.1),
              textColor: Theme.of(context).colorScheme.success,
              message: importState.successMessage!(l10n),
              actionLabel: importState.importedBook != null
                  ? l10n.commonOpenNow
                  : null,
              onAction: importState.importedBook == null
                  ? null
                  : () {
                      final book = importState.importedBook!;
                      ref.read(bookImportProvider.notifier).clearState();
                      openBookReader(Navigator.of(context), book);
                    },
              onDismiss: () =>
                  ref.read(bookImportProvider.notifier).clearState(),
            ),
          Expanded(
            child: booksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: LoadFailedText(err, event: 'library.books_load_failed'),
              ),
              data: (dataBooks) {
                final collections =
                    ref.watch(collectionsProvider).value ??
                    const <Collection>[];
                if (dataBooks.isEmpty && collections.isEmpty) {
                  return _buildEmptyState(context, ref);
                }
                // iOS-folder model: a book living in one or more folders
                // appears inside those folders, not on the root grid.
                return _buildBookGrid(
                  context,
                  ref,
                  collections: collections,
                  // Membership order, so the face shows the user's first
                  // four — dragging inside the folder curates the face.
                  folderBooks: {
                    for (final c in collections)
                      c.id: booksInCollectionOrder(
                        collectionId: c.id,
                        books: dataBooks,
                        memberships: memberships,
                      ),
                  },
                  looseBooks: looseBooks,
                  // The hero considers every book, foldered or not.
                  recent: mostRecentlyReadBook(dataBooks),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color textColor,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onDismiss,
  }) {
    // A live region, so screen readers announce the import result: it lands
    // here rather than in a snackbar.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: color,
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor, fontSize: 13),
              ),
            ),
            if (actionLabel != null && onAction != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: textColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(actionLabel),
                ),
              ),
            if (onDismiss != null)
              IconButton(
                icon: Icon(Icons.close, color: textColor, size: 18),
                tooltip: context.l10n.commonClose,
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + glassTabBarInset(context)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 72,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.libraryEmptyTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.libraryEmptySubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      AppHaptics.light();
                      _importEpub(context, ref);
                    },
                    icon: const Icon(Icons.book),
                    label: Text(l10n.libraryImportEpub),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      AppHaptics.light();
                      _showMangaImportTypeChoice(context, ref);
                    },
                    icon: const Icon(Icons.photo_library),
                    label: Text(l10n.libraryImportManga),
                  ),
                  // One tap installs the starter pack; Downloads shows the
                  // progress.
                  OutlinedButton.icon(
                    onPressed: () {
                      AppHaptics.light();
                      unawaited(installStarterPack(context));
                      Navigator.of(context).push(
                        namedRoute('downloads', (_) => const DownloadsScreen()),
                      );
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.libraryGetDictionaries),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      AppHaptics.light();
                      Navigator.of(context).push(
                        namedRoute(
                          'backup_settings',
                          (_) => const BackupSettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.restore),
                    label: Text(l10n.libraryRestoreBackup),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l10n.libraryFreeBooksTipInApp,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  logUsage('library.free_books_opened');
                  Navigator.of(context).push(
                    namedRoute('free_books', (_) => const FreeBooksScreen()),
                  );
                },
                icon: const Icon(Icons.local_library_outlined),
                label: Text(l10n.libraryFreeBooksLink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookGrid(
    BuildContext context,
    WidgetRef ref, {
    required List<Collection> collections,
    required Map<int, List<Book>> folderBooks,
    required List<Book> looseBooks,
    required Book? recent,
  }) {
    final entries = libraryGridEntries(
      collections: collections,
      looseBooks: looseBooks,
    );
    final indexByKey = {
      for (final (index, entry) in entries.indexed) _gridTileKey(entry): index,
    };
    return CustomScrollView(
      slivers: [
        if (recent != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: ContinueReadingCard(
                book: recent,
                onTap: () => openBookReader(Navigator.of(context), recent),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + glassTabBarInset(context),
          ),
          sliver: SliverGrid(
            gridDelegate: _libraryGridDelegate(context, ref),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = entries[index];
                if (entry is Collection) {
                  return _CollectionFolderTile(
                    key: _gridTileKey(entry),
                    collection: entry,
                    books: folderBooks[entry.id] ?? const [],
                  );
                }
                final book = entry as Book;
                return _BookTile(
                  key: _gridTileKey(book),
                  book: book,
                  isSelectionMode: _isSelectionMode,
                  isSelected: _selectedIds.contains(book.id),
                  onToggleSelection: () => _toggleSelection(book.id),
                );
              },
              childCount: entries.length,
              // A tile moves with its book when an import adds one ahead of
              // it, instead of being rebuilt: a sheet it opened works from it.
              findChildIndexCallback: (key) => indexByKey[key],
            ),
          ),
        ),
      ],
    );
  }

  void _showHelpDialog(BuildContext context) {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.librarySupportedMediaTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // EPUB section
              Text(
                l10n.libraryEpubBooksTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(l10n.libraryEpubBooksDescription),
              const SizedBox(height: 16),

              // Mokuro Manga section
              Text(
                l10n.libraryMokuroTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(l10n.libraryMokuroDescription),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '.mokuro format:\n'
                  '  manga_title.mokuro  <-- choose this from the folder sheet\n'
                  '  manga_title/\n'
                  '  |-- 001.jpg\n'
                  '  `-- ...\n'
                  '\n'
                  'Legacy format:\n'
                  '  manga_title.html    <-- or choose this\n'
                  '  manga_title/\n'
                  '  |-- 001.jpg\n'
                  '  `-- ...\n'
                  '  _ocr/manga_title/\n'
                  '  |-- 001.json\n'
                  '  `-- ...',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.libraryMokuroFormatDescription),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _launchMokuroProject(context),
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.libraryLearnHowToCreateMokuroFiles),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonGotIt),
          ),
        ],
      ),
    );
  }

  void _showSortPicker(
    BuildContext context,
    WidgetRef ref,
    LibrarySortOrder currentOrder,
  ) {
    final l10n = context.l10n;

    showSettingsOptionPickerSheet(
      context: context,
      title: l10n.librarySortBy,
      values: LibrarySortOrder.values,
      selected: currentOrder,
      labelOf: (order) => librarySortLabel(l10n, order),
      iconOf: _sortIcon,
      onSelected: (order) =>
          ref.read(librarySortProvider.notifier).setSortOrder(order),
    );
  }

  static IconData _sortIcon(LibrarySortOrder order) => switch (order) {
    LibrarySortOrder.dateAdded => Icons.calendar_today,
    LibrarySortOrder.lastRead => Icons.schedule,
    LibrarySortOrder.alphabetical => Icons.sort_by_alpha,
  };

  /// Browse a book server from the import sheet. Only the server type goes
  /// to telemetry: names and URLs are user data.
  void _openServer(BuildContext context, ServerConnection server) {
    logUsage(
      'library.server_browse_opened',
      attrs: {'server_type': server.serverType},
    );
    Navigator.of(context).push(
      namedRoute<void>(
        'server_browse',
        (_) => ServerBrowseScreen(connection: server),
      ),
    );
  }

  void _showImportChoice(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      // Scrolls on short screens: three rows plus one per server.
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.libraryImportTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.book),
                title: Text(l10n.libraryImportEpub),
                subtitle: Text(l10n.libraryImportEpubSubtitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _importEpub(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(l10n.libraryImportManga),
                subtitle: Text(l10n.libraryImportMangaSubtitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      _showMangaImportTypeChoice(context, ref);
                    }
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(l10n.libraryImportPdf),
                subtitle: Text(l10n.libraryImportPdfSubtitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _importPdf(ref);
                },
              ),
              // One row per enabled Komga/Kavita server. Servers are a source
              // of books, so they live under "+" rather than as library chrome.
              Consumer(
                builder: (_, sheetRef, _) {
                  final servers =
                      sheetRef
                          .watch(serverConnectionsProvider)
                          .value
                          ?.where((c) => c.enabled) ??
                      const <ServerConnection>[];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final server in servers)
                        ListTile(
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(
                            l10n.libraryImportFromServer(
                              serverName: server.name,
                            ),
                          ),
                          subtitle: Text(
                            server.baseUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _openServer(context, server);
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMangaImportTypeChoice(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.libraryImportMangaTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.libraryImportMangaDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_library),
                    title: Text(l10n.libraryImportMokuroFolder),
                    subtitle: Text(l10n.libraryImportMokuroFolderSubtitle),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _importManga(context, ref);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 56, bottom: 8),
                    child: TextButton.icon(
                      onPressed: () => _launchMokuroProject(sheetContext),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.libraryWhatIsMokuro),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.collections),
                    title: Text(l10n.libraryImportCbzArchive),
                    subtitle: Text(l10n.libraryImportCbzArchiveSubtitle),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _importCbz(ref);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Open the file picker for [extensions] and return the selected paths:
  /// none when the user cancels or the pick failed (said in a snack bar).
  Future<List<String>> _pickFilePaths(List<String> extensions) async {
    switch (await pickFiles(extensions: extensions, multiple: true)) {
      case FileDialogDone(:final value):
        return value;
      case FileDialogFailed(:final failure):
        _showFileDialogFailure(failure);
      case FileDialogCancelled():
    }
    return const [];
  }

  void _showFileDialogFailure(FileDialogFailure failure) {
    if (mounted) _showFileDialogFailureSnackBar(context, failure);
  }

  Future<void> _importEpub(BuildContext context, WidgetRef ref) async {
    final filePaths = await _pickFilePaths(const ['epub']);
    if (filePaths.isEmpty || !context.mounted) return;

    if (!await _confirmLargeImportOnLowRamDevice(context, filePaths)) return;

    ref
        .read(bookImportProvider.notifier)
        .importFiles(filePaths, format: 'epub');
  }

  /// True to proceed with the import. Warns once when a selected EPUB
  /// exceeds [largeEpubWarnBytes] on a device whose RAM makes the reader's
  /// whole-file JS-heap load likely to fail.
  Future<bool> _confirmLargeImportOnLowRamDevice(
    BuildContext context,
    List<String> filePaths,
  ) async {
    var largestBytes = 0;
    for (final path in filePaths) {
      try {
        final len = await File(path).length();
        if (len > largestBytes) largestBytes = len;
      } catch (_) {
        // Unreadable file: let the import flow surface the real error.
      }
    }
    if (largestBytes <= largeEpubWarnBytes || !await _isLowMemoryDevice()) {
      return true;
    }

    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.libraryLargeImportWarnTitle),
        content: Text(
          context.l10n.libraryLargeImportWarnBody(
            sizeMb: largestBytes ~/ (1024 * 1024),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.libraryLargeImportWarnAction),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  static Future<bool> _isLowMemoryDevice() async {
    try {
      if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        return info.physicalRamSize < lowRamDeviceThresholdMb;
      }
      if (!Platform.isAndroid) return false;
      final info = await DeviceInfoPlugin().androidInfo;
      return info.isLowRamDevice ||
          info.physicalRamSize < lowRamDeviceThresholdMb;
    } catch (_) {
      return false; // no device info → don't nag
    }
  }

  /// Scanned PDFs explain themselves after import (showScannedPdfNotice).
  Future<void> _importPdf(WidgetRef ref) async {
    final filePaths = await _pickFilePaths(const ['pdf']);
    if (filePaths.isEmpty) return;
    await ref
        .read(bookImportProvider.notifier)
        .importFiles(filePaths, format: 'pdf');
  }

  /// A CBZ without OCR data says so after import (importOne).
  Future<void> _importCbz(WidgetRef ref) async {
    // The import reads the file's bytes to tell ZIP from RAR, so a .cbr that
    // is really a zip (or the reverse) still imports.
    final filePaths = await _pickFilePaths(const ['cbz', 'cbr', 'zip', 'rar']);
    if (filePaths.isEmpty) return;
    await ref
        .read(bookImportProvider.notifier)
        .importFiles(filePaths, format: 'cbz');
  }

  Future<void> _importManga(BuildContext context, WidgetRef ref) async {
    if (Platform.isAndroid) {
      await _importMangaFromAndroidSafFolder(context, ref);
      return;
    }

    await _importMangaFromLocalFolder(context, ref);
  }

  Future<void> _launchMokuroProject(BuildContext context) async {
    final uri = Uri.parse('https://github.com/kha-white/mokuro');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.libraryCouldNotOpenMokuroProjectPage),
      ),
    );
  }

  Future<void> _importMangaFromAndroidSafFolder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final AndroidSafDirectoryAccess folder;
    switch (await pickAndroidFolder()) {
      case FileDialogDone(:final value):
        folder = value;
      case FileDialogFailed(:final failure):
        return _showFileDialogFailure(failure);
      case FileDialogCancelled():
        return;
    }

    final names = await AndroidSafService.listNamesInTreeDir(folder.treeUri);
    final candidates = names.where(isMangaManifestName).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (candidates.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryNoMangaManifestFound)),
      );
      return;
    }

    if (!context.mounted) return;
    final selectedNames = await showMangaManifestPickerSheet(
      context,
      files: candidates,
      folderLabel: _folderLabelFromTreeDocumentId(
        context,
        folder.treeDocumentId,
      ),
    );
    if (!context.mounted) return;
    if (selectedNames == null) return;

    await ref
        .read(bookImportProvider.notifier)
        .importFiles(
          [for (final name in selectedNames) p.posix.join('/saf', name)],
          format: 'manga_saf',
          safTreeUri: folder.treeUri,
        );
  }

  Future<void> _importMangaFromLocalFolder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = context.l10n;
    final String dirPath;
    switch (await pickIosFolder()) {
      case FileDialogDone(:final value):
        dirPath = value;
      case FileDialogFailed(:final failure):
        return _showFileDialogFailure(failure);
      case FileDialogCancelled():
        return;
    }

    final dir = Directory(dirPath);
    List<FileSystemEntity> entities;
    try {
      entities = await dir.list().toList();
    } catch (e) {
      logFailure('library.folder_read_failed', e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.libraryReadFolderFailed)));
      return;
    }

    final candidates =
        entities
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where(isMangaManifestName)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (candidates.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryNoMangaManifestFound)),
      );
      return;
    }

    if (!context.mounted) return;
    final selectedNames = await showMangaManifestPickerSheet(
      context,
      files: candidates,
      folderLabel: p.basename(dirPath),
    );
    if (!context.mounted) return;
    if (selectedNames == null) return;

    await ref.read(bookImportProvider.notifier).importFiles([
      for (final name in selectedNames) p.join(dirPath, name),
    ], format: 'manga');
  }

  String _folderLabelFromTreeDocumentId(
    BuildContext context,
    String? documentId,
  ) {
    if (documentId == null || documentId.isEmpty) {
      return context.l10n.librarySelectedFolder;
    }
    final afterColon = documentId.contains(':')
        ? documentId.split(':').last
        : documentId;
    final normalized = afterColon.replaceAll('\\', '/');
    final base = normalized.isEmpty ? documentId : p.posix.basename(normalized);
    return base.isEmpty ? context.l10n.librarySelectedFolder : base;
  }
}

/// What Delete OCR does for a manga, when the options sheet offers it.
enum _DeleteOcr {
  /// Clears all text: there is no original to go back to.
  clear,

  /// Restores the text a Mokuro import came with.
  restoreMokuro,

  /// Restores a PDF's own text; never clears it.
  restorePdf,
}

/// Says in a snack bar why a system file dialog did not open, while
/// [context] is still mounted.
void _showFileDialogFailureSnackBar(
  BuildContext context,
  FileDialogFailure failure,
) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(failure.message(context.l10n))));
}

/// Individual book tile for the grid.
class _BookTile extends ConsumerStatefulWidget {
  const _BookTile({
    super.key,
    required this.book,
    this.coverHeroTag,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
    this.inFolder = false,
  });

  final Book book;

  /// A folder has its own manual order, so a tile shown inside one has no
  /// favorite star and no favorite option.
  final bool inFolder;

  /// When set, the cover flies under this tag as a folder opens or closes.
  /// Only the covers a folder's face shows get one; see
  /// [folderCoverHeroTag].
  final String? coverHeroTag;

  /// While true, tap toggles selection instead of opening the reader and
  /// the long-press options sheet is suppressed.
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelection;

  @override
  ConsumerState<_BookTile> createState() => _BookTileState();
}

class _BookTileState extends ConsumerState<_BookTile>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  Offset? _pointerDownPosition;
  Timer? _longPressTimer;
  bool _longPressFired = false;

  /// While the options sheet is up the tile stays built, even when books
  /// imported ahead push it out of view: the sheet's rows act through it.
  bool _optionsOpen = false;

  @override
  bool get wantKeepAlive => _optionsOpen;

  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  void _onPressDown() => _scaleController.forward();
  void _onPressUp() => _scaleController.reverse();

  void _handlePointerDown(PointerDownEvent e) {
    _pointerDownPosition = e.localPosition;
    _longPressFired = false;
    // Selection mode owns the tile: no press-scale, no options sheet —
    // long-press belongs to the reorder drag there.
    if (widget.isSelectionMode) return;
    _onPressDown();

    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      _longPressFired = true;
      AppHaptics.heavy();
      _openOptions();
      _onPressUp();
    });
  }

  void _handlePointerUp(PointerUpEvent e) {
    // The raw Listener never joins the gesture arena, so up/cancel are
    // delivered along the pointer-down-time hit-test path even after this
    // tile is disposed mid-gesture (e.g. by a reorder drag's rebuild).
    // Every terminal-event handler here must guard on mounted.
    if (!mounted) return;
    _longPressTimer?.cancel();
    _onPressUp();

    if (_longPressFired) return;

    final downPos = _pointerDownPosition;
    if (downPos == null) return;
    // The Listener is not a gesture-arena participant, so it also sees the
    // pointer while a reorder drag owns it — the travel threshold is what
    // keeps a drag from counting as a tap.
    if ((e.localPosition - downPos).distance >= 20) return;
    _activate();
  }

  void _activate() {
    if (widget.isSelectionMode) {
      AppHaptics.light();
      widget.onToggleSelection?.call();
    } else {
      openBookReader(Navigator.of(context), book);
    }
  }

  void _openOptions() => _showBookOptions(context, ref);

  void _handlePointerCancel(PointerCancelEvent e) {
    if (!mounted) return; // see _handlePointerUp

    _longPressTimer?.cancel();
    _onPressUp();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final progress = book.readProgress.clamp(0.0, 1.0);
    final percentRead = (progress * 100).round();
    // The raw Listener exposes no actions, so screen readers get the tap and
    // the options sheet from here.
    return Semantics(
      container: true,
      button: true,
      selected: widget.isSelectionMode ? widget.isSelected : null,
      value: percentRead > 0
          ? l10n.readingProgressPercent(percent: percentRead)
          : null,
      onTap: _activate,
      onLongPress: widget.isSelectionMode ? null : _openOptions,
      customSemanticsActions: widget.isSelectionMode
          ? null
          : {
              CustomSemanticsAction(label: l10n.libraryBookOptions):
                  _openOptions,
            },
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: _CoverTilt(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _maybeHero(
                      widget.coverHeroTag,
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // A cover without art draws the title, which the
                            // tile already reads out.
                            ExcludeSemantics(child: BookCoverImage(book: book)),
                            if (book.bookType == 'manga')
                              const _CoverBadge(
                                icon: Icons.photo_library,
                                right: 4,
                              ),
                            if (book.readProgress > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  height: 3,
                                  color: Colors.black.withValues(alpha: 0.3),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    child: Container(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            if (book.bookType == 'manga')
                              OcrProgressOverlay(bookId: book.id),
                            // The selection tick takes this corner.
                            if (book.isFavorite &&
                                !widget.inFolder &&
                                !widget.isSelectionMode)
                              _CoverBadge(
                                icon: Icons.star,
                                left: 4,
                                semanticLabel: l10n.libraryFavoriteBadge,
                              ),
                            if (widget.isSelectionMode)
                              Positioned(
                                // top/right is taken by the manga badge.
                                top: 4,
                                left: 4,
                                child: Icon(
                                  widget.isSelected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 22,
                                  color: widget.isSelected
                                      ? theme.colorScheme.primary
                                      : Colors.white,
                                  // Keeps the circle visible on light covers.
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showBookOptions(BuildContext context, WidgetRef ref) {
    // Resolved before the sheet opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    final deleteOcrFuture = book.bookType == 'manga' ? _loadDeleteOcr() : null;
    final lowRamMode = ref.read(lowRamModeProvider);
    _optionsOpen = true;
    updateKeepAlive();
    showModalBottomSheet(
      context: context,
      // The sheet can exceed the default max height on small screens
      // (EPUB block + export + rename/cover/delete), so it scrolls.
      // Built from sheetContext: the OCR row rebuilds after the tile may be gone.
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(book.title),
                  subtitle: Text(
                    l10n.vocabularyAddedOn(date: _formatDate(book.dateAdded)),
                  ),
                ),
                const Divider(),
                // Bookmarks/highlights are EPUB-only features
                if (book.bookType != 'manga') ...[
                  ListTile(
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text(l10n.libraryBookmarksTitle),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showBookBookmarks(context);
                    },
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final isProUnlocked = proUnlockedValue(
                        ref.watch(proUnlockedProvider),
                      );
                      return ListTile(
                        enabled: isProUnlocked,
                        leading: Icon(
                          Icons.highlight,
                          color: isProUnlocked
                              ? null
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(l10n.readerHighlightsTooltip),
                        trailing: isProUnlocked
                            ? null
                            : TextButton(
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  openProUpgrade(
                                    context,
                                    source: 'library_highlights',
                                  );
                                },
                                child: Text(l10n.commonUnlock),
                              ),
                        onTap: isProUnlocked
                            ? () {
                                Navigator.of(sheetContext).pop();
                                _showBookHighlights(context);
                              }
                            : null,
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.ios_share_outlined),
                    title: Text(l10n.libraryExportFuriganaTitle),
                    onTap: () {
                      AppHaptics.light();
                      Navigator.of(sheetContext).pop();
                      runFuriganaExport(context, ref, book);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(l10n.libraryConvertToMangaTitle),
                    subtitle: Text(l10n.libraryConvertToMangaSubtitle),
                    onTap: () {
                      AppHaptics.light();
                      Navigator.of(sheetContext).pop();
                      runEpubMangaConversion(context, ref, book);
                    },
                  ),
                ],
                // Manga-only features
                if (book.bookType == 'manga') ...[
                  FutureBuilder<_DeleteOcr?>(
                    future: deleteOcrFuture,
                    builder: (ctx, snapshot) {
                      final deleteOcr = snapshot.data;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!lowRamMode)
                            ListTile(
                              leading: const Icon(Icons.document_scanner),
                              title: Text(l10n.localOcrRecognize),
                              subtitle: Text(switch (wording) {
                                Wording.android =>
                                  l10n.localOcrOnDeviceSubtitle,
                                Wording.ios => l10n.localOcrOnDeviceSubtitleIos,
                              }),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                showOcrActionSheet(context, book);
                              },
                            ),
                          if (deleteOcr != null)
                            ListTile(
                              leading: const Icon(Icons.delete_sweep_outlined),
                              title: Text(l10n.ocrRemoveActionTitle),
                              subtitle: Text(switch (deleteOcr) {
                                _DeleteOcr.clear => l10n.ocrRemoveSubtitle,
                                _DeleteOcr.restoreMokuro =>
                                  l10n.ocrRestoreOriginalMokuroSubtitle,
                                _DeleteOcr.restorePdf =>
                                  l10n.ocrRemovePdfSubtitle,
                              }),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                _removeOcr(context, container, deleteOcr);
                              },
                            ),
                        ],
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(l10n.libraryExportCbzTitle),
                    subtitle: Text(l10n.libraryExportCbzSubtitle),
                    onTap: () {
                      AppHaptics.light();
                      Navigator.of(sheetContext).pop();
                      runMangaCbzExport(context, ref, book);
                    },
                  ),
                ],
                const Divider(),
                if (!widget.inFolder)
                  FavoriteToggleTile(
                    isFavorite: book.isFavorite,
                    onToggle: () {
                      unawaited(
                        saveLibraryChange(
                          ScaffoldMessenger.of(sheetContext),
                          () => container
                              .read(bookRepositoryProvider)
                              .setFavorite(book.id, !book.isFavorite),
                          failure: l10n.libraryFavoriteChangeFailed,
                          event: 'library.favorite_change_failed',
                        ),
                      );
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: Text(l10n.libraryAddToCollectionAction),
                  onTap: () {
                    AppHaptics.light();
                    Navigator.of(sheetContext).pop();
                    showCollectionAssignSheet(context, book);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.commonRename),
                  onTap: () {
                    AppHaptics.light();
                    Navigator.of(sheetContext).pop();
                    _showRenameDialog(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(l10n.libraryChangeCoverAction),
                  onTap: () {
                    AppHaptics.light();
                    Navigator.of(sheetContext).pop();
                    _changeCover(context);
                  },
                ),
                ListTile(
                  iconColor: theme.colorScheme.error,
                  textColor: theme.colorScheme.error,
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n.libraryDeleteBookTitle),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmDelete(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      _optionsOpen = false;
      updateKeepAlive();
    });
  }

  // The sheets pop themselves before calling onNavigate.
  void _showBookBookmarks(BuildContext context) {
    final navigator = Navigator.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => BookmarksSheet(
        bookId: book.id,
        onNavigate: (cfi) => openBookReader(navigator, book, initialCfi: cfi),
      ),
    );
  }

  void _showBookHighlights(BuildContext context) {
    final navigator = Navigator.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => HighlightsSheet(
        bookId: book.id,
        onNavigate: (cfiRange) =>
            openBookReader(navigator, book, initialCfi: cfiRange),
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    final controller = TextEditingController(text: book.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.libraryRenameBookTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: ctx.l10n.commonTitleLabel,
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty && newTitle != book.title) {
                unawaited(
                  saveLibraryChange(
                    ScaffoldMessenger.of(ctx),
                    () => container
                        .read(bookRepositoryProvider)
                        .updateTitle(book.id, newTitle),
                    failure: ctx.l10n.libraryRenameBookFailed,
                    event: 'library.book_rename_failed',
                  ),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: Text(ctx.l10n.commonRename),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCover(BuildContext context) async {
    // Read before the picker opens: the tile can unmount while it's up.
    final repo = ref.read(bookRepositoryProvider);
    final String pickedPath;
    switch (await pickFiles(images: true)) {
      case FileDialogDone(:final value):
        pickedPath = value.first;
      case FileDialogFailed(:final failure):
        return _showFileDialogFailureSnackBar(context, failure);
      case FileDialogCancelled():
        return;
    }

    try {
      // Copy picked image to the book's storage directory.
      final bookDir = Directory(book.filePath).parent;
      final ext = p.extension(pickedPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = p.join(bookDir.path, 'custom_cover_$timestamp$ext');
      await File(pickedPath).copy(destPath);
      try {
        await repo.updateCoverImagePath(book.id, destPath);
      } catch (_) {
        // The book keeps its old cover and nothing points at the copy.
        await File(destPath).delete();
        rethrow;
      }
    } catch (e) {
      logFailure('library.cover_change_failed', e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryCoverChangeFailed)),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _removeOcr(
    BuildContext context,
    ProviderContainer container,
    _DeleteOcr deleteOcr,
  ) async {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.ocrRemoveActionTitle),
        content: Text(switch (deleteOcr) {
          _DeleteOcr.clear => dialogContext.l10n.ocrRemoveBody,
          _DeleteOcr.restoreMokuro =>
            dialogContext.l10n.ocrRestoreOriginalMokuroBody,
          _DeleteOcr.restorePdf => dialogContext.l10n.ocrRemovePdfBody,
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.ocrRemoveActionTitle),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await clearOcrTaskState(book.id);
      final repo = container.read(bookRepositoryProvider);
      final restored =
          deleteOcr != _DeleteOcr.clear &&
          await repo.restoreOriginalMokuroOcr(book);
      // A PDF's own text is never cleared, only restored.
      if (!restored && deleteOcr != _DeleteOcr.restorePdf) {
        await repo.clearMangaOcr(book);
      }
      container.invalidate(mangaPagesProvider(book.id));
      container.invalidate(ocrProgressProvider(book.id));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restored && deleteOcr == _DeleteOcr.restoreMokuro
                  ? context.l10n.ocrOriginalMokuroRestored
                  : context.l10n.ocrRemovedFromBook,
            ),
          ),
        );
      }
    } catch (e) {
      logFailure('ocr.delete_failed', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e == MangaPagesUnavailable.pagesMissing
                  ? context.l10n.mangaReaderPagesMissing
                  : context.l10n.ocrDeleteFailed,
            ),
          ),
        );
      }
    }
  }

  /// What Delete OCR would do for this manga; null when there is nothing
  /// to delete.
  Future<_DeleteOcr?> _loadDeleteOcr() async {
    final hasOriginal = await File(
      p.join(book.filePath, BookRepository.originalMokuroOcrBackupFileName),
    ).exists();
    final MokuroBook manga;
    try {
      manga = await MangaCacheStore.read(
        p.join(book.filePath, mangaPagesCacheFileName),
      );
    } catch (_) {
      return null; // No readable cache: nothing to delete.
    }
    if (manga.fromPdf) {
      // A PDF's own text is not OCR: only what an OCR run changed is taken
      // back, by restoring the PDF's text.
      return hasOriginal && !BookRepository.isOriginalText(manga.ocrSource)
          ? _DeleteOcr.restorePdf
          : null;
    }
    if (hasOriginal) return _DeleteOcr.restoreMokuro;
    return manga.pages.any((page) => page.blocks.isNotEmpty)
        ? _DeleteOcr.clear
        : null;
  }

  void _confirmDelete(BuildContext context) {
    // Resolved before the dialog opens: the tile can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    // The page the tile is on (the library or a collection) says it failed.
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.libraryDeleteBookTitle),
        content: Text(ctx.l10n.libraryDeleteBookBody(title: book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final failure = ctx.l10n.libraryDeleteBookFailed;
              Navigator.of(ctx).pop();
              unawaited(
                saveLibraryChange(
                  messenger,
                  () => container
                      .read(bookImportProvider.notifier)
                      .deleteBook(book.id),
                  failure: failure,
                  event: 'library.book_delete_failed',
                ),
              );
            },
            child: Text(
              ctx.l10n.commonDelete,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collection rendered like an iOS app folder: a rounded tile holding a
/// 2x2 preview of member covers, titled like a book tile. Tap opens the
/// folder, long-press manages it.
/// The gyroscope-driven 3D tilt shared by book covers and folder faces.
class _CoverTilt extends StatelessWidget {
  const _CoverTilt({this.borderRadius, required this.child});

  /// Clips the light and shadow layers; null leaves them unclipped.
  final BorderRadiusGeometry? borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Only the top route's tiles listen to the tilt sensors. Route opacity
    // doesn't cancel streams, so covered library tiles would otherwise keep
    // their gyroscope subscriptions (and per-event rebuilds) running for
    // as long as a folder — or a reader — is open. ModalRoute.of registers
    // a dependency, so tiles rebuild and re-enable when uncovered.
    // Motion that follows the phone's movement is what the system's reduce
    // motion setting exists for, so the covers stay still then.
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final enableSensorTilt =
        (Platform.isAndroid || Platform.isIOS) &&
        routeIsCurrent &&
        !MediaQuery.disableAnimationsOf(context);
    return Tilt.base(
      fps: 60,
      borderRadius: borderRadius,
      tiltConfig: TiltConfig(
        angle: 15.0,
        enableReverse: true,
        enableGestureTouch: false,
        enableGestureHover: false,
        enableGestureSensors: enableSensorTilt,
        sensorFactor: 5.0,
        enableSensorRevert: false,
      ),
      lightConfig: const LightConfig(minIntensity: 0.0, maxIntensity: 0.14),
      shadowConfig: ShadowBaseConfig(
        offsetInitial: const Offset(0, 2),
        offsetFactor: 0.08,
        minIntensity: 0.05,
        maxIntensity: 0.4,
        spreadInitial: 0,
        spreadFactor: 0,
        minBlurRadius: 6,
        maxBlurRadius: 16,
        color: Colors.black.withValues(alpha: 0.5),
      ),
      child: child,
    );
  }
}

/// A small icon in a top corner of a cover or a folder's face: the manga
/// badge on the right, the favorite star on the left. Goes in a [Stack].
class _CoverBadge extends StatelessWidget {
  const _CoverBadge({
    required this.icon,
    this.left,
    this.right,
    this.semanticLabel,
  });

  final IconData icon;
  final double? left;
  final double? right;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      left: left,
      right: right,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 12,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

class _CollectionFolderTile extends ConsumerWidget {
  const _CollectionFolderTile({
    super.key,
    required this.collection,
    required this.books,
  });

  final Collection collection;
  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Each cover on the face flies to its own place in the opened grid,
    // the way an iOS folder's icons do. Morphing the face into the grid
    // as one unit can't help jumping, because the two are different
    // layouts with no item-to-item correspondence.
    return GestureDetector(
      onTap: () {
        AppHaptics.light();
        Navigator.of(context).push(
          _folderRoute(collection.id, instant: ref.read(lowRamModeProvider)),
        );
      },
      onLongPress: () {
        AppHaptics.heavy();
        showCollectionManageSheet(context, collection);
      },
      child: Column(
        children: [
          Expanded(
            child: _CoverTilt(
              borderRadius: BorderRadius.circular(_folderCornerRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _FolderPreview(books: books, collectionId: collection.id),
                  if (collection.isFavorite)
                    _CoverBadge(
                      icon: Icons.star,
                      left: 4,
                      semanticLabel: context.l10n.libraryFavoriteBadge,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            collection.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Corner radius of a folder's face.
const double _folderCornerRadius = 12;

/// [books] filtered to [collectionId]'s members, in membership order.
/// Position first; ties (every row predating v22 sits at 0) fall back to
/// the order [books] already has, i.e. the library sort. The rank map is
/// the tie-break carrier because Dart's sort is not stable.
List<Book> booksInCollectionOrder({
  required int collectionId,
  required List<Book> books,
  required List<BookCollection> memberships,
}) {
  final position = {
    for (final m in memberships)
      if (m.collectionId == collectionId) m.bookId: m.position,
  };
  final members = [
    for (final b in books)
      if (position.containsKey(b.id)) b,
  ];
  final rank = {for (var i = 0; i < members.length; i++) members[i].id: i};
  members.sort((a, b) {
    final byPosition = position[a.id]!.compareTo(position[b.id]!);
    return byPosition != 0 ? byPosition : rank[a.id]!.compareTo(rank[b.id]!);
  });
  return members;
}

/// Hero tag for one cover shown on a folder's face. Scoped to the
/// collection so a book filed in two folders gets a distinct tag per
/// folder — two heroes sharing a tag on one screen is a crash.
String folderCoverHeroTag(int collectionId, int bookId) =>
    'folder-$collectionId-cover-$bookId';

/// Flies the SOURCE hero's child instead of the default (the destination's
/// child). The destination side of a cover flight is an Image whose
/// decode starts only when its screen is first built — on push the
/// default shuttle therefore renders blank for most of the flight,
/// blanking all four covers at once and reading as a full-screen flash.
/// The source side is by definition already decoded and on screen
/// (verified frame-by-frame from a screen recording).
Widget _coverFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  return (fromHeroContext.widget as Hero).child;
}

/// Wraps [child] in a Hero when [tag] is set.
Widget _maybeHero(String? tag, Widget child) => tag == null
    ? child
    : Hero(tag: tag, flightShuttleBuilder: _coverFlightShuttle, child: child);

/// Fades the folder screen in while the covers fly to their places. The
/// default route slides the page, which fights the flights. [instant]
/// (Low RAM mode) opens and closes it at once, with no flights.
Route<void> _folderRoute(int collectionId, {required bool instant}) {
  countUsage('collection.opened');
  final duration = instant ? Duration.zero : const Duration(milliseconds: 320);
  return PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'collection'),
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (_, _, _) => VerticalBarInset(
      child: CollectionFolderScreen(collectionId: collectionId),
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// The rounded folder face: up to four member covers in a 2x2, or a
/// placeholder icon while empty. Shared by the grid tile and the folder
/// screen's app bar so the hero flight morphs one into the other.
class _FolderPreview extends StatelessWidget {
  const _FolderPreview({required this.books, required this.collectionId});

  final List<Book> books;
  final int collectionId;

  /// How many covers the face shows — and so how many fly when it opens.
  static const int previewCount = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_folderCornerRadius),
      ),
      child: books.isEmpty
          ? Center(
              child: Icon(
                Icons.collections_bookmark_outlined,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.65,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final book in books.take(previewCount))
                  Hero(
                    tag: folderCoverHeroTag(collectionId, book.id),
                    flightShuttleBuilder: _coverFlightShuttle,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: BookCoverImage(book: book),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Fades, lifts and grows a folder tile in on a slice of the route's own
/// animation, so books without a hero partner enter deliberately instead
/// of popping in with the page.
///
/// Driven by the route rather than a per-tile AnimationController on
/// purpose: the grid's builder delegate disposes children scrolled past
/// the cache extent, so a controller would replay the entrance on
/// scroll-back (the trap stats_screen.dart documents). The route animation
/// sits at 1.0 forever once the push settles, so a remounted tile builds
/// static; on pop it runs 1→0 and the tiles stagger back out.
class _StaggeredEntrance extends StatelessWidget {
  const _StaggeredEntrance({
    super.key,
    required this.animation,
    required this.index,
    required this.child,
  });

  final Animation<double> animation;

  /// 0 for the first tile that has no hero to fly in on.
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (0.25 + 0.06 * index).clamp(0.0, 0.7);
    // .drive rather than CurvedAnimation: a CurvedAnimation built in
    // build() is never disposed.
    final t = animation.drive(
      CurveTween(curve: Interval(start, 1, curve: Curves.easeOutCubic)),
    );
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: t.drive(
          Tween(begin: const Offset(0, 0.06), end: Offset.zero),
        ),
        child: ScaleTransition(
          scale: t.drive(Tween(begin: 0.94, end: 1.0)),
          child: child,
        ),
      ),
    );
  }
}

/// One collection's books in the same grid the library uses. Rename/delete
/// live behind the app-bar action; deleting pops back to the library.
class CollectionFolderScreen extends ConsumerStatefulWidget {
  const CollectionFolderScreen({super.key, required this.collectionId});

  final int collectionId;

  @override
  ConsumerState<CollectionFolderScreen> createState() =>
      _CollectionFolderScreenState();
}

class _CollectionFolderScreenState
    extends ConsumerState<CollectionFolderScreen> {
  // ReorderableBuilder measures grid children through the GridView's key
  // and needs to share its scroll controller.
  final _scrollController = ScrollController();
  final _gridKey = GlobalKey();

  // Edit mode: tap selects, long-press-drag reorders. Vocabulary-screen
  // pattern.
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  /// Optimistic order while a reorder's stream echo is in flight.
  /// See [pendingDragOrder].
  List<Book>? _localOrder;

  int get collectionId => widget.collectionId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _enterSelectionMode() {
    AppHaptics.light();
    setState(() {
      _isSelectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int bookId) {
    setState(() {
      _selectedIds.contains(bookId)
          ? _selectedIds.remove(bookId)
          : _selectedIds.add(bookId);
    });
  }

  void _handleReorder(ReorderedListFunction<Book> reorder, List<Book> current) {
    final next = reorder(current);
    setState(() => _localOrder = next);
    // _localOrder retires in build once the stream echoes this order.
    final repo = ref.read(collectionRepositoryProvider);
    unawaited(
      saveLibraryChange(
        ScaffoldMessenger.of(context),
        () => repo.reorderCollectionBooks(collectionId, [
          for (final b in next) b.id,
        ]),
        failure: context.l10n.libraryCollectionChangeFailed,
        event: 'library.collection_change_failed',
      ).then((saved) {
        // Write failed: the stream will never echo this order, so drop the
        // optimistic one and let the grid fall back to the DB order.
        if (!saved && mounted) setState(() => _localOrder = null);
      }),
    );
  }

  Future<void> _removeSelectedFromFolder() async {
    // Resolved before the dialog opens: the screen can unmount while it's up.
    final container = ProviderScope.containerOf(context, listen: false);
    if (_selectedIds.length > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            ctx.l10n.libraryRemoveFromFolderConfirmTitle(
              count: _selectedIds.length,
            ),
          ),
          content: Text(ctx.l10n.libraryRemoveFromFolderConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.commonRemove),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    final removed = await saveLibraryChange(
      ScaffoldMessenger.of(context),
      () => container
          .read(collectionRepositoryProvider)
          .removeBooksFromCollection(collectionId, {..._selectedIds}),
      failure: context.l10n.libraryCollectionChangeFailed,
      event: 'library.collection_change_failed',
    );
    // Not removed: the selection stays, to try again.
    if (removed && mounted) _exitSelectionMode();
  }

  Widget _tile(List<Book> members, int index, Animation<double> route) {
    // ReorderableBuilder asserts a ValueKey on every direct child, so the
    // key must sit on the outermost widget returned here.
    final key = _gridTileKey(members[index]);
    final tile = _BookTile(
      key: index < _FolderPreview.previewCount ? key : null,
      book: members[index],
      // Covers the face showed have a hero partner to fly from.
      coverHeroTag: index < _FolderPreview.previewCount
          ? folderCoverHeroTag(collectionId, members[index].id)
          : null,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedIds.contains(members[index].id),
      onToggleSelection: () => _toggleSelection(members[index].id),
      inFolder: true,
    );
    if (index < _FolderPreview.previewCount) return tile;
    return _StaggeredEntrance(
      key: key,
      animation: route,
      index: index - _FolderPreview.previewCount,
      child: tile,
    );
  }

  AppBar _buildSelectionAppBar(List<Book> members) {
    final l10n = context.l10n;
    final allSelected =
        members.isNotEmpty && members.every((b) => _selectedIds.contains(b.id));
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.commonClose,
        onPressed: _exitSelectionMode,
      ),
      title: Text(l10n.librarySelectedCount(count: _selectedIds.length)),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected
              ? l10n.libraryDeselectAllTooltip
              : l10n.librarySelectAllTooltip,
          onPressed: () => setState(() {
            allSelected
                ? _selectedIds.clear()
                : _selectedIds.addAll(members.map((b) => b.id));
          }),
        ),
        IconButton(
          icon: const Icon(Icons.playlist_remove),
          tooltip: l10n.libraryRemoveFromFolderAction,
          onPressed: _selectedIds.isEmpty ? null : _removeSelectedFromFolder,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final collections =
        ref.watch(collectionsProvider).value ?? const <Collection>[];
    Collection? collection;
    for (final c in collections) {
      if (c.id == collectionId) {
        collection = c;
        break;
      }
    }
    if (collection == null) {
      // Deleted while open (via the manage sheet): leave gracefully.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final managed = collection;

    final books = ref.watch(booksProvider).value ?? const <Book>[];
    final memberships =
        ref.watch(bookCollectionsProvider).value ?? const <BookCollection>[];
    final streamMembers = booksInCollectionOrder(
      collectionId: collectionId,
      books: books,
      memberships: memberships,
    );
    // Same content once retired, so no setState needed here.
    _localOrder = pendingDragOrder(_localOrder, streamMembers, (b) => b.id);
    final members = _localOrder ?? streamMembers;

    final theme = Theme.of(context);
    final routeAnimation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;

    return Scaffold(
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(members)
          : AppBar(
              title: Text(managed.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: context.l10n.librarySelectTooltip,
                  onPressed: _enterSelectionMode,
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                  onPressed: () {
                    AppHaptics.light();
                    showCollectionManageSheet(context, managed);
                  },
                ),
              ],
            ),
      body: members.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.l10n.libraryFolderEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ReorderableBuilder<Book>.builder(
              key: const Key('folder-reorderable'),
              // No new-child fade-in: on the screen's first build every tile
              // is "new", and the default 500ms fade outlives the 320ms
              // route transition — the hero shuttle would land on a
              // still-fading tile and the cover flashed bright -> dim.
              // Entrances are the route fade + _StaggeredEntrance's job.
              animationConfig: const ReorderableAnimationConfig(
                fadeInDuration: Duration.zero,
              ),
              scrollController: _scrollController,
              itemCount: members.length,
              // One edit mode = select + drag; outside it this is a plain
              // grid and all existing gestures apply.
              enableDraggable: _isSelectionMode,
              onReorder: (reorderFn) => _handleReorder(reorderFn, members),
              childBuilder: (itemBuilder) => GridView.builder(
                key: _gridKey,
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: _libraryGridDelegate(context, ref),
                itemCount: members.length,
                itemBuilder: (context, index) =>
                    itemBuilder(_tile(members, index, routeAnimation), index),
              ),
            ),
    );
  }
}
