import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/features/manga/data/services/local_ocr_client.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_page_overlay.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

class Client implements LocalOcrClient {
  final created = Completer<OcrJobProgress>();
  final cancelled = <String>[];
  int starts = 0;
  @override
  Future<OcrJobProgress> start(OcrJobSpec spec) {
    starts++;
    return created.future;
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }

  @override
  Future<OcrModelState> modelState() async =>
      const OcrModelState({'supported': true, 'installed': true});
  @override
  Future<bool> requestNotifications() async => true;
}

const spec = OcrJobSpec(
  bookId: 1,
  title: 'Manga',
  cachePath: '/cache',
  pages: [7],
);
const queued = OcrJobProgress({
  'id': 'job',
  'bookId': 1,
  'status': 'queued',
  'pages': [7],
});

void main() {
  test(
    'launch is immediate and cancel during preparation creates no native job',
    () async {
      final client = Client();
      final container = ProviderContainer(
        overrides: [localOcrClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final gate = Completer<void>();
      final controller = container.read(localOcrLaunchesProvider.notifier);
      final pending = controller.start(spec, () => gate.future);
      expect(container.read(localOcrLaunchesProvider)[1], isNotNull);
      await controller.cancel(1);
      gate.complete();
      await pending;
      expect(client.starts, 0);
      expect(container.read(localOcrLaunchesProvider), isEmpty);
    },
  );
  test('cancel racing native job creation cancels the returned job', () async {
    final client = Client();
    final container = ProviderContainer(
      overrides: [localOcrClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final controller = container.read(localOcrLaunchesProvider.notifier);
    final pending = controller.start(spec, () async {});
    await Future<void>.delayed(Duration.zero);
    expect(client.starts, 1);
    await controller.cancel(1);
    client.created.complete(queued);
    await pending;
    expect(client.cancelled, ['job']);
    expect(container.read(localOcrLaunchesProvider), isEmpty);
  });
  test(
    'start errors are retained and duplicate taps cannot create duplicate jobs',
    () async {
      final client = Client();
      final container = ProviderContainer(
        overrides: [localOcrClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final controller = container.read(localOcrLaunchesProvider.notifier);
      final pending = controller.start(spec, () async {});
      await controller.start(spec, () async {});
      expect(client.starts, 1);
      client.created.completeError(StateError('could not start'));
      await pending;
      expect(
        container.read(localOcrLaunchesProvider)[1]!.error,
        contains('could not start'),
      );
    },
  );
  test(
    'single-page ETA starts after timed regions, not invented at launch',
    () {
      expect(queued.etaSeconds, isNull);
      const reading = OcrJobProgress({
        'id': 'job',
        'bookId': 1,
        'status': 'running',
        'pages': [7],
        'regionsDone': 2,
        'regionsTotal': 5,
        'regionElapsedMs': 4000,
      });
      expect(reading.etaSeconds, 6);
    },
  );
  testWidgets(
    'page remains mounted and cancel is visible before native start resolves',
    (tester) async {
      final client = Client();
      final container = ProviderContainer(
        overrides: [
          localOcrClientProvider.overrideWithValue(client),
          localOcrJobsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      addTearDown(container.dispose);
      final gate = Completer<void>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Text('Current page'),
                  LocalOcrPageOverlay(bookId: 1, visiblePages: [7]),
                ],
              ),
            ),
          ),
        ),
      );
      final pageElement = tester.element(find.text('Current page'));
      final pending = container
          .read(localOcrLaunchesProvider.notifier)
          .start(spec, () => gate.future);
      await tester.pump();
      expect(find.text('Preparing models…'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Estimating time remaining…'), findsOneWidget);
      expect(tester.element(find.text('Current page')), same(pageElement));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      gate.complete();
      await pending;
      await tester.pump();
      expect(find.text('Cancel'), findsNothing);
      expect(tester.element(find.text('Current page')), same(pageElement));
    },
  );
}
