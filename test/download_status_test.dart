import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/core/services/download_to_file.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/features/dictionary/data/services/dictionary_download_service.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/widgets/download_status.dart';

void main() {
  test('a dictionary download failure is worded for the user', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(dictionaryDownloadError(l10n, null), isNull);
    expect(
      dictionaryDownloadError(l10n, const WifiLostException()),
      'The download stopped because Wi-Fi disconnected. '
      'Tap Download to try again.',
    );
    expect(
      dictionaryDownloadError(
        l10n,
        const DownloadStoppedInBackgroundException(),
      ),
      'The download stopped because Mekuru was in the background. '
      'Tap Download to resume.',
    );
    expect(
      dictionaryDownloadError(
        l10n,
        const InsufficientSpaceException(neededBytes: 500 << 20),
      ),
      'Not enough free space on this device. About 500 MB more is needed.',
    );
    expect(dictionaryDownloadError(l10n, 'boom'), 'Download failed: boom');
  });

  test('download errors are worded once, in the app language', () {
    final es = lookupAppLocalizations(const Locale('es'));

    // Was "Download failed: HttpException: Download failed: HTTP 404, ...".
    expect(
      dictionaryDownloadError(es, const DownloadHttpException(404)),
      'Error al descargar: El servidor devolvió el error 404.',
    );
    expect(
      dictionaryDownloadError(es, const SocketException('refused')),
      es.localOcrDownloadNetwork,
    );
    expect(
      dictionaryDownloadError(es, const ModelVerificationException()),
      es.localOcrDownloadDamaged,
    );
    // What the Gemma worker records.
    expect(
      dictionaryDownloadError(
        es,
        ServerDownloadFailedException(
          serverDownloadErrorCode(const ServerDownloadHttpException(503)),
        ),
      ),
      'Error al descargar: El servidor devolvió el error 503.',
    );
    expect(
      dictionaryDownloadError(
        es,
        const ServerDownloadFailedException(serverDownloadInterruptedError),
      ),
      es.downloadInterrupted,
    );
  });

  testWidgets('a finishing dictionary import shows a moving bar', (
    tester,
  ) async {
    Future<LinearProgressIndicator> show(double progress) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DictionaryDownloadProgress(progress: progress)),
        ),
      );
      return tester.widget(find.byType(LinearProgressIndicator));
    }

    expect((await show(0.8)).value, 0.8);
    expect(find.text('Importing...'), findsOneWidget);

    expect(
      (await show(DictionaryDownloadService.finishingProgress)).value,
      isNull,
    );
    expect(find.text('Finishing up… this may take a minute'), findsOneWidget);
  });
}
