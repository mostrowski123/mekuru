import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';

/// A book's cover image with a blurred background fill, falling back to a
/// titled placeholder when the cover is missing or fails to decode.
///
/// Handles both Android SAF content URIs and plain file paths, and decodes
/// at the laid-out width to keep memory usage bounded.
class BookCoverImage extends StatelessWidget {
  const BookCoverImage({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverPath = book.coverImagePath;
    if (coverPath == null) return _buildPlaceholder(theme);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final tileCacheWidth = (constraints.maxWidth * dpr).toInt();
        // Blurred background can decode at half resolution — blur hides
        // detail loss and saves ~75% memory per blurred image.
        final blurCacheWidth = (tileCacheWidth * 0.5).toInt();

        if (AndroidSafService.isContentUri(coverPath)) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AndroidSafImage(
                  uri: coverPath,
                  fit: BoxFit.cover,
                  cacheWidth: blurCacheWidth,
                  errorBuilder: (_, _, _) => _buildPlaceholder(theme),
                ),
              ),
              AndroidSafImage(
                uri: coverPath,
                fit: BoxFit.fitHeight,
                cacheWidth: tileCacheWidth,
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
                child: Image.file(
                  coverFile,
                  fit: BoxFit.cover,
                  cacheWidth: blurCacheWidth,
                ),
              ),
              // Actual cover, fit by height first
              Image.file(
                coverFile,
                fit: BoxFit.fitHeight,
                cacheWidth: tileCacheWidth,
                errorBuilder: (_, _, _) => _buildPlaceholder(theme),
              ),
            ],
          );
        }

        return _buildPlaceholder(theme);
      },
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Icon + title need a grid tile's worth of height. Folder
          // previews and the folder app-bar thumbnail render covers far
          // smaller, where the title would overflow — drop it and scale
          // the icon there. Full-size tiles are unaffected.
          final showTitle = constraints.maxHeight >= 96;
          final iconSize = showTitle
              ? 32.0
              : (constraints.maxHeight * 0.4).clamp(10.0, 32.0);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.menu_book,
                  size: iconSize,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                if (showTitle) ...[
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
              ],
            ),
          );
        },
      ),
    );
  }
}
