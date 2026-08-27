import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/epub_file_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_setting_segments.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/blocking_progress_dialog.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Coverage dialog → progress dialog → off-isolate rebuild → SAF save-as.
/// Everything user-facing (cancel, MeCab down, failure) ends in a SnackBar;
/// cancel is silent.
Future<void> runFuriganaExport(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  final choice = await _showCoverageDialog(
    context,
    initialLevel: ref.read(readerSettingsProvider).furiganaJlptLevel,
  );
  if (choice == null || !context.mounted) return;
  final (exportMode, exportLevel) = choice;

  showBlockingProgressDialog(context, l10n.libraryExportFuriganaProgress);

  final exportAttrs = <String, Object>{
    'mode': exportMode.name,
    'jlpt_level': exportLevel,
  };
  Object? failure;
  Uint8List? bytes;
  try {
    bytes = await tracedOperation(
      'furigana_export.build_duration_ms',
      attributes: exportAttrs,
      action: () async {
        final epubPath = await EpubFileResolver().resolveLocalEpubPath(
          book.filePath,
        );
        return MecabService.instance.runOffIsolate(
          () => buildFuriganaEpubForMode(
            epubPath,
            mode: exportMode,
            jlptLevel: exportLevel,
          ),
        );
      },
    );
  } catch (e, st) {
    Sentry.captureException(e, stackTrace: st);
    failure = e;
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // spinner

  if (failure != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.commonErrorWithDetails(details: failure.toString())),
      ),
    );
    return;
  }
  if (bytes == null) {
    // Null is the load-bearing "MeCab could not come up" signal — never
    // silently save an unannotated book.
    logUsage('furigana_export.unavailable');
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.libraryExportFuriganaUnavailable)),
    );
    return;
  }

  // No type/allowedExtensions: OEM pickers choke on custom extension
  // filtering (see BackupFileManager); the .epub suffix is what matters.
  final savedPath = await FilePicker.saveFile(
    dialogTitle: l10n.libraryExportFuriganaSaveTitle,
    fileName: exportFileName(book.title),
    bytes: bytes,
  );
  if (savedPath != null) {
    logUsage('furigana_export.completed', attrs: exportAttrs);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.libraryExportFuriganaDone)),
    );
  }
}

Future<(FuriganaMode, int)?> _showCoverageDialog(
  BuildContext context, {
  required int initialLevel,
}) {
  final l10n = context.l10n;
  var mode = FuriganaMode.all;
  var level = initialLevel;
  return showDialog<(FuriganaMode, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        RadioListTile<FuriganaMode> option(FuriganaMode value, String label) {
          return RadioListTile<FuriganaMode>(
            value: value,
            title: Text(label),
            contentPadding: EdgeInsets.zero,
          );
        }

        return AlertDialog(
          title: Text(l10n.libraryExportFuriganaDialogTitle),
          content: RadioGroup<FuriganaMode>(
            groupValue: mode,
            onChanged: (chosen) => setState(() => mode = chosen!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                option(FuriganaMode.all, l10n.readerFuriganaAllKanji),
                option(
                  FuriganaMode.aboveLevel,
                  l10n.libraryExportFuriganaAboveLevel,
                ),
                if (mode == FuriganaMode.aboveLevel)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 8),
                    child: SegmentedButton<int>(
                      segments: furiganaJlptLevelSegments(),
                      selected: {level},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          setState(() => level = selection.single),
                    ),
                  ),
                option(FuriganaMode.book, l10n.libraryExportFuriganaMatchBook),
                option(FuriganaMode.hide, l10n.libraryExportFuriganaNone),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop((mode, level)),
              child: Text(l10n.libraryExportFuriganaAction),
            ),
          ],
        );
      },
    ),
  );
}

/// A book title with filesystem-hostile characters replaced, truncated to a
/// sane length — the base name for any exported file.
String sanitizedExportBaseName(String title) {
  var sanitized = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (sanitized.length > 80) sanitized = sanitized.substring(0, 80).trim();
  if (sanitized.isEmpty) sanitized = 'book';
  return sanitized;
}

/// Suggested save-dialog name for the furigana EPUB export.
String exportFileName(String title) =>
    '${sanitizedExportBaseName(title)} (furigana).epub';
