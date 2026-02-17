import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tilt/flutter_tilt.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/settings_screen.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:path/path.dart' as p;

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
            icon: const Icon(Icons.add),
            tooltip: 'Import EPUB',
            onPressed: importState.isImporting ? null : () => _importEpub(ref),
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort: ${librarySortLabel(sortOrder)}',
            onPressed: () {
              AppHaptics.light();
              _showSortPicker(context, ref, sortOrder);
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
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
            'Tap + to import an EPUB',
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
          MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
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
