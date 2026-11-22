import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/manga/data/services/ndl_text_model.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/fake_download_notifiers.dart';
import '../../../../shared/fake_path_provider.dart';
import '../../../../shared/free_space_fakes.dart';
import '../../../../shared/loopback_http.dart';
import '../../../../test_app.dart';

void main() {
  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Scaffold(body: MangaOcrIosDownloadTile()),
      ),
    );
    // The installed check is real file I/O, which the fake clock never runs.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  // The tile spins while the dialog is open, so it never settles there.
  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder inDialog(Finder text) =>
      find.descendant(of: find.byType(AlertDialog), matching: text);

  testWidgets('offers the optional manga-ocr pack with its size', (
    tester,
  ) async {
    await pumpTile(tester);

    expect(find.text('Download'), findsOneWidget);
    // Encoder, decoder and vocabulary, without Android's detector.
    expect(find.textContaining('201.5 MB'), findsOneWidget);
    expect(find.textContaining('Optional'), findsOneWidget);
  });

  testWidgets('off Wi-Fi asks before downloading the pack', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockWifiConnected(false);
      await pumpTile(tester);

      await tester.tap(find.text('Download'));
      await pumpDialog(tester);
      expect(find.text('Download over mobile data?'), findsOneWidget);
      expect(inDialog(find.textContaining('201.5 MB')), findsOneWidget);
      // Busy while asking: no second tap can start a second download.
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Download'),
        ),
        findsNothing,
      );

      await tester.tap(inDialog(find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.text('Download'));
      await pumpDialog(tester);
      await tester.tap(inDialog(find.text('Download')));
      await pumpDialog(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on Wi-Fi the pack downloads without asking', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockWifiConnected(true);
      await pumpTile(tester);

      await tester.tap(find.text('Download'));
      await pumpDialog(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('ModelDownloadTile', () {
    late bool installed;
    late Completer<void> finish;
    late List<bool> wifiOnlyCalls;
    late int removed;
    late bool removeFails;
    void Function(double)? report;

    setUp(() {
      installed = false;
      wifiOnlyCalls = [];
      removed = 0;
      removeFails = false;
      report = null;
    });

    Future<void> pumpModelTile(WidgetTester tester, {Locale? locale}) async {
      // Made in the test's fake-async zone, which setUp is not.
      finish = Completer<void>();
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Scaffold(
            body: ModelDownloadTile(
              icon: Icons.menu_book_outlined,
              title: 'Test model',
              description: 'Optional test model.',
              files: ndlTextModelFiles,
              installed: () async => installed,
              download: ({required NetworkConsent network, onProgress}) {
                report = onProgress;
                wifiOnlyCalls.add(network == NetworkConsent.wifiOnly);
                return finish.future;
              },
              remove: () async {
                removed++;
                if (removeFails) {
                  throw const FileSystemException('locked', '/data/model');
                }
                installed = false;
              },
              readyText: 'Models installed · works offline',
              mobileDataBody: (size) => 'The model is $size.',
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pump();
    }

    testWidgets('downloads with progress, then offers Remove', (tester) async {
      mockWifiConnected(true);
      await pumpModelTile(tester);
      expect(find.text('Optional test model. (42.6 MB)'), findsOneWidget);

      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump();
      // Started on Wi-Fi without asking, so it stops if Wi-Fi goes.
      expect(wifiOnlyCalls, [true]);
      report!(0.5);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.5,
      );

      installed = true;
      finish.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Models installed · works offline'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(removed, 1);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('accepted mobile data lets the download go on off Wi-Fi', (
      tester,
    ) async {
      mockWifiConnected(false);
      await pumpModelTile(tester);
      await tester.tap(find.text('Download'));
      await pumpDialog(tester);
      await tester.tap(inDialog(find.text('Download')));
      await pumpDialog(tester);
      expect(wifiOnlyCalls, [false]);
    });

    testWidgets('a lost Wi-Fi connection says how to continue', (tester) async {
      mockWifiConnected(true);
      await pumpModelTile(tester);
      await tester.tap(find.text('Download'));
      await tester.pump();
      finish.completeError(const WifiLostException());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The download stopped because Wi-Fi disconnected. Finished files '
          'are kept. Tap Download to continue.',
        ),
        findsOneWidget,
      );
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('a download Android stopped in the background says so', (
      tester,
    ) async {
      mockWifiConnected(true);
      await pumpModelTile(tester);
      await tester.tap(find.text('Download'));
      await tester.pump();
      finish.completeError(const DownloadStoppedInBackgroundException());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The download stopped because Mekuru was in the background. Tap '
          'Download to resume.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('other failures say the download did not finish, never the '
        "error's text", (tester) async {
      mockWifiConnected(true);
      await pumpModelTile(tester);
      await tester.tap(find.text('Download'));
      await tester.pump();
      finish.completeError(Exception('boom'));
      await tester.pumpAndSettle();
      expect(
        find.text("The download didn't finish. Try again."),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('in Japanese, a failed remove says so and offers Remove '
        'again', (tester) async {
      final ja = lookupAppLocalizations(const Locale('ja'));
      installed = true;
      removeFails = true;
      await pumpModelTile(tester, locale: const Locale('ja'));

      await tester.tap(find.byTooltip(ja.commonRemove));
      await tester.pumpAndSettle();

      expect(removed, 1);
      expect(find.text(ja.downloadsDeleteFailed), findsOneWidget);
      expect(untranslatedDownloadText, findsNothing);
      expect(find.textContaining('/data/'), findsNothing);

      removeFails = false;
      await tester.tap(find.byTooltip(ja.commonRemove));
      await tester.pumpAndSettle();
      expect(removed, 2);
      expect(find.text(ja.downloadsDeleteFailed), findsNothing);
      expect(find.text(ja.commonDownload), findsOneWidget);
    });
  });

  testWidgets('without room the NDL tile fetches nothing and says how much '
      'more it needs', (tester) async {
    final root = Directory.systemTemp.createTempSync('ndl_room_');
    PathProviderPlatform.instance = FakePathProviderPlatform(
      p.join(root.path, 'app'),
    );
    mockFreeBytes(1);
    final http = (await tester.runAsync(LoopbackHttp.start))!;
    addTearDown(() async {
      await tester.runAsync(http.close);
      root.deleteSync(recursive: true);
    });
    mockWifiConnected(true);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Scaffold(body: NdlTextModelDownloadTile()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final model = ndlTextModelFiles.fold(0, (sum, file) => sum + file.bytes);
    final shown = find.text(
      lookupAppLocalizations(
        const Locale('en'),
      ).backupFullNotEnoughSpace(size: formatBytes(model - 1)),
    );

    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(find.text('Download'), findsNothing);
    // The download's file I/O is real, which the fake clock never runs.
    for (var i = 0; i < 50 && find.text('Download').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    expect(http.requests, isEmpty);
    expect(shown, findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  testWidgets('the NDL tile offers the scanned-book reader with its size', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Scaffold(body: NdlTextModelDownloadTile()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text('Scanned-book reader — NDLOCR-Lite'), findsOneWidget);
    expect(find.textContaining('(42.6 MB)'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  group('Downloads screen shows the NDL tile', () {
    Future<void> pumpDownloads(
      WidgetTester tester, {
      required bool onDeviceSupported,
    }) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...fakeDownloadNotifierOverrides(<String>[]),
            localOcrModelProvider.overrideWith(
              (ref) => Stream.value(
                OcrModelState({
                  'supported': onDeviceSupported,
                  'installed': false,
                }),
              ),
            ),
          ],
          child: buildLocalizedTestApp(home: const DownloadsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The list builds lazily and these tiles sit at its end.
    Iterable<Type> tiles(WidgetTester tester) =>
        (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
                as SliverChildListDelegate)
            .children
            .map((child) => child.runtimeType);

    testWidgets('on Android only where on-device OCR runs', (tester) async {
      await pumpDownloads(tester, onDeviceSupported: false);
      expect(tiles(tester), isNot(contains(NdlTextModelDownloadTile)));

      await tester.pumpWidget(const SizedBox());
      await pumpDownloads(tester, onDeviceSupported: true);
      expect(tiles(tester), contains(NdlTextModelDownloadTile));
    });

    testWidgets('on iOS always, next to the manga-ocr pack', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpDownloads(tester, onDeviceSupported: false);
        expect(
          tiles(tester),
          containsAllInOrder([
            MangaOcrIosDownloadTile,
            NdlTextModelDownloadTile,
          ]),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
