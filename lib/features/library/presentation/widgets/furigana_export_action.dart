// ignore_for_file: unawaited_futures
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/platform/file_pick.dart';
import 'package:mekuru/core/services/sentry_helpers.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/services/epub_furigana_export.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/epub_file_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_setting_segments.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/blocking_progress_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Coverage dialog → progress dialog → off-isolate rebuild into a temp file
/// → system save dialog. Everything user-facing (MeCab down, failure) ends
/// in a SnackBar; cancel is silent. The temp file never outlives the call.
Future<void> runFuriganaExport(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  final choice = await showFuriganaCoverageDialog(
    context,
    initialLevel: ref.read(readerSettingsProvider).furiganaJlptLevel,
    offerWanikani: ref.read(wanikaniProvider).hasKanji,
  );
  if (choice == null || !context.mounted) return;
  final (exportMode, exportLevel) = choice;
  final knownKanji = ref.read(wanikaniKnownKanjiProvider);
  // Named as the user will see it: on iOS the save dialog moves this file.
  final outPath = p.join(
    (await getTemporaryDirectory()).path,
    exportFileName(book.title),
  );
  if (!context.mounted) return;

  showBlockingProgressDialog(context, l10n.libraryExportFuriganaProgress);

  final exportAttrs = <String, Object>{
    'mode': exportMode.name,
    'jlpt_level': exportLevel,
  };
  try {
    Object? failure;
    var written = false;
    try {
      written = await tracedOperation(
        'furigana_export.build_duration_ms',
        attributes: exportAttrs,
        action: () async {
          final epubPath = await EpubFileResolver().resolveLocalEpubPath(
            book.filePath,
          );
          return MecabService.instance.runOffIsolate(
            () => writeFuriganaEpubForMode(
              epubPath,
              outPath,
              mode: exportMode,
              jlptLevel: exportLevel,
              knownKanji: knownKanji,
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
        SnackBar(content: Text(l10n.commonExportFailed(format: 'EPUB'))),
      );
      return;
    }
    if (!written) {
      // False is the load-bearing "MeCab could not come up" signal — never
      // silently save an unannotated book.
      logUsage('furigana_export.unavailable');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.libraryExportFuriganaUnavailable)),
      );
      return;
    }

    try {
      switch (await saveFile(outPath, mimeType: 'application/epub+zip')) {
        case FileDialogDone():
          logUsage('furigana_export.completed', attrs: exportAttrs);
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.libraryExportFuriganaDone)),
          );
        case FileDialogFailed(:final failure):
          messenger.showSnackBar(
            SnackBar(content: Text(failure.message(l10n))),
          );
        case FileDialogCancelled():
      }
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonExportFailed(format: 'EPUB'))),
      );
    }
  } finally {
    try {
      await File(outPath).delete();
    } on FileSystemException {
      // Never written, or already gone with the save.
    }
  }
}

/// Picks the export coverage: the returned tuple is the mode plus the JLPT
/// level (meaningful for aboveLevel only). [offerWanikani] adds the WaniKani
/// option; it is hidden until kanji stages have been synced because an
/// empty known set would just export every kanji annotated.
@visibleForTesting
Future<(FuriganaMode, int)?> showFuriganaCoverageDialog(
  BuildContext context, {
  required int initialLevel,
  bool offerWanikani = false,
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
                if (offerWanikani)
                  option(
                    FuriganaMode.wanikani,
                    l10n.libraryExportFuriganaWanikani,
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

/// A book title with filesystem-hostile characters replaced, cut to 80
/// characters and 200 bytes — the base name for any exported file. A file
/// name holds 255 bytes and a kana or kanji takes three, so 80 of them plus
/// " (furigana).epub" did not fit.
String sanitizedExportBaseName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final kept = StringBuffer();
  var bytes = 0;
  for (final rune in cleaned.runes.take(80)) {
    bytes += utf8.encode(String.fromCharCode(rune)).length;
    if (bytes > 200) break;
    kept.writeCharCode(rune);
  }
  final sanitized = kept.toString().trim();
  return sanitized.isEmpty ? 'book' : sanitized;
}

/// Suggested save-dialog name for the furigana EPUB export.
String exportFileName(String title) =>
    '${sanitizedExportBaseName(title)} (furigana).epub';
