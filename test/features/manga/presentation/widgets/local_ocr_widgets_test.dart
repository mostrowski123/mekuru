import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/settings/presentation/widgets/ocr_attributions.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var wifi = true;
  var failNetworkCheck = false;
  Future<Object?> Function() benchmark = () async => null;
  void Function()? onBenchmarkCancel;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    wifi = true;
    failNetworkCheck = false;
    benchmark = () async => null;
    onBenchmarkCancel = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalMangaOcr.channel, (call) async {
          calls.add(call);
          if (call.method == 'isWifiConnected') {
            if (failNetworkCheck) {
              throw PlatformException(code: 'network_check_failed');
            }
            return wifi;
          }
          if (call.method == 'benchmark') return benchmark();
          if (call.method == 'benchmarkCancel') onBenchmarkCancel?.call();
          return null;
        });
    calls.clear();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalMangaOcr.channel, null);
  });
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  OcrJobProgress job(String status) => OcrJobProgress({
    'id': 'job',
    'bookId': 1,
    'status': status,
    'pages': [0, 1, 2],
    'outcomes': {'0': 'done', '1': 'failed'},
    'errors': {'1': 'image_access_lost'},
  });
  testWidgets('paused job shows explicit resume and retained progress', (
    tester,
  ) async {
    await tester.pumpWidget(host(LocalOcrJobCard(job: job('paused'))));
    expect(find.text('2 / 3 pages processed'), findsOneWidget);
    expect(find.text('1 saved · 0 skipped · 1 failed'), findsOneWidget);
    await tester.tap(find.text('Retry failed pages'));
    await tester.pump();
    expect(calls.single.method, 'resume');
    expect((calls.single.arguments as Map)['retryFailed'], true);
  });
  testWidgets('cancel requires confirmation and never deletes results', (
    tester,
  ) async {
    await tester.pumpWidget(host(LocalOcrJobCard(job: job('running'))));
    await tester.tap(find.text('Cancel scan'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.textContaining('Completed OCR will be kept'), findsOneWidget);
    await tester.tap(find.text('Cancel scan').last);
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['cancel']);
  });
  testWidgets('pause requests stop without cancelling the job', (tester) async {
    await tester.pumpWidget(host(LocalOcrJobCard(job: job('running'))));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(calls.map((c) => c.method), ['pause']);
  });
  testWidgets('dismiss deletes the finished job and tells the host at once', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      host(
        LocalOcrJobCard(job: job('completed'), onDismissed: () => dismissed++),
      ),
    );
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['dismiss']);
    expect((calls.single.arguments as Map)['id'], 'job');
    // Fired only after the delete lands, so a failure cannot leave the card
    // hidden while the journal still holds the job.
    expect(dismissed, 1);
  });
  testWidgets('a failed dismiss reports the error and keeps the card', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalMangaOcr.channel, (call) async {
          calls.add(call);
          throw PlatformException(code: 'job_busy');
        });
    var dismissed = 0;
    await tester.pumpWidget(
      host(
        LocalOcrJobCard(job: job('completed'), onDismissed: () => dismissed++),
      ),
    );
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['dismiss']);
    expect(dismissed, 0);
    expect(
      find.text(AppLocalizationsEn().localOcrError(details: 'job_busy')),
      findsOneWidget,
    );
  });
  testWidgets('download is available without Pro or account providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localOcrModelProvider.overrideWith(
            (ref) => Stream.value(
              const OcrModelState({
                'supported': true,
                'installed': false,
                'status': 'missing',
                'totalBytes': 296173655,
                'downloadedBytes': 0,
              }),
            ),
          ),
        ],
        child: host(const LocalOcrDownloadTile()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Japanese manga OCR — manga-ocr'), findsOneWidget);
    expect(find.textContaining('296.2 MB'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['isWifiConnected', 'download']);
    expect((calls.last.arguments as Map)['allowMetered'], false);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(Card), findsNothing);
  });
  Widget modelDownload({int downloaded = 0}) => ProviderScope(
    overrides: [
      localOcrModelProvider.overrideWith(
        (ref) => Stream.value(
          OcrModelState({
            'supported': true,
            'installed': false,
            'status': 'missing',
            'totalBytes': 296173655,
            'downloadedBytes': downloaded,
          }),
        ),
      ),
    ],
    child: host(const LocalOcrDownloadTile()),
  );

  testWidgets('non-Wi-Fi download confirms size before transferring', (
    tester,
  ) async {
    wifi = false;
    await tester.pumpWidget(modelDownload());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.map((c) => c.method), ['isWifiConnected']);
    expect(find.text('Download over mobile data?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('296.2 MB'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Download'),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.last.method, 'download');
    expect((calls.last.arguments as Map)['allowMetered'], true);
  });

  testWidgets('cancel mobile confirmation leaves transfer untouched', (
    tester,
  ) async {
    wifi = false;
    await tester.pumpWidget(modelDownload());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['isWifiConnected']);
    // Network state is checked again for each explicit attempt.
    wifi = true;
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), [
      'isWifiConnected',
      'isWifiConnected',
      'download',
    ]);
    expect((calls.last.arguments as Map)['allowMetered'], false);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'resume asks again off Wi-Fi and dismissing does not grant consent',
    (tester) async {
      wifi = false;
      await tester.pumpWidget(modelDownload(downloaded: 100000000));
      await tester.pumpAndSettle();
      expect(find.text('100.0 MB / 296.2 MB downloaded'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('saved download progress will be reused'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['isWifiConnected']);
    },
  );

  testWidgets('network check failure reports error and never starts transfer', (
    tester,
  ) async {
    failNetworkCheck = true;
    await tester.pumpWidget(modelDownload());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.textContaining('network_check_failed'), findsOneWidget);
    expect(calls.map((c) => c.method), ['isWifiConnected']);
  });

  testWidgets('unsupported device does not offer download', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localOcrModelProvider.overrideWith(
            (ref) => Stream.value(const OcrModelState({'supported': false})),
          ),
        ],
        child: host(const LocalOcrDownloadTile()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing);
    expect(find.textContaining('Remote OCR remains available'), findsOneWidget);
  });
  testWidgets('attributions and bundled licenses are reachable offline', (
    tester,
  ) async {
    await tester.pumpWidget(host(const OcrAttributions()));
    expect(find.textContaining('manga-ocr by'), findsOneWidget);
    expect(find.textContaining('Comic Text Detector by'), findsOneWidget);
    await tester.tap(find.text('View license and source notices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MANGA-OCR.txt'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('aa6573bd10b0d446cbf622e29c3e084914df9741'),
      findsOneWidget,
    );
    expect(calls, isEmpty);
  });

  group('LocalOcrSpeedTestRow', () {
    final en = AppLocalizationsEn();
    const result = {'loadMs': 1200, 'pageMs': 8000, 'blocks': 5, 'threads': 2};
    const running = 'Testing on-device OCR speed…';

    testWidgets('runs behind a modal and remembers the result', (tester) async {
      final pending = Completer<Map<String, Object>>();
      benchmark = () => pending.future;
      await tester.pumpWidget(host(const LocalOcrSpeedTestRow()));
      await tester.pumpAndSettle();
      expect(find.textContaining('About '), findsNothing);

      await tester.tap(find.text('Test device speed'));
      await tester.pump();
      await tester.pump();
      expect(find.text(running), findsOneWidget);

      pending.complete(result);
      await tester.pumpAndSettle();
      expect(find.text(running), findsNothing);
      expect(
        find.text(
          'About 8.0 s per page · a 200-page volume takes about 27 min',
        ),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('ocr.speed_test_page_ms'), 8000);
      expect(prefs.getInt('ocr.speed_test_load_ms'), 1200);
      expect(calls.map((c) => c.method), ['benchmark']);

      // A fresh row restores the remembered result without running again.
      calls.clear();
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpWidget(host(const LocalOcrSpeedTestRow()));
      await tester.pumpAndSettle();
      expect(find.textContaining('About 8.0 s per page'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('missing models point at Downloads and keep no result', (
      tester,
    ) async {
      benchmark = () async => throw PlatformException(code: 'model_missing');
      await tester.pumpWidget(host(const LocalOcrSpeedTestRow()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test device speed'));
      await tester.pumpAndSettle();
      expect(find.text(en.localOcrDownloadRequired), findsOneWidget);
      expect(find.text(running), findsNothing);
      expect(find.textContaining('About '), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('ocr.speed_test_page_ms'), isNull);
    });

    testWidgets('cancel stops the test and reports the interruption', (
      tester,
    ) async {
      final pending = Completer<Map<String, Object>>();
      benchmark = () => pending.future;
      onBenchmarkCancel = () =>
          pending.completeError(PlatformException(code: 'stopped'));
      await tester.pumpWidget(host(const LocalOcrSpeedTestRow()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test device speed'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['benchmark', 'benchmarkCancel']);
      expect(find.text(en.localOcrSpeedTestCancelled), findsOneWidget);
      expect(find.text(en.localOcrInterrupted), findsNothing);
      expect(find.text(running), findsNothing);
      expect(find.textContaining('About '), findsNothing);
    });

    test('volume estimate rounds up to whole minutes', () {
      expect(localOcrVolumeMinutes(1200, 8000), 27);
      expect(localOcrVolumeMinutes(0, 60000), 200);
      expect(localOcrVolumeMinutes(0, 0), 0);
    });

    testWidgets('download tile offers the test only once installed', (
      tester,
    ) async {
      Widget tile(bool installed) => ProviderScope(
        key: ValueKey(installed),
        overrides: [
          localOcrModelProvider.overrideWith(
            (ref) => Stream.value(
              OcrModelState({
                'supported': true,
                'installed': installed,
                'status': installed ? 'installed' : 'missing',
                'totalBytes': 296173655,
                'downloadedBytes': 0,
              }),
            ),
          ),
        ],
        child: host(const LocalOcrDownloadTile()),
      );
      await tester.pumpWidget(tile(false));
      await tester.pumpAndSettle();
      expect(find.byType(LocalOcrSpeedTestRow), findsNothing);
      await tester.pumpWidget(tile(true));
      await tester.pumpAndSettle();
      expect(find.byType(LocalOcrSpeedTestRow), findsOneWidget);
      expect(find.text('Test device speed'), findsOneWidget);
    });
  });
}
