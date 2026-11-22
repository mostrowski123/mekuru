import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_client.dart';
import 'package:mekuru/features/manga/data/services/ocr_failure.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/l10n/l10n.dart';

import '../../test_app.dart';

void main() {
  final ja = AppLocalizationsJa();

  /// What the app shows for [errorMessage] and for [job]'s phase, in Japanese.
  Future<void> show(
    WidgetTester tester, {
    String? errorMessage,
    OcrJobProgress? job,
  }) => tester.pumpWidget(
    buildLocalizedTestApp(
      locale: const Locale('ja'),
      home: Builder(
        builder: (context) => Column(
          children: [
            if (errorMessage != null)
              Text(describeOcrFailure(context.l10n, errorMessage)),
            if (job != null) Text('phase:${localOcrPhase(context, job)}'),
          ],
        ),
      ),
    ),
  );

  void expectNoRawText() {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('秘密'), findsNothing);
    expect(find.textContaining('Broken pipe'), findsNothing);
  }

  testWidgets('an unexpected failure says OCR could not continue', (
    tester,
  ) async {
    await show(
      tester,
      errorMessage: ocrErrorCode(StateError('秘密の漫画/001.jpg is gone')),
    );

    expectNoRawText();
    expect(find.text(ja.localOcrCouldNotContinue), findsOneWidget);
  });

  testWidgets('a network failure says it could not reach the server', (
    tester,
  ) async {
    await show(
      tester,
      errorMessage: ocrErrorCode(
        const OcrServerException(0, 'Network error: Broken pipe'),
      ),
    );

    expectNoRawText();
    expect(find.text(ja.ocrErrorConnectFailed), findsOneWidget);
  });

  testWidgets('English an older version stored is worded', (tester) async {
    await show(
      tester,
      errorMessage: 'Unexpected error: Exception: 秘密の漫画 broke',
    );

    expectNoRawText();
    expect(find.text(ja.localOcrCouldNotContinue), findsOneWidget);
  });

  testWidgets('a failure with words of its own keeps them', (tester) async {
    await show(tester, errorMessage: OcrFailure.authFailed.code());

    expect(find.text(ja.ocrErrorAuthFailed), findsOneWidget);
  });

  testWidgets('a job status with no words of its own never shows its code', (
    tester,
  ) async {
    await show(tester, job: const OcrJobProgress({'status': 'stalled'}));

    expect(find.text('phase:'), findsOneWidget);
    expect(find.textContaining('stalled'), findsNothing);
  });

  testWidgets('a running job in a phase with no words says it recognizes', (
    tester,
  ) async {
    await show(
      tester,
      job: const OcrJobProgress({'status': 'running', 'phase': 'warming'}),
    );

    expect(find.text('phase:${ja.localOcrRecognizing}'), findsOneWidget);
    expect(find.textContaining('running'), findsNothing);
  });

  testWidgets('a known phase keeps its words', (tester) async {
    await show(
      tester,
      job: const OcrJobProgress({'status': 'running', 'phase': 'detecting'}),
    );

    expect(find.text('phase:${ja.localOcrDetecting}'), findsOneWidget);
  });
}
