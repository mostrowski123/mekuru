// Opens the EPUB reader over a fake web view that records the JavaScript
// the reader sends it. A test plays the page's side by calling the viewer's
// callbacks.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/data/services/user_font_store.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/providers/user_font_providers.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../shared/fake_user_font_store.dart';
import '../../../shared/reader_settings_test_helpers.dart';
import '../../../test_app.dart';

/// What [RecordingWebViewPlatform.sent] holds for a picture of the page.
const screenshotCall = '<takeScreenshot>';

/// Records the JavaScript sent to every web view it makes. With
/// [finishLoading], a web view reports its page loaded as soon as it is
/// made, so the viewer sends the book.
class RecordingWebViewPlatform extends InAppWebViewPlatform {
  RecordingWebViewPlatform({this.finishLoading = false});

  final bool finishLoading;
  final sent = <String>[];

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _RecordingWebView(params, this);
}

class _RecordingWebView extends PlatformInAppWebViewWidget {
  _RecordingWebView(super.params, this.platform) : super.implementation();

  final RecordingWebViewPlatform platform;

  // A rebuild makes a new widget for the same web view: create it once.
  static final _created = Expando<bool>();

  @override
  Widget build(BuildContext context) {
    if (_created[context] != true) {
      _created[context] = true;
      final controller = params.controllerFromPlatform!(
        _RecordingController(platform.sent),
      );
      params.onWebViewCreated?.call(controller);
      if (platform.finishLoading) params.onLoadStop?.call(controller, null);
    }
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

class _RecordingController extends PlatformInAppWebViewController {
  _RecordingController(this.sent)
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  final List<String> sent;

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {}

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sent.add(source);
    return null;
  }

  /// Recorded in [sent] as [screenshotCall]: the reader takes no picture of
  /// the page.
  @override
  Future<Uint8List?> takeScreenshot({
    ScreenshotConfiguration? screenshotConfiguration,
  }) async {
    sent.add(screenshotCall);
    return null;
  }
}

class _NoProgress extends BookRepository {
  _NoProgress(super.db);

  @override
  Future<Book?> getBookById(int id) async => null;

  @override
  Future<void> updateProgress(
    int bookId,
    String cfi, {
    double? progress,
    String? href,
    double? hrefProgression,
  }) async {}
}

class _SettingsStorage implements ReaderSettingsStorage {
  _SettingsStorage(this.settings);

  final ReaderSettings settings;

  @override
  Future<ReaderSettings?> load() async => settings;

  @override
  Future<void> save(ReaderSettings settings) async {}
}

Finder readerViewerFinder() =>
    find.byType(CustomEpubViewer, skipOffstage: false);

CustomEpubViewer readerViewer(WidgetTester tester) =>
    tester.widget(readerViewerFinder());

/// Pumps until the reader has resolved the book file and built a viewer.
Future<void> pumpUntilViewerBuilt(WidgetTester tester) async {
  for (var i = 0; i < 50 && readerViewerFinder().evaluate().isEmpty; i++) {
    // The book file is resolved with real file IO.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(readerViewerFinder(), findsOneWidget, reason: 'no viewer was built');
}

/// A Japanese book (right to left, horizontal text), read [direction] when
/// given, its file in [dir].
Book recordedBook(Directory dir, {String? direction}) => Book(
  id: 1,
  isFavorite: false,
  title: 'Recorded Book',
  filePath: (File('${dir.path}/book.epub')..writeAsBytesSync([0])).path,
  bookType: 'epub',
  totalPages: 1,
  readProgress: 0,
  language: 'ja',
  hasVerticalCss: false,
  overrideReadingDirection: direction,
  dateAdded: DateTime(2026, 11, 22),
);

/// Opens [book] with [settings] in an app with [theme], and lets the page
/// report it shown unless [loaded] is false.
Future<ProviderContainer> openRecordedReader(
  WidgetTester tester, {
  required AppDatabase db,
  required Book book,
  required ReaderSettings settings,
  UserFontStore? fonts,
  ThemeData? theme,
  bool loaded = true,
}) async {
  // Left in place: a reader a failed test leaves open still turns the
  // wakelock off when the next test tears it down.
  WakelockPlusPlatformInterface.instance = NoWakelock();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('mekuru/android_system_ui'),
    (_) async => null,
  );
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      readerBookRepositoryProvider.overrideWithValue(_NoProgress(db)),
      readerSettingsStorageProvider.overrideWithValue(
        _SettingsStorage(settings),
      ),
      readerBrightnessProvider.overrideWith(FakeReaderBrightnessNotifier.new),
      proUnlockedProvider.overrideWith(() => FakeProUnlockedNotifier(false)),
      userFontStoreProvider.overrideWithValue(fonts ?? FakeUserFontStore()),
      wanikaniKnownKanjiProvider.overrideWithValue(const {}),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: buildLocalizedTestApp(
        theme: theme,
        home: ReaderScreen(book: book, initialCfi: 'epubcfi(/6/4!/4/2/1:0)'),
      ),
    ),
  );
  await pumpUntilViewerBuilt(tester);
  if (!loaded) return container;
  readerViewer(tester).onLoaded!();
  await tester.pump();
  return container;
}

/// Closes the reader and lets its timers run out.
Future<void> closeRecordedReader(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
