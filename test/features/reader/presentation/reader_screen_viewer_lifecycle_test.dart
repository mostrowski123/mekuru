// How the EPUB reader follows its viewer's life: loading, the load
// watchdog, relocations before epub.js has locations, rebuilds for a new
// reading mode, and a renderer that dies. A blank web view stands in for
// the real one, so each test plays the viewer's side by calling its
// callbacks.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/epub_models.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/providers/user_font_providers.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';
import 'package:mekuru/features/settings/presentation/screens/reading_settings_screen.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../shared/fake_user_font_store.dart';
import '../../../shared/reader_settings_test_helpers.dart';
import '../../../shared/test_database.dart';
import '../../../test_app.dart';

const _openedAt = 'epubcfi(/6/4!/4/2/1:0)';
const _pageA = 'epubcfi(/6/6!/4/2/1:0)';
const _pageB = 'epubcfi(/6/8!/4/2/1:0)';
const _pageC = 'epubcfi(/6/10!/4/2/1:0)';

/// A web view that shows nothing and never reports back.
class _BlankWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _BlankWebView(params);
}

class _BlankWebView extends PlatformInAppWebViewWidget {
  _BlankWebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

/// Records the progress the reader saves instead of writing it.
class _RecordingBookRepository extends BookRepository {
  _RecordingBookRepository(super.db);

  final saves = <({String cfi, double? progress})>[];

  @override
  Future<Book?> getBookById(int id) async => null;

  @override
  Future<void> updateProgress(
    int bookId,
    String cfi, {
    double? progress,
    String? href,
    double? hrefProgression,
  }) async {
    saves.add((cfi: cfi, progress: progress));
  }
}

class _DefaultSettingsStorage implements ReaderSettingsStorage {
  @override
  Future<ReaderSettings?> load() async => const ReaderSettings();

  @override
  Future<void> save(ReaderSettings settings) async {}
}

class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  bool get isMock => true;

  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}

void main() {
  late Directory tempDir;
  late Book book;
  late AppDatabase db;
  late _RecordingBookRepository books;
  late ProviderContainer container;
  late WakelockPlusPlatformInterface originalWakelock;

  setUpAll(() => InAppWebViewPlatform.instance = _BlankWebViewPlatform());

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = _NoWakelock();
    tempDir = Directory.systemTemp.createTempSync('reader_viewer_');
    final epub = File('${tempDir.path}/book.epub')..writeAsBytesSync([0]);
    book = Book(
      id: 1,
      isFavorite: false,
      title: 'Viewer Lifecycle Book',
      filePath: epub.path,
      bookType: 'epub',
      totalPages: 1,
      readProgress: 0.42,
      language: 'ja',
      hasVerticalCss: false,
      dateAdded: DateTime(2026, 11, 21),
    );
    db = createTestDatabase();
    books = _RecordingBookRepository(db);
  });

  tearDown(() async {
    WakelockPlusPlatformInterface.instance = originalWakelock;
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Finder viewerFinder() => find.byType(CustomEpubViewer, skipOffstage: false);
  CustomEpubViewer viewer(WidgetTester tester) => tester.widget(viewerFinder());
  final spinner = find.byKey(const Key('reader-loading-overlay'));

  /// Pumps until the reader has resolved the book file and built a viewer.
  Future<void> pumpUntilViewerBuilt(WidgetTester tester) async {
    for (var i = 0; i < 50 && viewerFinder().evaluate().isEmpty; i++) {
      // The book file is resolved with real file IO.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(viewerFinder(), findsOneWidget, reason: 'no viewer was built');
  }

  Future<void> openReader(WidgetTester tester) async {
    // Answered at once: the settings screen opens only after the bars show.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('mekuru/android_system_ui'),
      (_) async => null,
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        readerBookRepositoryProvider.overrideWithValue(books),
        readerSettingsStorageProvider.overrideWithValue(
          _DefaultSettingsStorage(),
        ),
        readerBrightnessProvider.overrideWith(FakeReaderBrightnessNotifier.new),
        proUnlockedProvider.overrideWith(() => FakeProUnlockedNotifier(false)),
        userFontStoreProvider.overrideWithValue(FakeUserFontStore()),
        wanikaniKnownKanjiProvider.overrideWithValue(const {}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          // An open at a picked position skips the server progress pull.
          home: ReaderScreen(book: book, initialCfi: _openedAt),
        ),
      ),
    );
    await pumpUntilViewerBuilt(tester);
  }

  /// Lets the reader react (and an async viewer rebuild finish).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Past the 350 ms progress debounce.
  Future<void> flushSaves(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 400));

  Future<void> closeReader(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  void relocate(WidgetTester tester, String cfi, double progress) => viewer(
    tester,
  ).onRelocated!(EpubLocation(startCfi: cfi, endCfi: cfi, progress: progress));

  testWidgets('the spinner stays until the viewer reports the book shown', (
    tester,
  ) async {
    await openReader(tester);
    expect(spinner, findsOneWidget);

    viewer(tester).onLoaded!();
    await tester.pump();
    expect(spinner, findsNothing);

    // A loaded book does not time out later.
    await tester.pump(const Duration(seconds: 16));
    expect(find.textContaining('took too long'), findsNothing);
    expect(viewerFinder(), findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('a load that never finishes times out after 15 seconds', (
    tester,
  ) async {
    await openReader(tester);

    await tester.pump(const Duration(seconds: 14));
    expect(find.textContaining('took too long'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('took too long'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(viewerFinder(), findsNothing);
    await closeReader(tester);
  });

  testWidgets('the timeout does not replace a load error', (tester) async {
    await openReader(tester);

    viewer(tester).onLoadError!('net::ERR_FAILED');
    await tester.pump();
    expect(find.textContaining('net::ERR_FAILED'), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    expect(find.textContaining('net::ERR_FAILED'), findsOneWidget);
    expect(find.textContaining('took too long'), findsNothing);
    await closeReader(tester);
  });

  testWidgets('until locations exist a page keeps the saved progress', (
    tester,
  ) async {
    await openReader(tester);
    viewer(tester).onLoaded!();
    await tester.pump();

    // Before locations epub.js reports every page at 0%.
    relocate(tester, _pageA, 0);
    await flushSaves(tester);
    expect(books.saves.last, (cfi: _pageA, progress: 0.42));

    viewer(tester).onLocationsReady!();
    relocate(tester, _pageB, 0.5);
    await flushSaves(tester);
    expect(books.saves.last, (cfi: _pageB, progress: 0.5));
    await closeReader(tester);
  });

  testWidgets('a new reading mode builds a viewer that waits for its own '
      'locations', (tester) async {
    await openReader(tester);
    viewer(tester).onLoaded!();
    viewer(tester).onLocationsReady!();
    relocate(tester, _pageB, 0.5);
    await flushSaves(tester);
    final oldKey = viewer(tester).key;

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(viewer(tester).key, isNot(oldKey));
    expect(spinner, findsOneWidget);

    // The new viewer's first page arrives before its locations.
    relocate(tester, _pageC, 0);
    await flushSaves(tester);
    expect(books.saves.last, (cfi: _pageC, progress: 0.5));

    viewer(tester).onLoaded!();
    await tester.pump();
    expect(spinner, findsNothing);
    await closeReader(tester);
  });

  testWidgets('late reports from a replaced viewer change nothing', (
    tester,
  ) async {
    await openReader(tester);
    final replaced = viewer(tester);
    replaced.onLoaded!();
    replaced.onLocationsReady!();
    relocate(tester, _pageB, 0.5);
    await flushSaves(tester);

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(viewer(tester).key, isNot(replaced.key));

    // Messages the old web view sent before it went.
    replaced.onLoaded!();
    replaced.onLocationsReady!();
    replaced.onRelocated!(
      const EpubLocation(startCfi: _pageA, endCfi: _pageA, progress: 0.9),
    );
    await flushSaves(tester);
    expect(spinner, findsOneWidget);
    expect(books.saves.last, (cfi: _pageB, progress: 0.5));

    // The new viewer still has no locations of its own.
    relocate(tester, _pageC, 0);
    await flushSaves(tester);
    expect(books.saves.last, (cfi: _pageC, progress: 0.5));
    await closeReader(tester);
  });

  testWidgets('a dead renderer gets a new viewer at the page it showed', (
    tester,
  ) async {
    await openReader(tester);
    viewer(tester).onLoaded!();
    await tester.pump();
    relocate(tester, _pageB, 0.5);
    await tester.pump();
    final oldKey = viewer(tester).key;

    viewer(tester).onRendererGone!();
    await settle(tester);
    expect(viewer(tester).key, isNot(oldKey));
    expect(viewer(tester).initialCfi, _pageB);
    expect(spinner, findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('a renderer that dies while the book opens offers Retry', (
    tester,
  ) async {
    await openReader(tester);

    viewer(tester).onRendererGone!();
    await tester.pump();
    expect(find.textContaining('The web view stopped.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    expect(find.textContaining('The web view stopped.'), findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('a dead renderer waits for the screen covering the reader', (
    tester,
  ) async {
    await openReader(tester);
    viewer(tester).onLoaded!();
    await tester.pump();
    final oldKey = viewer(tester).key;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    unawaited(
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Text('x'))),
    );
    await settle(tester);
    viewer(tester).onRendererGone!();
    await settle(tester);
    expect(viewer(tester).key, oldKey);

    navigator.pop();
    await settle(tester);
    expect(viewer(tester).key, isNot(oldKey));
    await closeReader(tester);
  });

  testWidgets('a reading-mode change under the full settings screen waits '
      'until it closes', (tester) async {
    await openReader(tester);
    viewer(tester).onLoaded!();
    await tester.pump();
    final oldKey = viewer(tester).key;

    // A tap in the middle of the page brings up the controls.
    viewer(tester).onTouchDown!(0.5, 0.5, null);
    viewer(tester).onTouchUp!(0.5, 0.5, false, false, null);
    await settle(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await settle(tester);
    expect(find.byType(ReadingSettingsScreen), findsOneWidget);

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(viewer(tester).key, oldKey);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(viewer(tester).key, isNot(oldKey));
    expect(spinner, findsOneWidget);
    await closeReader(tester);
  });
}
