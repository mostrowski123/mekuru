import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/main.dart' show navigatorKey;

/// [pdf]'s book, after telling the user why its words can't be tapped when
/// it is scanned. For `importPdf(...).then(explainIfScanned)`.
Book explainIfScanned(({Book book, bool scanned}) pdf) {
  if (pdf.scanned) unawaited(showScannedPdfNotice(pdf.book));
  return pdf.book;
}

/// Tells the user why the words of the scanned PDF [book] they just
/// imported can't be tapped, and offers OCR (whose sheet handles Pro)
/// outside Low RAM mode.
/// Free users would otherwise see text PDFs work and scanned ones not,
/// without knowing the difference. Uses the app navigator, so imports that
/// finish after their screen closed (server downloads) still explain.
Future<void> showScannedPdfNotice(Book book) async {
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  final l10n = context.l10n;
  final lowRamMode = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(lowRamModeProvider);
  final runOcr = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.pdfScannedTitle),
      content: Text(l10n.pdfScannedBody(title: book.title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonOk),
        ),
        if (!lowRamMode)
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.ocrRunActionTitle),
          ),
      ],
    ),
  );
  if (runOcr == true && context.mounted) {
    await showOcrActionSheet(context, book);
  }
}
