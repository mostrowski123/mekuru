import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/manga/data/services/manga_cbz_export.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/blocking_progress_dialog.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Progress dialog → off-isolate CBZ build → share sheet → SnackBar.
/// Dismissing the share sheet is silent; failures end in a SnackBar.
Future<void> runMangaCbzExport(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  showBlockingProgressDialog(context, l10n.libraryExportCbzProgress);

  Object? failure;
  StackTrace? failureStack;
  String? cbzPath;
  var pageCount = 0;
  try {
    (cbzPath, pageCount) = await tracedOperation(
      'manga_cbz_export.build_duration_ms',
      action: () => ref
          .read(bookRepositoryProvider)
          .exportMangaCbz(
            book,
            fileName: '${sanitizedExportBaseName(book.title)}.cbz',
          ),
    );
  } catch (e, st) {
    failure = e;
    failureStack = st;
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // spinner

  if (failure != null || cbzPath == null) {
    final message = switch (failure) {
      EmptyMangaExportException() => l10n.libraryExportCbzEmpty,
      SafMangaExportUnsupportedException() =>
        l10n.libraryExportCbzSafUnsupported,
      _ => l10n.commonErrorWithDetails(details: failure.toString()),
    };
    if (failure is! EmptyMangaExportException &&
        failure is! SafMangaExportUnsupportedException) {
      Sentry.captureException(failure, stackTrace: failureStack);
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return;
  }

  final tmpFile = File(cbzPath);
  try {
    // share_plus copies the file into its own provider cache natively, so
    // the temp file can be deleted as soon as the sheet resolves.
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tmpFile.path, mimeType: 'application/vnd.comicbook+zip')],
      ),
    );
    if (result.status == ShareResultStatus.success) {
      logUsage('manga_cbz_export.completed', attrs: {'pages': pageCount});
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.libraryExportCbzDone)),
      );
    }
  } catch (e, st) {
    Sentry.captureException(e, stackTrace: st);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.commonErrorWithDetails(details: '$e'))),
    );
  } finally {
    try {
      await tmpFile.delete();
    } catch (_) {}
  }
}
