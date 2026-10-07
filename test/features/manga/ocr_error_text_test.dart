import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_client.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/data/services/vision_page_ocr.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';
import 'package:mekuru/features/sync/data/services/server_download_work.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

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
      expect(
        describe(const OcrServerException(0, 'Network error: Broken pipe')),
        'Error de red: Broken pipe',
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

    test('text saved by an older version is shown as it is', () {
      expect(
        describeOcrFailure(es, 'Could not connect to OCR server.'),
        'Could not connect to OCR server.',
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
    // Anything else in the general message.
    expect(
      localOcrReason(context, 'weird'),
      es.localOcrError(details: 'weird'),
    );
  });

  test('a failed model download is worded in the app language', () {
    expect(
      modelDownloadFailureReason(es, const ModelVerificationException()),
      es.localOcrDownloadDamaged,
    );
    expect(
      modelDownloadFailureReason(es, const ServerDownloadHttpException(404)),
      es.serverErrorStatus(status: 404),
    );
    expect(
      modelDownloadFailureReason(es, const SocketException('refused')),
      es.localOcrDownloadNetwork,
    );
  });
}
