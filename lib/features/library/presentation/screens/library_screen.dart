import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tilt/flutter_tilt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
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
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Library screen displaying imported books in a grid view.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Load persisted sort order on first build.
    ref.read(librarySortProvider.notifier).loadPersistedSort();

    final booksAsync = ref.watch(booksProvider);
    final importState = ref.watch(bookImportProvider);
    final sortOrder = ref.watch(librarySortProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => _showHelpDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort: ${librarySortLabel(sortOrder)}',
            onPressed: () {
              AppHaptics.light();
              _showSortPicker(context, ref, sortOrder);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: importState.isImporting
            ? null
            : () => _showImportChoice(context, ref),
        tooltip: 'Import',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (importState.isImporting)
            LinearProgressIndicator(value: importState.progress),
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
              onDismiss: () =>
                  ref.read(bookImportProvider.notifier).clearState(),
            ),
          Expanded(
            child: booksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (books) {
                if (books.isEmpty) return _buildEmptyState(context);
                return _buildBookGrid(context, ref, books);
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

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Your library is empty',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to import a book',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookGrid(BuildContext context, WidgetRef ref, List<Book> books) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) => _BookTile(book: books[index]),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supported Media'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // EPUB section
              Text('EPUB Books', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Standard .epub files are supported. Tap the + button '
                'and select "Import EPUB" to add one from your device.',
              ),
              const SizedBox(height: 16),

              // Mokuro Manga section
              Text(
                'Mokuro Manga',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Import manga by selecting a folder, then choosing a '
                '.mokuro or .html file. '
                'The page images are loaded from a sibling folder '
                'with the same name.',
              ),
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
                  '    ├── 001.jpg\n'
                  '    └── ...\n'
                  '\n'
                  'Legacy format:\n'
                  '  manga_title.html    <-- or choose this\n'
                  '  manga_title/\n'
                  '    ├── 001.jpg\n'
                  '    └── ...\n'
                  '  _ocr/manga_title/\n'
                  '    ├── 001.json\n'
                  '    └── ...',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The .mokuro file is generated by the mokuro tool, '
                'which runs OCR on manga pages to extract Japanese text.',
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://github.com/kha-white/mokuro');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  'Learn how to create .mokuro files →',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
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
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Sort by',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final order in LibrarySortOrder.values)
              ListTile(
                leading: Icon(_sortIcon(order)),
                title: Text(librarySortLabel(order)),
                trailing: order == currentOrder
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  AppHaptics.medium();
                  ref.read(librarySortProvider.notifier).setSortOrder(order);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  static IconData _sortIcon(LibrarySortOrder order) => switch (order) {
    LibrarySortOrder.dateAdded => Icons.calendar_today,
    LibrarySortOrder.lastRead => Icons.schedule,
    LibrarySortOrder.alphabetical => Icons.sort_by_alpha,
  };

  void _showImportChoice(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Import',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.book),
              title: const Text('EPUB'),
              subtitle: const Text('Import an EPUB file'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _importEpub(ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Manga (Mokuro)'),
              subtitle: const Text('Select a folder with .mokuro OCR data'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _importManga(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections),
              title: const Text('Manga (CBZ)'),
              subtitle: const Text('Import a .cbz comic book archive'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _importCbz(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importEpub(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    ref.read(bookImportProvider.notifier).importEpub(filePath);
  }

  Future<void> _importCbz(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cbz'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    final book = await ref
        .read(bookImportProvider.notifier)
        .importCbz(filePath);
    if (book != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Imported without OCR. To get text overlays, import external OCR output (e.g. .mokuro).',
          ),
        ),
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
        const SnackBar(
          content: Text(
            'No .mokuro or .html files found in the selected folder.',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final selectedName = await _showMangaManifestPickerSheet(
      context,
      files: candidates,
      folderLabel: _folderLabelFromTreeDocumentId(folder.treeDocumentId),
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
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select manga folder',
    );
    if (dirPath == null || dirPath.isEmpty) return;

    final dir = Directory(dirPath);
    List<FileSystemEntity> entities;
    try {
      entities = await dir.list().toList();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not read folder:\n$e')));
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
        const SnackBar(
          content: Text(
            'No .mokuro or .html files found in the selected folder.',
          ),
        ),
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

  String _folderLabelFromTreeDocumentId(String? documentId) {
    if (documentId == null || documentId.isEmpty) return 'Selected folder';
    final afterColon = documentId.contains(':')
        ? documentId.split(':').last
        : documentId;
    final normalized = afterColon.replaceAll('\\', '/');
    final base = normalized.isEmpty ? documentId : p.posix.basename(normalized);
    return base.isEmpty ? 'Selected folder' : base;
  }

  Future<String?> _showMangaManifestPickerSheet(
    BuildContext context, {
    required List<String> files,
    required String folderLabel,
  }) {
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
              subtitle: Text(
                '${files.length} manga file${files.length == 1 ? '' : 's'} found',
              ),
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

  const _MangaOcrCacheSummary({
    required this.totalPages,
    required this.pagesWithOcr,
    required this.pagesWithoutOcr,
    required this.pagesNeedingWordSegmentation,
    this.ocrSource,
  });

  static const empty = _MangaOcrCacheSummary(
    totalPages: 0,
    pagesWithOcr: 0,
    pagesWithoutOcr: 0,
    pagesNeedingWordSegmentation: 0,
  );

  bool get isMokuroSource => ocrSource == 'mokuro';
  bool get hasPartialOcr =>
      !isMokuroSource && pagesWithOcr > 0 && pagesWithoutOcr > 0;
  bool get hasCompleteOcr =>
      totalPages > 0 && (isMokuroSource || pagesWithoutOcr == 0);
  bool get needsWordSegmentation => pagesNeedingWordSegmentation > 0;
}

/// Individual book tile for the grid.
class _BookTile extends ConsumerStatefulWidget {
  const _BookTile({required this.book});

  final Book book;

  @override
  ConsumerState<_BookTile> createState() => _BookTileState();
}

class _BookTileState extends ConsumerState<_BookTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;
  late final StreamController<TiltStreamModel> _tiltStreamController;

  // Track pointer for tap vs long-press detection
  Offset? _pointerDownPosition;
  Timer? _longPressTimer;
  bool _longPressFired = false;

  // Key to find the Tilt widget's render box for coordinate conversion
  final _tiltKey = GlobalKey();

  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    _tiltStreamController = StreamController<TiltStreamModel>.broadcast();
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
    _tiltStreamController.close();
    _scaleController.dispose();
    super.dispose();
  }

  void _onPressDown() => _scaleController.forward();
  void _onPressUp() => _scaleController.reverse();

  /// Convert a global position to local coordinates relative to the Tilt widget.
  Offset? _toTiltLocal(Offset globalPosition) {
    final renderBox = _tiltKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    return renderBox.globalToLocal(globalPosition);
  }

  void _handlePointerDown(PointerDownEvent e) {
    _pointerDownPosition = e.localPosition;
    _longPressFired = false;
    _onPressDown();

    // Send initial touch position to tilt
    final local = _toTiltLocal(e.position);
    if (local != null) {
      _tiltStreamController.add(
        TiltStreamModel(
          position: local,
          gesturesType: GesturesType.controller,
          gestureUse: true,
        ),
      );
    }

    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      _longPressFired = true;
      AppHaptics.heavy();
      _showBookOptions(context, ref);
      _onPressUp();
      // Release tilt on long press
      final local = _toTiltLocal(e.position);
      if (local != null) {
        _tiltStreamController.add(
          TiltStreamModel(
            position: local,
            gesturesType: GesturesType.controller,
            gestureUse: false,
          ),
        );
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent e) {
    // Update tilt position as finger moves
    final local = _toTiltLocal(e.position);
    if (local != null) {
      _tiltStreamController.add(
        TiltStreamModel(
          position: local,
          gesturesType: GesturesType.controller,
          gestureUse: true,
        ),
      );
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    _longPressTimer?.cancel();
    _onPressUp();

    // Release tilt
    final local = _toTiltLocal(e.position);
    if (local != null) {
      _tiltStreamController.add(
        TiltStreamModel(
          position: local,
          gesturesType: GesturesType.controller,
          gestureUse: false,
        ),
      );
    }

    if (_longPressFired) return;

    // Check it was a tap (not a drag)
    final downPos = _pointerDownPosition;
    if (downPos != null) {
      final distance = (e.localPosition - downPos).distance;
      if (distance < 20) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => book.bookType == 'manga'
                ? MangaReaderScreen(book: book)
                : ReaderScreen(book: book),
          ),
        );
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent e) {
    _longPressTimer?.cancel();
    _onPressUp();

    // Release tilt
    final local = _toTiltLocal(e.position);
    if (local != null) {
      _tiltStreamController.add(
        TiltStreamModel(
          position: local,
          gesturesType: GesturesType.controller,
          gestureUse: false,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enableSensorTilt = Platform.isAndroid || Platform.isIOS;
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Tilt(
                key: _tiltKey,
                tiltStreamController: _tiltStreamController,
                tiltConfig: TiltConfig(
                  angle: 15.0,
                  enableReverse: true,
                  enableGestureTouch: false,
                  enableGestureSensors: enableSensorTilt,
                  sensorFactor: 5.0,
                  enableRevert: true,
                  controllerLeaveDuration: Duration(milliseconds: 400),
                  leaveCurve: Curves.easeOutBack,
                ),
                lightConfig: const LightConfig(
                  minIntensity: 0.0,
                  maxIntensity: 0.14,
                ),
                shadowConfig: ShadowConfig(
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
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCoverImage(theme),
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
                                widthFactor: book.readProgress.clamp(0.0, 1.0),
                                child: Container(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        if (book.bookType == 'manga')
                          OcrProgressOverlay(bookId: book.id),
                      ],
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

  Widget _buildCoverImage(ThemeData theme) {
    final coverPath = book.coverImagePath;
    if (coverPath != null) {
      if (AndroidSafService.isContentUri(coverPath)) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AndroidSafImage(
                uri: coverPath,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildPlaceholder(theme),
              ),
            ),
            AndroidSafImage(
              uri: coverPath,
              fit: BoxFit.fitHeight,
              errorBuilder: (_, _, _) => _buildPlaceholder(theme),
            ),
          ],
        );
      }

      final coverFile = File(coverPath);
      if (coverFile.existsSync()) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Blurred background fill (no darkening)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Image.file(coverFile, fit: BoxFit.cover),
            ),
            // Actual cover, fit by height first
            Image.file(
              coverFile,
              fit: BoxFit.fitHeight,
              errorBuilder: (_, _, _) => _buildPlaceholder(theme),
            ),
          ],
        );
      }
    }
    return _buildPlaceholder(theme);
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                book.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookOptions(BuildContext context, WidgetRef ref) {
    final ocrSummaryFuture = book.bookType == 'manga'
        ? _loadMangaOcrSummary()
        : null;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(book.title),
              subtitle: Text('Added ${_formatDate(book.dateAdded)}'),
            ),
            const Divider(),
            // Bookmarks/highlights are EPUB-only features
            if (book.bookType != 'manga') ...[
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: const Text('Bookmarks'),
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
                    title: const Text('Highlights'),
                    trailing: isProUnlocked
                        ? null
                        : TextButton(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _openProUpgrade(context);
                            },
                            child: const Text('Unlock'),
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
            ],
            // Manga-only features
            if (book.bookType == 'manga') ...[
              FutureBuilder<_MangaOcrCacheSummary>(
                future: ocrSummaryFuture,
                builder: (ctx, snapshot) {
                  final summary = snapshot.data ?? _MangaOcrCacheSummary.empty;
                  final isRunning = ref.watch(isOcrRunningProvider(book.id));
                  final progress = ref.watch(ocrProgressProvider(book.id));
                  final completedPages = progress.whenOrNull(
                    data: (p) => p?.completed,
                  );
                  final totalPages = progress.whenOrNull(data: (p) => p?.total);
                  final isProUnlocked = proUnlockedValue(
                    ref.watch(proUnlockedProvider),
                  );

                  final hasCompleteOcr =
                      summary.hasCompleteOcr && !summary.needsWordSegmentation;
                  final canResume = summary.hasPartialOcr;
                  final isWordOnlyPass =
                      summary.needsWordSegmentation &&
                      summary.pagesWithoutOcr == 0;
                  final isMokuroComplete = summary.isMokuroSource && !isRunning;
                  final needsProUnlock =
                      !isRunning &&
                      !hasCompleteOcr &&
                      !isWordOnlyPass &&
                      !isMokuroComplete;
                  final isProLocked = needsProUnlock && !isProUnlocked;

                  final title = isRunning
                      ? 'Cancel OCR'
                      : isMokuroComplete
                      ? 'Replace OCR'
                      : hasCompleteOcr
                      ? 'Remove OCR'
                      : 'Run OCR';
                  final subtitle = isProLocked
                      ? 'Unlock Pro to use your custom OCR server'
                      : isRunning
                      ? 'Stop processing and save progress'
                      : isMokuroComplete
                      ? 'Replace Mokuro OCR with your custom OCR server'
                      : hasCompleteOcr
                      ? 'Remove OCR text from all pages'
                      : isWordOnlyPass
                      ? 'Build word tap targets from saved OCR'
                      : canResume
                      ? 'Resume OCR (${completedPages ?? summary.pagesWithOcr}/${totalPages ?? summary.totalPages} done)'
                      : 'Recognize text on all pages';

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        enabled: !isProLocked,
                        leading: Icon(
                          isRunning
                              ? Icons.cancel_outlined
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
                                child: const Text('Unlock'),
                              )
                            : null,
                        onTap: isProLocked
                            ? null
                            : () {
                                Navigator.of(sheetContext).pop();
                                if (isRunning) {
                                  _cancelOcr(context, ref);
                                  return;
                                }
                                if (isMokuroComplete) {
                                  _replaceOcrForMokuro(context, ref);
                                  return;
                                }
                                if (hasCompleteOcr) {
                                  _removeOcr(context, ref);
                                  return;
                                }
                                _startOcr(context, ref);
                              },
                      ),
                      if (isMokuroComplete)
                        ListTile(
                          leading: const Icon(Icons.delete_sweep_outlined),
                          title: const Text('Remove OCR'),
                          subtitle: const Text(
                            'Remove OCR text from all pages',
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _removeOcr(context, ref);
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                AppHaptics.light();
                Navigator.of(sheetContext).pop();
                _showRenameDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Change Cover'),
              onTap: () {
                AppHaptics.light();
                Navigator.of(sheetContext).pop();
                _changeCover(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete Book',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(context);
              },
            ),
          ],
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
        title: const Text('Rename Book'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty && newTitle != book.title) {
                ref.read(bookRepositoryProvider).updateTitle(book.id, newTitle);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCover(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final pickedPath = result.files.single.path;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to change cover: $e')));
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
          const SnackBar(content: Text('No pages cache found for this book')),
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
    final summary = _summarizeOcrPages(pages, ocrSource: ocrSource);
    final emptyCount = summary.pagesWithoutOcr;
    final isWordOnlyPass = emptyCount == 0 && summary.needsWordSegmentation;

    if (emptyCount == 0 && !summary.needsWordSegmentation) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'OCR is already complete. Use "Remove OCR" to reset.',
            ),
          ),
        );
      }
      return;
    }

    if (!isWordOnlyPass && imageDirPath.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manga image directory not found')),
        );
      }
      return;
    }

    // Confirm with user
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isWordOnlyPass ? 'Build Word Overlays' : 'Run OCR'),
        content: Text(
          isWordOnlyPass
              ? 'OCR text already exists. This will rebuild word tap targets '
                    'so lookup overlays appear correctly.'
              : 'This will process $emptyCount pages. OCR will run in the '
                    'background and continue even if you close the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isWordOnlyPass ? 'Process' : 'Start'),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Unable to prepare OCR: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start OCR: $e')));
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
                ? 'Word overlay processing started in background'
                : 'OCR started in background',
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
        title: const Text('Replace OCR'),
        content: const Text(
          'This will overwrite the OCR data imported from the Mokuro/HTML file '
          'and re-run OCR on ALL pages using your custom server.\n\n'
          'To restore the original OCR, re-import the book.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Replace'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to prepare OCR: $e')));
      }
      return;
    }

    // Clear all OCR blocks and reset ocrSource so the worker processes every page
    final cacheFilePath = p.join(book.filePath, 'pages_cache.json');
    final cacheFile = File(cacheFilePath);
    if (!cacheFile.existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pages cache found for this book')),
        );
      }
      return;
    }

    try {
      final cacheJson =
          json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
      final mokuroBook = MokuroBook.fromJson(cacheJson);
      final imageDirPath = mokuroBook.imageDirPath;

      final clearedPages = mokuroBook.pages
          .map((page) => page.copyWith(blocks: const []))
          .toList();
      final cleared = MokuroBook(
        title: mokuroBook.title,
        imageDirPath: mokuroBook.imageDirPath,
        safTreeUri: mokuroBook.safTreeUri,
        safImageDirRelativePath: mokuroBook.safImageDirRelativePath,
        autoCropVersion: mokuroBook.autoCropVersion,
        ocrSource: null,
        pages: clearedPages,
      );
      await cacheFile.writeAsString(json.encode(cleared.toJson()));

      await scheduleOcrTask(
        bookId: book.id,
        cacheFilePath: cacheFilePath,
        imageDir: imageDirPath,
      );

      ref.invalidate(ocrProgressProvider(book.id));
      ref.invalidate(mangaPagesProvider(book.id));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OCR replacement started in background'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start OCR: $e')));
      }
    }
  }

  void _cancelOcr(BuildContext context, WidgetRef ref) async {
    await cancelOcrTask(book.id);

    // Invalidate to pick up the cancelled status
    ref.invalidate(ocrProgressProvider(book.id));
    ref.invalidate(mangaPagesProvider(book.id));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OCR cancelled. Progress saved.')),
      );
    }
  }

  void _removeOcr(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove OCR'),
        content: const Text(
          'Remove OCR text and word overlays from this manga? '
          'You can run OCR again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await clearOcrTaskState(book.id);
      await ref.read(bookRepositoryProvider).clearMangaOcr(book);
      ref.invalidate(mangaPagesProvider(book.id));
      ref.invalidate(ocrProgressProvider(book.id));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR removed from this book')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove OCR: $e')));
      }
    }
  }

  Future<_MangaOcrCacheSummary> _loadMangaOcrSummary() async {
    final cacheFilePath = p.join(book.filePath, 'pages_cache.json');
    final cacheFile = File(cacheFilePath);
    if (!await cacheFile.exists()) {
      return _MangaOcrCacheSummary.empty;
    }

    try {
      final cacheJson =
          json.decode(await cacheFile.readAsString()) as Map<String, dynamic>;
      final pages = cacheJson['pages'] as List<dynamic>? ?? [];
      final ocrSource = cacheJson['ocrSource'] as String?;
      return _summarizeOcrPages(pages, ocrSource: ocrSource);
    } catch (_) {
      return _MangaOcrCacheSummary.empty;
    }
  }

  _MangaOcrCacheSummary _summarizeOcrPages(
    List<dynamic> pages, {
    String? ocrSource,
  }) {
    var pagesWithOcr = 0;
    var pagesWithoutOcr = 0;
    var pagesNeedingWordSegmentation = 0;

    for (final pageData in pages) {
      if (pageData is! Map) continue;
      final blocks = pageData['blocks'] as List<dynamic>? ?? const [];
      if (blocks.isEmpty) {
        pagesWithoutOcr++;
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
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Book'),
        content: Text('Delete "${book.title}" from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final container = ProviderScope.containerOf(context);
              container.read(bookImportProvider.notifier).deleteBook(book.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
