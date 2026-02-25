import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tilt/flutter_tilt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/screens/manga_reader_screen.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/bookmarks_sheet.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';
import 'package:mekuru/shared/utils/haptics.dart';
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
          if (importState.isImporting) const LinearProgressIndicator(),
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
              Text(
                'EPUB Books',
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
                'Import manga by selecting a .mokuro or .html file. '
                'The page images are loaded from a sibling folder '
                'with the same name.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '.mokuro format:\n'
                  '  manga_title.mokuro  <-- select this\n'
                  '  manga_title/\n'
                  '    ├── 001.jpg\n'
                  '    └── ...\n'
                  '\n'
                  'Legacy format:\n'
                  '  manga_title.html    <-- or this\n'
                  '  manga_title/\n'
                  '    ├── 001.jpg\n'
                  '    └── ...\n'
                  '  _ocr/manga_title/\n'
                  '    ├── 001.json\n'
                  '    └── ...',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
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
                  final uri = Uri.parse(
                    'https://github.com/kha-white/mokuro',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
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
                  ref
                      .read(librarySortProvider.notifier)
                      .setSortOrder(order);
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
              title: const Text('Manga'),
              subtitle: const Text('Import a .mokuro or .html file'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _importManga(context, ref);
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

  Future<void> _importManga(BuildContext context, WidgetRef ref) async {
    // On Android, request storage permission before accessing manga files.
    // MANAGE_EXTERNAL_STORAGE is needed because the image directory
    // referenced by the mokuro/HTML file is accessed via filesystem paths.
    if (Platform.isAndroid) {
      final granted = await _ensureStoragePermission(context);
      if (!granted) return;
    }

    // Use directory picker instead of file picker. On Android, pickFiles()
    // copies the file to a cache directory, losing access to sibling image
    // folders. The directory picker returns the real filesystem path.
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;

    debugPrint('[MangaImport] Selected directory: $dirPath');

    // Scan for .mokuro, .html, and .mobile.html files in the selected directory
    final mangaFiles = <File>[];
    try {
      final allFiles = <File>[];
      await for (final entity in Directory(dirPath).list()) {
        if (entity is File) {
          final lower = entity.path.toLowerCase();
          if (lower.endsWith('.mokuro') || lower.endsWith('.html')) {
            allFiles.add(entity);
          }
        }
      }
      // If both Book.html and Book.mobile.html exist, keep only Book.html
      final nonMobilePaths = allFiles
          .where((f) => !f.path.toLowerCase().endsWith('.mobile.html'))
          .map((f) => f.path.toLowerCase())
          .toSet();
      for (final file in allFiles) {
        final lower = file.path.toLowerCase();
        if (lower.endsWith('.mobile.html')) {
          // Include .mobile.html only if no matching non-mobile .html exists
          final nonMobile =
              '${lower.substring(0, lower.length - '.mobile.html'.length)}.html';
          if (!nonMobilePaths.contains(nonMobile)) {
            mangaFiles.add(file);
          }
        } else {
          mangaFiles.add(file);
        }
      }
    } catch (e) {
      debugPrint('[MangaImport] Cannot list directory: $e');
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot read directory: $e')),
        );
      }
      return;
    }

    if (mangaFiles.isEmpty) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No .mokuro or .html files found in this folder.'),
          ),
        );
      }
      return;
    }

    // Sort by name for consistent ordering
    mangaFiles.sort((a, b) => a.path.compareTo(b.path));

    String selectedFile;
    if (mangaFiles.length == 1) {
      selectedFile = mangaFiles.first.path;
    } else {
      // Let the user pick which file to import
      // ignore: use_build_context_synchronously
      if (!context.mounted) return;
      final picked = await _showMangaFilePicker(context, mangaFiles);
      if (picked == null) return;
      selectedFile = picked;
    }

    debugPrint('[MangaImport] Importing: $selectedFile');
    ref.read(bookImportProvider.notifier).importManga(selectedFile);
  }

  /// Show a bottom sheet to pick which manga file to import.
  Future<String?> _showMangaFilePicker(
    BuildContext context,
    List<File> files,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.4,
        minChildSize: 0.25,
        maxChildSize: 0.7,
        builder: (_, scrollController) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select manga to import',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: files.length,
                  itemBuilder: (_, index) {
                    final file = files[index];
                    final ext = p.extension(file.path).toLowerCase();
                    final icon = ext == '.mokuro'
                        ? Icons.data_object
                        : Icons.code;
                    return ListTile(
                      leading: Icon(icon),
                      title: Text(
                        p.basenameWithoutExtension(file.path),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(ext),
                      onTap: () => Navigator.of(sheetContext).pop(file.path),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Request storage permission on Android.
  ///
  /// Uses [Permission.manageExternalStorage] which gives full filesystem
  /// access. This opens the system settings page where the user toggles
  /// the "Allow access to manage all files" switch.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  Future<bool> _ensureStoragePermission(BuildContext context) async {
    // Check if already granted
    if (await Permission.manageExternalStorage.isGranted) return true;

    // Request the permission (opens system settings on Android 11+)
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // Permission denied — show explanation
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Storage permission is required to read manga files. '
            'Please grant "All files access" in Settings.',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => openAppSettings(),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    return false;
  }
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
    final renderBox =
        _tiltKey.currentContext?.findRenderObject() as RenderBox?;
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
      _tiltStreamController.add(TiltStreamModel(
        position: local,
        gesturesType: GesturesType.controller,
        gestureUse: true,
      ));
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
        _tiltStreamController.add(TiltStreamModel(
          position: local,
          gesturesType: GesturesType.controller,
          gestureUse: false,
        ));
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent e) {
    // Update tilt position as finger moves
    final local = _toTiltLocal(e.position);
    if (local != null) {
      _tiltStreamController.add(TiltStreamModel(
        position: local,
        gesturesType: GesturesType.controller,
        gestureUse: true,
      ));
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    _longPressTimer?.cancel();
    _onPressUp();

    // Release tilt
    final local = _toTiltLocal(e.position);
    if (local != null) {
      _tiltStreamController.add(TiltStreamModel(
        position: local,
        gesturesType: GesturesType.controller,
        gestureUse: false,
      ));
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
      _tiltStreamController.add(TiltStreamModel(
        position: local,
        gesturesType: GesturesType.controller,
        gestureUse: false,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                tiltConfig: const TiltConfig(
                  angle: 15.0,
                  enableReverse: true,
                  enableGestureTouch: false,
                  enableGestureSensors: true,
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
    if (book.coverImagePath != null) {
      final coverFile = File(book.coverImagePath!);
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
              ListTile(
                leading: const Icon(Icons.highlight),
                title: const Text('Highlights'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showBookHighlights(context);
                },
              ),
            ],
            // Manga-only features
            if (book.bookType == 'manga') ...[
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Reprocess OCR'),
                subtitle: const Text('Re-run word segmentation'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _reprocessOcr(context, ref);
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
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
          );
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
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
          );
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
                ref
                    .read(bookRepositoryProvider)
                    .updateTitle(book.id, newTitle);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to change cover: $e')),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _reprocessOcr(BuildContext context, WidgetRef ref) async {
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Expanded(child: Text('Re-running word segmentation…')),
          ],
        ),
      ),
    );

    try {
      final bookRepo = ref.read(bookRepositoryProvider);
      await bookRepo.reprocessMangaOcr(book);

      // Invalidate cached page data so re-entering the reader picks it up
      ref.invalidate(mangaPagesProvider(book.id));

      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR reprocessing complete')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reprocessing failed: $e')),
        );
      }
    }
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
