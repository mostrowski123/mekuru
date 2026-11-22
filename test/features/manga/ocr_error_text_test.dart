import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_client.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/manga/data/services/ocr_failure.dart';
import 'package:mekuru/features/manga/data/services/vision_page_ocr.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/core/platform/network_status.dart'
    show WifiLostException;
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download.dart' show DownloadKind;
import 'package:mekuru/shared/widgets/download_status.dart';

import '../../test_app.dart';

void main() {
  final es = lookupAppLocalizations(const Locale('es'));

  group('a failed remote or iOS OCR run is worded in the app language', () {
    String describe(Object error) =>
        describeOcrFailure(es, ocrErrorCode(error));

    test('server answers', () {
      expect(
        describe(const OcrServerException(401, 'unauthorized')),
        es.ocrErrorAuthFailed,
      );
      expect(
        describe(
          const OcrServerException(403, 'forbidden', code: 'job_forbidden'),
        ),
        es.ocrErrorJobForbidden,
      );
      expect(
        describe(const OcrServerException(503, 'unavailable')),
        'Error del servidor OCR (503). Puede que el servidor no esté '
        'funcionando o esté mal configurado.',
      );
      expect(
        describe(const OcrServerException(418, 'teapot: no')),
        'El servidor OCR devolvió el error 418: teapot: no',
      );
    });

    test('network failures, with no doubled prefix', () {
      expect(
        describe(
          const OcrServerException(0, 'Network error: Connection refused'),
        ),
        es.ocrErrorConnectFailed,
      );
      // The socket's own text ("Broken pipe") is not shown.
      expect(
        describe(const OcrServerException(0, 'Network error: Broken pipe')),
        es.ocrErrorConnectFailed,
      );
    });

    test('Apple Vision failing is not a server error', () {
      expect(
        describe(const TextRecognitionException('no image')),
        es.ocrErrorRecognitionFailed,
      );
    });

    test('codes the worker writes directly', () {
      expect(
        describeOcrFailure(es, OcrFailure.keyMissing.code()),
        es.ocrCustomServerKeyRequiredBody,
      );
      expect(
        describeOcrFailure(es, OcrFailure.pageImageMissing.code('/a/b.jpg')),
        es.ocrErrorPageImageMissing(path: '/a/b.jpg'),
      );
    });

    test('a custom server\'s connection test', () {
      expect(
        describeOcrFailure(es, OcrFailure.unhealthy.code('warming')),
        es.settingsCustomOcrServerUnhealthy(status: 'warming'),
      );
      expect(
        describeOcrFailure(es, OcrFailure.status.code('404:')),
        es.serverErrorStatus(status: 404),
      );
    });

    test('English saved by an older version is worded by how it starts', () {
      expect(
        describeOcrFailure(es, 'Could not connect to OCR server.'),
        es.ocrErrorConnectFailed,
      );
      expect(
        describeOcrFailure(es, 'OCR server URL is not configured.'),
        es.ocrCustomServerRequiredBody,
      );
      expect(
        describeOcrFailure(es, 'OCR server error (502). The server may be '),
        es.ocrErrorServer(status: 502),
      );
      // An exception's text followed these; none of it is shown.
      expect(
        describeOcrFailure(es, 'Unexpected error: Exception: 秘密.zip'),
        es.localOcrCouldNotContinue,
      );
      expect(
        describeOcrFailure(es, 'Network error: Broken pipe'),
        es.localOcrCouldNotContinue,
      );
    });
  });

  testWidgets('on-device OCR codes are worded in the app language', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('es'),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(localOcrReason(context, 'job_busy'), es.localOcrStillRunning);
    expect(
      localOcrReason(context, 'consecutive_page_failures'),
      es.localOcrTooManyFailures,
    );
    expect(
      localOcrReason(context, 'page_failed'),
      es.ocrErrorRecognitionFailed,
    );
    expect(
      localOcrReason(context, 'network_error'),
      es.localOcrDownloadNetwork,
    );
    expect(
      localOcrReason(context, 'download_http_503'),
      es.serverErrorStatus(status: 503),
    );
    // Anything else, a native failure's message or a Dart error's text
    // included, says only that OCR couldn't continue.
    for (final code in [
      'weird',
      '/data/user/0/moe.matthew.mekuru/files/x.json (No such file)',
      'Bad state: No element',
    ]) {
      expect(localOcrReason(context, code), es.localOcrCouldNotContinue);
    }
  });

  test('a failed model download is worded in the app language', () {
    String? reason(Object error) =>
        dictionaryDownloadError(es, error, kind: DownloadKind.mangaOcrIos);
    expect(
      reason(const ModelVerificationException()),
      es.localOcrDownloadDamaged,
    );
    expect(
      reason(const ServerDownloadHttpException(404)),
      'Error al descargar: El servidor devolvió el error 404.',
    );
    expect(
      reason(const SocketException('refused')),
      es.localOcrDownloadNetwork,
    );
    // A model keeps the files it got, which a dictionary does not.
    expect(reason(const WifiLostException()), es.localOcrWifiLostIos);
    expect(
      dictionaryDownloadError(
        es,
        const WifiLostException(),
        kind: DownloadKind.fixedDictionary,
      ),
      es.dictionaryDownloadWifiLost,
    );
  });
}
