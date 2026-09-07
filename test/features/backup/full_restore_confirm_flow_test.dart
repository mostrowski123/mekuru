import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/presentation/widgets/full_restore_confirm_flow.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';

import '../../test_app.dart';

/// The full restore deletes everything in Mekuru on the device, so it is
/// gated by two dialogs: a review of what is in the file and on the device,
/// then a destructive confirmation that stays disabled until acknowledged.
void main() {
  final l10n = AppLocalizationsEn();

  FullBackupPreview preview({int externalManga = 0}) => FullBackupPreview(
    manifest: FullBackupManifest(
      format: 1,
      appVersion: '1.37.0',
      schemaVersion: AppDatabase.latestSchemaVersion,
      createdAt: DateTime.utc(2026, 9, 1, 12),
      appSupportPath: '/old',
      bookCount: 7,
      dictionaryCount: 3,
      externalMangaCount: externalManga,
      dbBytes: 1000,
      booksBytes: 4000,
      entryCount: 20,
    ),
    sizeBytes: 3 * 1024 * 1024,
    currentBookCount: 2,
    currentDictionaryCount: 1,
  );

  Future<List<bool>> pumpFlow(
    WidgetTester tester, {
    FullBackupPreview? withPreview,
  }) async {
    final results = <bool>[];
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showFullRestoreConfirmFlow(
                  context,
                  withPreview ?? preview(),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return results;
  }

  Finder confirmButton() =>
      find.widgetWithText(FilledButton, l10n.backupFullReplaceConfirm);

  testWidgets('review shows the file and the device, then Continue', (
    tester,
  ) async {
    await pumpFlow(tester, withPreview: preview(externalManga: 2));

    expect(find.text(l10n.backupFullReviewTitle), findsOneWidget);
    expect(find.text(l10n.backupFullReviewInFile), findsOneWidget);
    expect(find.text(l10n.backupFullReviewOnDevice), findsOneWidget);
    expect(find.textContaining('7 books'), findsOneWidget);
    expect(find.textContaining('3 dictionaries'), findsOneWidget);
    expect(find.textContaining('3.0 MB'), findsOneWidget);
    expect(find.textContaining('Mekuru 1.37.0'), findsOneWidget);
    expect(find.textContaining('2 books'), findsOneWidget);
    expect(find.textContaining('1 dictionary'), findsOneWidget);
    expect(
      find.text(l10n.backupFullReviewExternalManga(count: 2)),
      findsOneWidget,
    );
    // The destructive dialog is not on screen yet.
    expect(find.text(l10n.backupFullReplaceTitle), findsNothing);
  });

  testWidgets('no external manga line when there are none', (tester) async {
    await pumpFlow(tester);
    expect(find.textContaining('outside Mekuru'), findsNothing);
  });

  testWidgets('cancelling the review returns false without a second dialog', (
    tester,
  ) async {
    final results = await pumpFlow(tester);

    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(find.text(l10n.backupFullReplaceTitle), findsNothing);
  });

  testWidgets('the destructive button is disabled until acknowledged', (
    tester,
  ) async {
    final results = await pumpFlow(tester);

    await tester.tap(find.text(l10n.backupFullReviewContinue));
    await tester.pumpAndSettle();

    expect(find.text(l10n.backupFullReplaceTitle), findsOneWidget);
    // The destructive dialog spells out what is on THIS device right now.
    expect(find.textContaining('2 books, 1 dictionary'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirmButton()).onPressed, isNull);

    await tester.tap(confirmButton(), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(results, isEmpty);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirmButton()).onPressed, isNotNull);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('cancelling the destructive dialog returns false', (
    tester,
  ) async {
    final results = await pumpFlow(tester);
    await tester.tap(find.text(l10n.backupFullReviewContinue));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  testWidgets('every deletion sentence names Mekuru, never the device', (
    tester,
  ) async {
    await pumpFlow(tester);
    final texts = <String>[];
    void collect() {
      texts.addAll(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? t.textSpan?.toPlainText() ?? ''),
      );
    }

    collect();
    await tester.tap(find.text(l10n.backupFullReviewContinue));
    await tester.pumpAndSettle();
    collect();

    final deletionSentences = texts.where(
      (t) => t.toLowerCase().contains('delet'),
    );
    expect(deletionSentences, isNotEmpty);
    for (final sentence in deletionSentences) {
      expect(sentence, contains('Mekuru'), reason: sentence);
    }
    // Nothing may read as a phone wipe.
    const phoneWipePhrases = [
      "device's data",
      'device will be erased',
      'device will be wiped',
      'erase this device',
      'your phone',
    ];
    for (final text in texts) {
      for (final phrase in phoneWipePhrases) {
        expect(text.toLowerCase(), isNot(contains(phrase)), reason: text);
      }
    }
  });
}
