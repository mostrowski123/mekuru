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
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart'
    show describeServerDownloadError;
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download.dart';
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
    // iOS ended its background work.
    expect(
      dictionaryDownloadError(l10n, const DownloadStoppedException()),
      'The download was interrupted. Tap Download to try again.',
    );
    // An archive that doesn't unpack, or UniDic's hash that doesn't match.
    expect(
      dictionaryDownloadError(l10n, const FormatException('bad CRC')),
      'The downloaded file was damaged. Download it again.',
    );
    // Anything else, such as an import that failed, never shows its text.
    for (final failure in [
      'boom',
      StateError('import failed'),
      const ServerDownloadFailedException('FileSystemException: read-only'),
      const ServerDownloadFailedException(''),
    ]) {
      expect(
        dictionaryDownloadError(l10n, failure),
        "The download didn't finish. Try again.",
      );
    }
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
    // A background model download that filled the disk.
    expect(
      dictionaryDownloadError(
        es,
        const ServerDownloadFailedException(serverDownloadStorageFullError),
      ),
      es.localOcrStorageFull,
    );
  });

  test('every failure a download worker has recorded keeps its meaning', () {
    String meaning(String? stored) =>
        switch (RecordedDownloadFailure.parse(stored)) {
          RecordedFailureCode code => code.name,
          RecordedServerStatus(:final status) => 'server($status)',
        };

    // Spelled out, not the constants: these are in status files on disk,
    // written by 1.74.5 and by earlier builds of this version.
    expect(
      {
        for (final stored in [
          'stopped',
          'untrusted_certificate',
          'interrupted',
          'connection_gone',
          'storage_full',
          'server_status:0',
          'server_status:401',
          'server_status:503',
          'server_status:',
          'server_status:abc',
          // An exception's own text (serverDownloadErrorCode), or none.
          'FileSystemException: Cannot open file, path = /data/x',
          'Download failed',
          '',
          null,
        ])
          stored: meaning(stored),
      },
      {
        'stopped': 'stopped',
        'untrusted_certificate': 'untrustedCertificate',
        'interrupted': 'interrupted',
        'connection_gone': 'connectionGone',
        'storage_full': 'storageFull',
        'server_status:0': 'server(0)',
        'server_status:401': 'server(401)',
        'server_status:503': 'server(503)',
        'server_status:': 'other',
        'server_status:abc': 'other',
        'FileSystemException: Cannot open file, path = /data/x': 'other',
        'Download failed': 'other',
        '': 'other',
        null: 'other',
      },
    );
    // What the worker writes parses back.
    expect(
      meaning(serverDownloadErrorCode(const SocketException('refused'))),
      'server(0)',
    );
    expect(
      meaning(serverDownloadErrorCode(const ServerDownloadHttpException(404))),
      'server(404)',
    );
  });

  test('a recorded failure is worded for a model tile and for a server '
      "book's message, which speaks of the book's own server", () {
    final ja = lookupAppLocalizations(const Locale('ja'));
    String tile(String stored) =>
        dictionaryDownloadError(ja, ServerDownloadFailedException(stored))!;

    expect(
      {
        for (final stored in [
          'stopped',
          'untrusted_certificate',
          'interrupted',
          'connection_gone',
          'storage_full',
          'server_status:0',
          'server_status:401',
          'server_status:503',
          'FileSystemException: read-only',
        ])
          stored: (tile(stored), describeServerDownloadError(ja, stored)),
      },
      {
        'stopped': ('ダウンロードが停止しました', 'ダウンロードが停止しました'),
        'untrusted_certificate': (
          ja.serverCertificateUntrusted,
          ja.serverCertificateUntrusted,
        ),
        // A book's message is not beside a Download button.
        'interrupted': (
          'ダウンロードが中断されました。「ダウンロード」をタップして、もう一度お試しください。',
          ja.serverBrowseDownloadInterrupted,
        ),
        'connection_gone': (
          ja.serverErrorConnectionGone,
          'ダウンロードに失敗しました：${ja.serverErrorConnectionGone}',
        ),
        'storage_full': (
          ja.localOcrStorageFull,
          'ダウンロードに失敗しました：${ja.localOcrStorageFull}',
        ),
        // The user typed a book server's address and signed in to it.
        'server_status:0': (
          'ダウンロードで接続できませんでした。インターネット接続を確認して、もう一度お試しください。',
          'ダウンロードに失敗しました：${ja.serverErrorUnreachable}',
        ),
        'server_status:401': (
          'ダウンロードに失敗しました：サーバーがエラー401を返しました。',
          'ダウンロードに失敗しました：${ja.serverErrorSignInRejected}',
        ),
        'server_status:503': (
          'ダウンロードに失敗しました：サーバーがエラー503を返しました。',
          'ダウンロードに失敗しました：サーバーがエラー503を返しました。',
        ),
        // Never the stored text.
        'FileSystemException: read-only': (
          ja.downloadNotFinished,
          ja.downloadNotFinished,
        ),
      },
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
