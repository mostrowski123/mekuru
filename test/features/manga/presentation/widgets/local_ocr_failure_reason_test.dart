// Every place an on-device OCR step can fail words the failure the same way,
// in the app language: a native failure by its code, anything else as "OCR
// could not continue". The failure's own text never shows.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/local_ocr_client.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/services/ocr_purchase_flow.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_page_overlay.dart';
import 'package:mekuru/features/manga/presentation/widgets/local_ocr_widgets.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

final _ja = AppLocalizationsJa();

/// A failure's own text: a folder name the user gave, and a path.
const _secret = '秘密の漫画 /data/user/0/moe.matthew.mekuru/files/x';

/// Each failure with the words it is shown with: a native failure's code
/// has words of its own, anything else does not.
final _failures = <(String, Object, String)>[
  (
    'a native failure',
    PlatformException(code: 'book_busy', message: _secret),
    _ja.localOcrBusy,
  ),
  ('an unexpected error', StateError(_secret), _ja.localOcrCouldNotContinue),
];

void _expectWorded(String words) {
  expect(find.text(words), findsOneWidget);
  expect(
    find.textContaining(RegExp('秘密|/data/|Bad state|PlatformException')),
    findsNothing,
  );
}

/// The OCR client: [modelState], [start] and [cancel] end in [failure] when
/// they are asked to.
class _Client implements LocalOcrClient {
  _Client({this.modelFails = false, this.startFails = false, this.failure});

  final bool modelFails;
  final bool startFails;
  final Object? failure;

  @override
  Future<OcrModelState> modelState() async {
    if (modelFails) throw failure!;
    return const OcrModelState({'supported': true, 'installed': true});
  }

  @override
  Future<OcrJobProgress> start(OcrJobSpec spec) async {
    if (startFails) throw failure!;
    return OcrJobProgress({
      'id': 'job',
      'bookId': spec.bookId,
      'status': 'queued',
      'pages': spec.pages,
    });
  }

  @override
  Future<void> cancel(String jobId) async => throw failure!;

  @override
  Future<bool> requestNotifications() async => true;
}

const _spec = OcrJobSpec(
  bookId: 1,
  title: 'Manga',
  cachePath: '/cache',
  pages: [0],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, failure, words) in _failures) {
    group(name, () {
      testWidgets('ending an action on a scan shows a message', (tester) async {
        await tester.pumpWidget(
          buildLocalizedTestApp(
            locale: const Locale('ja'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      runLocalOcrAction(context, () async => throw failure),
                  child: const Text('act'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('act'));
        await tester.pumpAndSettle();

        _expectWorded(words);
      });

      testWidgets('reading the OCR models shows it under them', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localOcrModelProvider.overrideWith(
                (ref) => Stream.error(failure),
              ),
            ],
            child: buildLocalizedTestApp(
              locale: const Locale('ja'),
              home: const Scaffold(body: LocalOcrDownloadTile()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectWorded(words);
      });

      testWidgets('starting a scan from the OCR sheet shows it on the sheet', (
        tester,
      ) async {
        final flow = OcrPurchaseFlow.instance;
        OcrPurchaseFlow.instance = OcrPurchaseFlow(
          readProUnlocked: () async => true,
        );
        addTearDown(() => OcrPurchaseFlow.instance = flow);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localOcrClientProvider.overrideWithValue(
                _Client(modelFails: true, failure: failure),
              ),
              ocrBookLoaderProvider.overrideWithValue(
                (_) async => const MokuroBook(
                  title: 'Manga',
                  imageDirPath: '/unused',
                  pages: [
                    MokuroPage(
                      pageIndex: 0,
                      imageFileName: '0.png',
                      imgWidth: 100,
                      imgHeight: 120,
                      blocks: [],
                    ),
                  ],
                ),
              ),
              localOcrJobsProvider.overrideWith(
                (ref) => Stream.value(const []),
              ),
              ocrProgressProvider(1).overrideWith((ref) => Stream.value(null)),
            ],
            child: buildLocalizedTestApp(
              locale: const Locale('ja'),
              home: Scaffold(
                body: OcrActionSheet(
                  book: Book(
                    id: 1,
                    isFavorite: false,
                    title: 'Manga',
                    filePath: '/unused',
                    bookType: 'manga',
                    totalPages: 1,
                    readProgress: 0,
                    dateAdded: DateTime(2026),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(_ja.localOcrStartPages(count: 1)));
        await tester.pumpAndSettle();

        _expectWorded(words);
      });

      /// The reader's scan panel over the page, for a scan launched in
      /// [container].
      Future<void> showPanel(
        WidgetTester tester,
        ProviderContainer container,
      ) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: buildLocalizedTestApp(
              locale: const Locale('ja'),
              home: const Scaffold(
                body: Stack(
                  children: [
                    LocalOcrPageOverlay(bookId: 1, visiblePages: [0]),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      ProviderContainer scans(_Client client) {
        final container = ProviderContainer(
          overrides: [
            localOcrClientProvider.overrideWithValue(client),
            localOcrJobsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      testWidgets('a scan that does not start shows it on the page', (
        tester,
      ) async {
        final container = scans(_Client(startFails: true, failure: failure));
        await container
            .read(localOcrLaunchesProvider.notifier)
            .start(_spec, () async {});
        await showPanel(tester, container);

        _expectWorded(words);
      });

      testWidgets('a scan that does not cancel shows it on the page', (
        tester,
      ) async {
        final container = scans(_Client(failure: failure));
        final launches = container.read(localOcrLaunchesProvider.notifier);
        await launches.start(_spec, () async {});
        await launches.cancel(1);
        await showPanel(tester, container);

        _expectWorded(words);
      });
    });
  }
}
