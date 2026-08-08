import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/entities/reorderable_animation_config.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tilt/flutter_tilt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/widgets/book_cover_image.dart';
import 'package:mekuru/features/library/presentation/widgets/collection_widgets.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/library/presentation/widgets/continue_reading_card.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/manga/presentation/services/ocr_purchase_flow.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/bookmarks_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_progress_overlay.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/utils/pending_drag_order.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

void _openBookReader(BuildContext context, Book book) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => book.bookType == 'manga'
          ? MangaReaderScreen(book: book)
          : ReaderScreen(book: book),
    ),
  );
}

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
              ],
            ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: importState.isImporting
                  ? null
                  : () => _showImportChoice(context, ref),
              tooltip: l10n.commonImport,
              child: const Icon(Icons.add),
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
              message: importState.error!,
              onDismiss: () =>
                  ref.read(bookImportProvider.notifier).clearState(),
            ),
          if (importState.successMessage != null)
            _buildBanner(
              context,
              icon: Icons.check_circle_outline,
              color: Colors.green.withValues(alpha: 0.1),
              textColor: Colors.green,
              message: importState.successMessage!,
              actionLabel: importState.importedBook != null
                  ? l10n.commonOpenNow
                  : null,
              onAction: importState.importedBook == null
                  ? null
                  : () {
                      final book = importState.importedBook!;
                      ref.read(bookImportProvider.notifier).clearState();
                      _openBookReader(context, book);
                    },
              onDismiss: () =>
                  ref.read(bookImportProvider.notifier).clearState(),
            ),
          Expanded(
            child: booksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  l10n.commonErrorWithDetails(details: err.toString()),
                ),
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
    return Container(
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
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
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
                      _importEpub(ref);
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
                  OutlinedButton.icon(
                    onPressed: () {
                      AppHaptics.light();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DownloadsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.libraryGetDictionaries),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      AppHaptics.light();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BackupSettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.restore),
                    label: Text(l10n.libraryRestoreBackup),
                  ),
                ],
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
    return CustomScrollView(
      slivers: [
        if (recent != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: ContinueReadingCard(
                book: recent,
                onTap: () => _openBookReader(context, recent),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index < collections.length) {
                final collection = collections[index];
                return _CollectionFolderTile(
                  key: ValueKey('folder-tile-${collection.id}'),
                  collection: collection,
                  books: folderBooks[collection.id] ?? const [],
                );
              }
              final book = looseBooks[index - collections.length];
              return _BookTile(
                key: ValueKey('book-tile-${book.id}'),
                book: book,
                isSelectionMode: _isSelectionMode,
                isSelected: _selectedIds.contains(book.id),
                onToggleSelection: () => _toggleSelection(book.id),
              );
            }, childCount: collections.length + looseBooks.length),
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

  void _showImportChoice(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
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
                _importEpub(ref);
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
          ],
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
                      _importCbz(context, ref);
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

  /// Open the file picker for [extensions] and return the selected paths.
  /// Returns an empty list when the user cancels or when another picker is
  /// still resolving (e.g. double-tap of the FAB).
  Future<List<String>> _pickFilePaths(List<String> extensions) async {
    final FilePickerResult? result;
    try {
      // allowMultiple defaults to true (and is deprecated as a parameter).
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
    } on PlatformException catch (e) {
      if (e.code == 'already_active') return const [];
      rethrow;
    }

    if (result == null) return const [];
    return result.files.map((f) => f.path).nonNulls.toList();
  }

  Future<void> _importEpub(WidgetRef ref) async {
    final filePaths = await _pickFilePaths(const ['epub']);
    if (filePaths.isEmpty) return;

    ref
        .read(bookImportProvider.notifier)
        .importFiles(filePaths, format: 'epub');
  }

  Future<void> _importCbz(BuildContext context, WidgetRef ref) async {
    final filePaths = await _pickFilePaths(const ['cbz']);
    if (filePaths.isEmpty) return;

    final imported = await ref
        .read(bookImportProvider.notifier)
        .importFiles(filePaths, format: 'cbz');
    if (imported > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryImportedWithoutOcrMessage)),
      );
    }
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
    final folder = await AndroidSafService.pickDirectory();
    if (folder == null) return;

    final names = await AndroidSafService.listNamesInTreeDir(folder.treeUri);
    final candidates = names.where(_isSupportedMangaManifestName).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (candidates.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryNoMangaManifestFound)),
      );
      return;
    }

    if (!context.mounted) return;
    final selectedName = await _showMangaManifestPickerSheet(
      context,
      files: candidates,
      folderLabel: _folderLabelFromTreeDocumentId(
        context,
        folder.treeDocumentId,
      ),
    );
    if (!context.mounted) return;
    if (selectedName == null) return;

    final syntheticImportPath = p.posix.join('/saf', selectedName);
    debugPrint(
      '[MangaImport] Folder import (SAF): ${folder.treeUri} -> $selectedName',
    );

    ref
        .read(bookImportProvider.notifier)
        .importMangaWithSaf(
          syntheticImportPath,
          safTreeUri: folder.treeUri,
          safSelectedFileRelativePath: selectedName,
        );
  }

  Future<void> _importMangaFromLocalFolder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = context.l10n;
    final dirPath = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.librarySelectMangaFolder,
    );
    if (dirPath == null || dirPath.isEmpty) return;

    final dir = Directory(dirPath);
    List<FileSystemEntity> entities;
    try {
      entities = await dir.list().toList();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.libraryCouldNotReadFolder(details: '$e'))),
      );
      return;
    }

    final candidates =
        entities
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where(_isSupportedMangaManifestName)
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
    final selectedName = await _showMangaManifestPickerSheet(
      context,
      files: candidates,
      folderLabel: p.basename(dirPath),
    );
    if (!context.mounted) return;
    if (selectedName == null) return;

    final importPath = p.join(dirPath, selectedName);
    debugPrint('[MangaImport] Folder import: $importPath');
    ref.read(bookImportProvider.notifier).importManga(importPath);
  }

  bool _isSupportedMangaManifestName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mokuro') || lower.endsWith('.html');
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

  Future<String?> _showMangaManifestPickerSheet(
    BuildContext context, {
    required List<String> files,
    required String folderLabel,
  }) {
    final l10n = context.l10n;

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(folderLabel),
              subtitle: Text(l10n.libraryMangaFilesFound(count: files.length)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  final isMokuro = file.toLowerCase().endsWith('.mokuro');
                  return ListTile(
                    leading: Icon(isMokuro ? Icons.data_object : Icons.html),
                    title: Text(file),
                    onTap: () => Navigator.of(sheetContext).pop(file),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MangaOcrCacheSummary {
  final int totalPages;
  final int pagesWithOcr;
  final int pagesWithoutOcr;
  final int pagesNeedingWordSegmentation;
  final String? ocrSource;
  final bool ocrCompleted;
  final bool hasOriginalMokuroBackup;

  const _MangaOcrCacheSummary({
    required this.totalPages,
    required this.pagesWithOcr,
    required this.pagesWithoutOcr,
    required this.pagesNeedingWordSegmentation,
    this.ocrSource,
    this.ocrCompleted = false,
    this.hasOriginalMokuroBackup = false,
  });

  static const empty = _MangaOcrCacheSummary(
    totalPages: 0,
    pagesWithOcr: 0,
    pagesWithoutOcr: 0,
    pagesNeedingWordSegmentation: 0,
  );

  bool get isMokuroSource => ocrSource == 'mokuro';
  bool get hasPartialOcr =>
      !isMokuroSource &&
      !hasCompleteOcr &&
      pagesWithOcr > 0 &&
      pagesWithoutOcr > 0;
  bool get hasCompleteOcr =>
      totalPages > 0 &&
      (ocrCompleted || isMokuroSource || pagesWithoutOcr == 0);
  bool get needsWordSegmentation => pagesNeedingWordSegmentation > 0;
  bool get canRestoreOriginalMokuroOcr => hasOriginalMokuroBackup;
}

@visibleForTesting
String mangaOcrPrimaryActionTitle({
  required AppLocalizations l10n,
  required bool isRunning,
  required bool isMokuroComplete,
  required bool hasCompleteOcr,
}) {
  if (isRunning) {
    return l10n.ocrCancelActionTitle;
  }
  if (isMokuroComplete) {
    return l10n.ocrReplaceActionTitle;
  }
  if (hasCompleteOcr) {
    return l10n.ocrRemoveActionTitle;
  }
  return l10n.ocrRunActionTitle;
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
  });

  final Book book;

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  Offset? _pointerDownPosition;
  Timer? _longPressTimer;
  bool _longPressFired = false;

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
      _showBookOptions(context, ref);
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
    if (widget.isSelectionMode) {
      AppHaptics.light();
      widget.onToggleSelection?.call();
    } else {
      _openBookReader(context, book);
    }
  }

  void _handlePointerCancel(PointerCancelEvent e) {
    if (!mounted) return; // see _handlePointerUp

    _longPressTimer?.cancel();
    _onPressUp();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Listener(
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
                          BookCoverImage(book: book),
                          if (book.bookType == 'manga')
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.photo_library,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
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
                                  widthFactor: book.readProgress.clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: Container(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          if (book.bookType == 'manga')
                            OcrProgressOverlay(bookId: book.id),
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
                                    : Colors.white70,
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
    );
  }

  void _showBookOptions(BuildContext context, WidgetRef ref) {
    final ocrSummaryFuture = book.bookType == 'manga'
        ? _loadMangaOcrSummary()
        : null;
    showModalBottomSheet(
      context: context,
      // The sheet can exceed the default max height on small screens
      // (EPUB block + export + rename/cover/delete), so it scrolls.
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(book.title),
                subtitle: Text(
                  context.l10n.vocabularyAddedOn(
                    date: _formatDate(book.dateAdded),
                  ),
                ),
              ),
              const Divider(),
              // Bookmarks/highlights are EPUB-only features
              if (book.bookType != 'manga') ...[
                ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(context.l10n.libraryBookmarksTitle),
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
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(context.l10n.readerHighlightsTooltip),
                      trailing: isProUnlocked
                          ? null
                          : TextButton(
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _openProUpgrade(context);
                              },
                              child: Text(context.l10n.commonUnlock),
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
                  title: Text(context.l10n.libraryExportFuriganaTitle),
                  onTap: () {
                    AppHaptics.light();
                    Navigator.of(sheetContext).pop();
                    runFuriganaExport(context, ref, book);
                  },
                ),
              ],
              // Manga-only features
              if (book.bookType == 'manga') ...[
                FutureBuilder<_MangaOcrCacheSummary>(
                  future: ocrSummaryFuture,
                  builder: (ctx, snapshot) {
                    final summary =
                        snapshot.data ?? _MangaOcrCacheSummary.empty;
                    final isRunning = ref.watch(isOcrRunningProvider(book.id));
                    final progress = ref.watch(ocrProgressProvider(book.id));
                    final currentOcrProgress = progress.whenOrNull(
                      data: (p) => p,
                    );
                    final completedPages = progress.whenOrNull(
                      data: (p) => p?.completed,
                    );
                    final totalPages = progress.whenOrNull(
                      data: (p) => p?.total,
                    );
                    final isProUnlocked = proUnlockedValue(
                      ref.watch(proUnlockedProvider),
                    );

                    final hasCompleteOcr = summary.hasCompleteOcr;
                    final canResume = summary.hasPartialOcr;
                    final isWordOnlyPass =
                        summary.needsWordSegmentation &&
                        summary.pagesWithoutOcr == 0;
                    final isPaused =
                        currentOcrProgress?.status == OcrStatus.cancelled;
                    final isMokuroComplete =
                        summary.isMokuroSource && !isRunning;
                    final l10n = context.l10n;
                    final deleteOcrSubtitle =
                        summary.canRestoreOriginalMokuroOcr
                        ? l10n.ocrRestoreOriginalMokuroSubtitle
                        : l10n.ocrRemoveSubtitle;
                    final showDeleteOcrOption =
                        (isPaused &&
                            (summary.pagesWithOcr > 0 ||
                                summary.canRestoreOriginalMokuroOcr)) ||
                        isMokuroComplete;
                    final needsProUnlock =
                        !isRunning &&
                        !hasCompleteOcr &&
                        !isWordOnlyPass &&
                        !isMokuroComplete;
                    final isProLocked = needsProUnlock && !isProUnlocked;

                    final title = mangaOcrPrimaryActionTitle(
                      l10n: l10n,
                      isRunning: isRunning,
                      isMokuroComplete: isMokuroComplete,
                      hasCompleteOcr: hasCompleteOcr,
                    );
                    final subtitle = isProLocked
                        ? l10n.ocrUnlockProSubtitle
                        : isRunning
                        ? l10n.ocrStopAndSaveProgressSubtitle
                        : isMokuroComplete
                        ? l10n.ocrReplaceMokuroSubtitle
                        : hasCompleteOcr
                        ? deleteOcrSubtitle
                        : isWordOnlyPass
                        ? l10n.ocrBuildWordTargetsSubtitle
                        : canResume
                        ? l10n.ocrResumeSubtitle(
                            completed: completedPages ?? summary.pagesWithOcr,
                            total: totalPages ?? summary.totalPages,
                          )
                        : l10n.ocrRecognizeAllPagesSubtitle;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          enabled: !isProLocked,
                          leading: Icon(
                            isRunning
                                ? Icons.pause_circle_outline
                                : isMokuroComplete
                                ? Icons.find_replace
                                : hasCompleteOcr
                                ? Icons.delete_sweep_outlined
                                : Icons.document_scanner,
                          ),
                          title: Text(title),
                          subtitle: Text(subtitle),
                          trailing: isProLocked
                              ? TextButton(
                                  onPressed: () {
                                    Navigator.of(sheetContext).pop();
                                    _openProUpgrade(context);
                                  },
                                  child: Text(l10n.commonUnlock),
                                )
                              : null,
                          onTap: isProLocked
                              ? null
                              : () {
                                  Navigator.of(sheetContext).pop();
                                  if (isRunning) {
                                    _pauseOcr(context, ref);
                                    return;
                                  }
                                  if (isMokuroComplete) {
                                    _replaceOcrForMokuro(context, ref);
                                    return;
                                  }
                                  if (hasCompleteOcr) {
                                    _removeOcr(
                                      context,
                                      ref,
                                      restoreOriginalMokuro:
                                          summary.canRestoreOriginalMokuroOcr,
                                    );
                                    return;
                                  }
                                  _startOcr(context, ref);
                                },
                        ),
                        if (showDeleteOcrOption)
                          ListTile(
                            leading: const Icon(Icons.delete_sweep_outlined),
                            title: Text(l10n.ocrRemoveActionTitle),
                            subtitle: Text(deleteOcrSubtitle),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              _removeOcr(
                                context,
                                ref,
                                restoreOriginalMokuro:
                                    summary.canRestoreOriginalMokuroOcr,
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: Text(context.l10n.libraryAddToCollectionAction),
                onTap: () {
                  AppHaptics.light();
                  Navigator.of(sheetContext).pop();
                  showCollectionAssignSheet(context, book);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.l10n.commonRename),
                onTap: () {
                  AppHaptics.light();
                  Navigator.of(sheetContext).pop();
                  _showRenameDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(context.l10n.libraryChangeCoverAction),
                onTap: () {
                  AppHaptics.light();
                  Navigator.of(sheetContext).pop();
                  _changeCover(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  context.l10n.libraryDeleteBookTitle,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookBookmarks(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => BookmarksSheet(
        bookId: book.id,
        onNavigate: (cfi) {
          Navigator.of(context).pop();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
        },
      ),
    );
  }

  void _showBookHighlights(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => HighlightsSheet(
        bookId: book.id,
        onNavigate: (cfiRange) {
          Navigator.of(context).pop();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
        },
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: book.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.libraryRenameBookTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.commonTitleLabel,
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty && newTitle != book.title) {
                ref.read(bookRepositoryProvider).updateTitle(book.id, newTitle);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(context.l10n.commonRename),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCover(BuildContext context) async {
    final picked = await FilePicker.pickFile(type: FileType.image);

    if (picked == null) return;
    final pickedPath = picked.path;
    if (pickedPath == null) return;

    try {
      // Copy picked image to the book's storage directory.
      final bookDir = Directory(book.filePath).parent;
      final ext = p.extension(pickedPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = p.join(bookDir.path, 'custom_cover_$timestamp$ext');
      await File(pickedPath).copy(destPath);

      ref.read(bookRepositoryProvider).updateCoverImagePath(book.id, destPath);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.libraryChangeCoverFailed(details: '$e')),
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openProUpgrade(BuildContext context) async {
    await openProUpgrade(context, ref);
  }

  void _startOcr(BuildContext context, WidgetRef ref) async {
    final cacheFilePath = p.join(book.filePath, 'pages_cache.json');
    final cacheFile = File(cacheFilePath);

    if (!cacheFile.existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrNoPagesCacheFound)),
        );
      }
      return;
    }

    // Read cache to determine what OCR work remains.
    final cacheJson =
        json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
    final imageDirPath = cacheJson['imageDirPath'] as String? ?? '';
    final pages = cacheJson['pages'] as List<dynamic>? ?? [];
    final ocrSource = cacheJson['ocrSource'] as String?;
    final ocrCompleted = cacheJson['ocrCompleted'] as bool?;
    final summary = _summarizeOcrPages(
      pages,
      ocrSource: ocrSource,
      ocrCompleted: ocrCompleted,
    );
    final emptyCount = summary.pagesWithoutOcr;
    final isWordOnlyPass = emptyCount == 0 && summary.needsWordSegmentation;

    if (emptyCount == 0 && !summary.needsWordSegmentation) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrAlreadyCompleteResetHint)),
        );
      }
      return;
    }

    if (!isWordOnlyPass && imageDirPath.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrMangaImageDirectoryNotFound)),
        );
      }
      return;
    }

    // Confirm with user
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isWordOnlyPass
              ? context.l10n.ocrBuildWordOverlaysTitle
              : context.l10n.ocrRunActionTitle,
        ),
        content: Text(
          isWordOnlyPass
              ? context.l10n.ocrBuildWordOverlaysBody
              : context.l10n.ocrProcessPagesBody(count: emptyCount),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              isWordOnlyPass
                  ? context.l10n.ocrProcessAction
                  : context.l10n.ocrStartAction,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    if (!isWordOnlyPass) {
      try {
        final ready = await OcrPurchaseFlow.instance.ensureProAndCustomOcrReady(
          context,
          getServerUrl: () => ref.read(ocrServerUrlProvider),
        );
        if (!ready) return;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.ocrPrepareFailed(details: '$e')),
            ),
          );
        }
        return;
      }
    }

    try {
      await scheduleOcrTask(
        bookId: book.id,
        cacheFilePath: cacheFilePath,
        imageDir: imageDirPath,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrStartFailed(details: '$e'))),
        );
      }
      return;
    }

    // Invalidate the progress provider so it starts polling
    ref.invalidate(ocrProgressProvider(book.id));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isWordOnlyPass
                ? context.l10n.ocrWordOverlayStartedBackground
                : context.l10n.ocrStartedBackground,
          ),
        ),
      );
    }
  }

  void _replaceOcrForMokuro(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.ocrReplaceActionTitle),
        content: Text(context.l10n.ocrReplaceMokuroBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.ocrReplaceActionTitle),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final ready = await OcrPurchaseFlow.instance.ensureProAndCustomOcrReady(
        context,
        getServerUrl: () => ref.read(ocrServerUrlProvider),
      );
      if (!ready) return;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrPrepareFailed(details: '$e'))),
        );
      }
      return;
    }

    // Clear all OCR blocks and reset ocrSource so the worker processes every page
    final cacheFilePath = p.join(book.filePath, 'pages_cache.json');
    final cacheFile = File(cacheFilePath);
    if (!cacheFile.existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrNoPagesCacheFound)),
        );
      }
      return;
    }

    try {
      await ref
          .read(bookRepositoryProvider)
          .backupOriginalMokuroOcrIfNeeded(book);

      final cacheJson =
          json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
      final mokuroBook = MokuroBook.fromJson(cacheJson);
      final imageDirPath = mokuroBook.imageDirPath;

      final clearedPages = mokuroBook.pages
          .map((page) => page.copyWith(blocks: const []))
          .toList();
      final cleared = mokuroBook.copyWith(
        ocrSource: null,
        ocrCompleted: false,
        pages: clearedPages,
      );
      await writeStringAtomic(cacheFile, json.encode(cleared.toJson()));

      await scheduleOcrTask(
        bookId: book.id,
        cacheFilePath: cacheFilePath,
        imageDir: imageDirPath,
      );

      ref.invalidate(ocrProgressProvider(book.id));
      ref.invalidate(mangaPagesProvider(book.id));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrReplaceStartedBackground)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrStartFailed(details: '$e'))),
        );
      }
    }
  }

  void _pauseOcr(BuildContext context, WidgetRef ref) async {
    await cancelOcrTask(book.id);

    // Invalidate to pick up the cancelled status
    ref.invalidate(ocrProgressProvider(book.id));
    ref.invalidate(mangaPagesProvider(book.id));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.ocrCancelSavedProgress)),
      );
    }
  }

  void _removeOcr(
    BuildContext context,
    WidgetRef ref, {
    bool restoreOriginalMokuro = false,
  }) async {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.ocrRemoveActionTitle),
        content: Text(
          restoreOriginalMokuro
              ? context.l10n.ocrRestoreOriginalMokuroBody
              : context.l10n.ocrRemoveBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.ocrRemoveActionTitle),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await clearOcrTaskState(book.id);
      final repo = ref.read(bookRepositoryProvider);
      final restored = restoreOriginalMokuro
          ? await repo.restoreOriginalMokuroOcr(book)
          : false;
      if (!restored) {
        await repo.clearMangaOcr(book);
      }
      ref.invalidate(mangaPagesProvider(book.id));
      ref.invalidate(ocrProgressProvider(book.id));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restored
                  ? context.l10n.ocrOriginalMokuroRestored
                  : context.l10n.ocrRemovedFromBook,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ocrRemoveFailed(details: '$e'))),
        );
      }
    }
  }

  Future<_MangaOcrCacheSummary> _loadMangaOcrSummary() async {
    final cacheFilePath = p.join(book.filePath, 'pages_cache.json');
    final cacheFile = File(cacheFilePath);
    final backupFile = File(
      p.join(book.filePath, BookRepository.originalMokuroOcrBackupFileName),
    );
    final hasOriginalMokuroBackup = await backupFile.exists();
    if (!await cacheFile.exists()) {
      return _MangaOcrCacheSummary(
        totalPages: 0,
        pagesWithOcr: 0,
        pagesWithoutOcr: 0,
        pagesNeedingWordSegmentation: 0,
        hasOriginalMokuroBackup: hasOriginalMokuroBackup,
      );
    }

    try {
      final cacheJson =
          json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
      final pages = cacheJson['pages'] as List<dynamic>? ?? [];
      final ocrSource = cacheJson['ocrSource'] as String?;
      final ocrCompleted = cacheJson['ocrCompleted'] as bool?;
      return _summarizeOcrPages(
        pages,
        ocrSource: ocrSource,
        ocrCompleted: ocrCompleted,
        hasOriginalMokuroBackup: hasOriginalMokuroBackup,
      );
    } catch (_) {
      return _MangaOcrCacheSummary(
        totalPages: 0,
        pagesWithOcr: 0,
        pagesWithoutOcr: 0,
        pagesNeedingWordSegmentation: 0,
        hasOriginalMokuroBackup: hasOriginalMokuroBackup,
      );
    }
  }

  _MangaOcrCacheSummary _summarizeOcrPages(
    List<dynamic> pages, {
    String? ocrSource,
    bool? ocrCompleted,
    bool hasOriginalMokuroBackup = false,
  }) {
    var pagesWithOcr = 0;
    var pagesWithoutOcr = 0;
    var pagesNeedingWordSegmentation = 0;
    final isOcrCompleted = ocrCompleted ?? ocrSource != null;

    for (final pageData in pages) {
      if (pageData is! Map) continue;
      final blocks = pageData['blocks'] as List<dynamic>? ?? const [];
      if (blocks.isEmpty) {
        if (!isOcrCompleted) {
          pagesWithoutOcr++;
        }
        continue;
      }

      pagesWithOcr++;
      final pageNeedsWordSegmentation = blocks.any((blockData) {
        if (blockData is! Map) return false;
        final lines = blockData['lines'] as List<dynamic>? ?? const [];
        final words = blockData['words'] as List<dynamic>? ?? const [];
        return lines.isNotEmpty && words.isEmpty;
      });
      if (pageNeedsWordSegmentation) {
        pagesNeedingWordSegmentation++;
      }
    }

    return _MangaOcrCacheSummary(
      totalPages: pages.length,
      pagesWithOcr: pagesWithOcr,
      pagesWithoutOcr: pagesWithoutOcr,
      pagesNeedingWordSegmentation: pagesNeedingWordSegmentation,
      ocrSource: ocrSource,
      ocrCompleted: isOcrCompleted,
      hasOriginalMokuroBackup: hasOriginalMokuroBackup,
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.libraryDeleteBookTitle),
        content: Text(context.l10n.libraryDeleteBookBody(title: book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final container = ProviderScope.containerOf(context);
              container.read(bookImportProvider.notifier).deleteBook(book.id);
            },
            child: Text(
              context.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
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
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final enableSensorTilt =
        (Platform.isAndroid || Platform.isIOS) && routeIsCurrent;
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

class _CollectionFolderTile extends StatelessWidget {
  const _CollectionFolderTile({
    super.key,
    required this.collection,
    required this.books,
  });

  final Collection collection;
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Each cover on the face flies to its own place in the opened grid,
    // the way an iOS folder's icons do. Morphing the face into the grid
    // as one unit can't help jumping, because the two are different
    // layouts with no item-to-item correspondence.
    return GestureDetector(
      onTap: () {
        AppHaptics.light();
        Navigator.of(context).push(_folderRoute(collection.id));
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
              child: _FolderPreview(books: books, collectionId: collection.id),
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
/// default route slides the page, which fights the flights.
Route<void> _folderRoute(int collectionId) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) =>
        CollectionFolderScreen(collectionId: collectionId),
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
    ref.read(collectionRepositoryProvider).reorderCollectionBooks(
      collectionId,
      [for (final b in next) b.id],
    );
  }

  Future<void> _removeSelectedFromFolder() async {
    if (_selectedIds.length > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            context.l10n.libraryRemoveFromFolderConfirmTitle(
              count: _selectedIds.length,
            ),
          ),
          content: Text(context.l10n.libraryRemoveFromFolderConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.l10n.commonRemove),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(collectionRepositoryProvider).removeBooksFromCollection(
      collectionId,
      {..._selectedIds},
    );
    if (mounted) _exitSelectionMode();
  }

  Widget _tile(List<Book> members, int index, Animation<double> route) {
    // ReorderableBuilder asserts a ValueKey on every direct child, so the
    // key must sit on the outermost widget returned here.
    final key = ValueKey('book-tile-${members[index].id}');
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
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                itemCount: members.length,
                itemBuilder: (context, index) =>
                    itemBuilder(_tile(members, index, routeAnimation), index),
              ),
            ),
    );
  }
}
