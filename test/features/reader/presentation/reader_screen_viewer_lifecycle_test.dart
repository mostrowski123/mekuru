// How the EPUB reader follows its viewer's life: loading, the load
// watchdog, relocations (what they save and bookmark, also before epub.js
// has locations), rebuilds for a new reading mode, and a renderer that
// dies. A blank web view stands in for the real one, so each test plays
// the viewer's side by calling its callbacks.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/epub_models.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/repositories/bookmark_repository.dart';
import 'package:mekuru/features/reader/data/repositories/highlight_repository.dart';
import 'package:mekuru/features/reader/data/services/reader_settings_storage.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/providers/user_font_providers.dart';
import 'package:mekuru/features/reader/presentation/screens/reader_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/reading_settings_screen.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../shared/fake_user_font_store.dart';
import '../../../shared/reader_settings_test_helpers.dart';
import '../../../shared/test_database.dart';
import '../../../test_app.dart';
import 'recording_reader.dart';

const _openedAt = 'epubcfi(/6/4!/4/2/1:0)';
const _pageA = 'epubcfi(/6/6!/4/2/1:0)';
const _pageB = 'epubcfi(/6/8!/4/2/1:0)';
const _pageC = 'epubcfi(/6/10!/4/2/1:0)';
final _en = AppLocalizationsEn();

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

/// The book's one highlight, looked up only once [found] completes.
class _HeldHighlights extends HighlightRepository {
  _HeldHighlights(super.db);

  static const range = 'epubcfi(/6/4!/4/2,/1:0,/1:2)';
  final found = Completer<void>();

  @override
  Future<List<Highlight>> getAllHighlightsForBook(int bookId) async {
    await found.future;
    return [
      Highlight(
        id: 1,
        bookId: bookId,
        cfiRange: range,
        selectedText: '本を',
        color: 'yellow',
        userNote: '',
        dateAdded: DateTime(2026, 11, 22),
      ),
    ];
  }
}

class _DefaultSettingsStorage implements ReaderSettingsStorage {
  @override
  Future<ReaderSettings?> load() async => const ReaderSettings();

  @override
  Future<void> save(ReaderSettings settings) async {}
}

void main() {
  late Directory tempDir;
  late Book book;
  late AppDatabase db;
  late _RecordingBookRepository books;
  late ProviderContainer container;
  late WakelockPlusPlatformInterface originalWakelock;

  late List<({String message, Map<String, SentryAttribute> attributes})> logs;

  setUpAll(() => InAppWebViewPlatform.instance = _BlankWebViewPlatform());

  setUp(() {
    logs = [];
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message: message, attributes: attributes));
    SharedPreferences.setMockInitialValues({});
    originalWakelock = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = NoWakelock();
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
    usageLogSinkOverride = null;
    WakelockPlusPlatformInterface.instance = originalWakelock;
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  final spinner = find.byKey(const Key('reader-loading-overlay'));

  /// Opens [opened] (the test's book when null), and waits for its viewer
  /// unless [viewerExpected] is false. [highlights] stands in for the
  /// book's saved highlights, which only a Pro reader ([proUnlocked]) shows.
  Future<void> openReader(
    WidgetTester tester, {
    Book? opened,
    bool viewerExpected = true,
    bool proUnlocked = false,
    HighlightRepository? highlights,
  }) async {
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
        proUnlockedProvider.overrideWith(
          () => FakeProUnlockedNotifier(proUnlocked),
        ),
        if (highlights != null)
          highlightRepositoryProvider.overrideWithValue(highlights),
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
          home: ReaderScreen(book: opened ?? book, initialCfi: _openedAt),
        ),
      ),
    );
    if (viewerExpected) {
      await pumpUntilViewerBuilt(tester);
      return;
    }
    for (var i = 0; i < 50 && find.text('Retry').evaluate().isEmpty; i++) {
      // The book file is looked for with real file IO.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
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

  void relocate(WidgetTester tester, String cfi, double progress) =>
      readerViewer(tester).onRelocated!(
        EpubLocation(startCfi: cfi, endCfi: cfi, progress: progress),
      );

  testWidgets('the spinner stays until the viewer reports the book shown', (
    tester,
  ) async {
    await openReader(tester);
    expect(spinner, findsOneWidget);

    readerViewer(tester).onLoaded!();
    await tester.pump();
    expect(spinner, findsNothing);

    // A loaded book does not time out later.
    await tester.pump(const Duration(seconds: 16));
    expect(find.textContaining('took too long'), findsNothing);
    expect(readerViewerFinder(), findsOneWidget);
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
    expect(readerViewerFinder(), findsNothing);
    await closeReader(tester);
  });

  testWidgets('a rebuilt viewer that never shows the book times out too', (
    tester,
  ) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(spinner, findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    expect(find.textContaining('took too long'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('Retry builds one viewer', (tester) async {
    await openReader(tester);
    await tester.pump(const Duration(seconds: 15));

    await tester.tap(find.text('Retry'));
    final built = <Key?>{};
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      built.addAll(readerViewerFinder().evaluate().map((e) => e.widget.key));
      // The book file is found again with real file IO.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(built, hasLength(1));
    expect(spinner, findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('the timeout does not replace a load error', (tester) async {
    await openReader(tester);

    readerViewer(tester).onLoadError!('net::ERR_FAILED');
    await tester.pump();
    expect(find.text(_en.readerCouldNotOpen), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    expect(find.text(_en.readerCouldNotOpen), findsOneWidget);
    expect(find.textContaining('took too long'), findsNothing);
    await closeReader(tester);
  });

  group('a book that does not open says so in plain words', () {
    /// What the reader sent to telemetry about it.
    List<Map<String, Object?>> openFailures() => [
      for (final log in logs)
        if (log.message == 'reader.open_failed')
          {for (final a in log.attributes.entries) a.key: a.value.value},
    ];

    testWidgets('a book file that is gone', (tester) async {
      final gone = '${tempDir.path}${Platform.pathSeparator}gone.epub';
      await openReader(
        tester,
        opened: book.copyWith(filePath: gone),
        viewerExpected: false,
      );

      expect(find.text(_en.readerBookFileUnreadable), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('FileSystemException'), findsNothing);
      expect(find.textContaining('gone'), findsNothing);
      // What happened is in telemetry, its path is not.
      final failure = openFailures().single;
      expect(failure['error_type'], 'FileSystemException');
      expect(failure.values.join(' '), isNot(contains('gone')));
      expect(failure.values.join(' '), isNot(contains(tempDir.path)));
      await closeReader(tester);
    });

    testWidgets('a book file the page could not read', (tester) async {
      await openReader(tester);

      // What the viewer passes when reading the book's file fails.
      readerViewer(tester).onLoadError!(
        FileSystemException('Cannot open file', book.filePath),
      );
      await tester.pump();
      expect(find.text(_en.readerBookFileUnreadable), findsOneWidget);
      expect(find.textContaining('Cannot open file'), findsNothing);
      final failure = openFailures().single;
      expect(failure['error_type'], 'FileSystemException');
      expect(failure.values.join(' '), isNot(contains(tempDir.path)));

      // Retry opens the book again.
      await tester.tap(find.text('Retry'));
      await pumpUntilViewerBuilt(tester);
      expect(find.text(_en.readerBookFileUnreadable), findsNothing);
      expect(spinner, findsOneWidget);
      await closeReader(tester);
    });

    for (final detail in [
      'net::ERR_FAILED',
      'HTTP 404',
      'display error',
      "TypeError: Cannot read properties of undefined (reading 'href')",
    ]) {
      testWidgets('what the page reports goes to telemetry, not on screen: '
          '$detail', (tester) async {
        await openReader(tester);

        readerViewer(tester).onLoadError!(detail);
        await tester.pump();
        expect(find.text(_en.readerCouldNotOpen), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.textContaining(detail), findsNothing);
        expect(openFailures().single['error_message'], detail);
        await closeReader(tester);
      });
    }
  });

  testWidgets('until locations exist a page keeps the saved progress', (
    tester,
  ) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();

    // Before locations epub.js reports every page at 0%.
    relocate(tester, _pageA, 0);
    await flushSaves(tester);
    expect(books.saves.last, (cfi: _pageA, progress: 0.42));

    readerViewer(tester).onLocationsReady!();
    relocate(tester, _pageB, 0.5);
    await flushSaves(tester);
    expect(books.saves.last, (cfi: _pageB, progress: 0.5));
    await closeReader(tester);
  });

  testWidgets('a new reading mode builds a viewer that waits for its own '
      'locations', (tester) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    readerViewer(tester).onLocationsReady!();
    relocate(tester, _pageB, 0.5);
    await flushSaves(tester);
    final oldKey = readerViewer(tester).key;

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(readerViewer(tester).key, isNot(oldKey));
    expect(
      readerViewer(tester).initialCfi,
      _pageB,
      reason: 'the last page shown',
    );
    expect(spinner, findsOneWidget);

    // The new viewer's first page arrives before its locations.
    relocate(tester, _pageC, 0);
    await flushSaves(tester);
    expect(books.saves.last, (cfi: _pageC, progress: 0.5));

    readerViewer(tester).onLoaded!();
    await tester.pump();
    expect(spinner, findsNothing);
    await closeReader(tester);
  });

  testWidgets('a reading-mode change while a new viewer loads is applied '
      'once it loads', (tester) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    final loading = readerViewer(tester);
    expect(loading.scrollView, isTrue);

    container.read(readerSettingsProvider.notifier).setScrollView(false);
    await settle(tester);
    expect(
      readerViewer(tester).key,
      loading.key,
      reason: 'left to finish loading',
    );

    loading.onLoaded!();
    await settle(tester);
    expect(readerViewer(tester).key, isNot(loading.key));
    expect(readerViewer(tester).scrollView, isFalse);
    expect(spinner, findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('late reports from a replaced viewer change nothing', (
    tester,
  ) async {
    await openReader(tester);
    final replaced = readerViewer(tester);
    replaced.onLoaded!();
    replaced.onLocationsReady!();
    relocate(tester, _pageB, 0.5);
    await flushSaves(tester);

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(readerViewer(tester).key, isNot(replaced.key));

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

  testWidgets('a new reading mode chosen while the highlights are still being '
      'looked up shows them on the new page', (tester) async {
    final webView = RecordingWebViewPlatform();
    InAppWebViewPlatform.instance = webView;
    addTearDown(() => InAppWebViewPlatform.instance = _BlankWebViewPlatform());
    List<String> drawn() => [
      for (final js in webView.sent)
        if (js.startsWith('addHighlight(')) js,
    ];
    final highlights = _HeldHighlights(db);
    await openReader(tester, proUnlocked: true, highlights: highlights);
    readerViewer(tester).onLoaded!();
    await tester.pump();
    final oldKey = readerViewer(tester).key;

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(readerViewer(tester).key, isNot(oldKey));

    // The old page's lookup ends after the new viewer took its place.
    highlights.found.complete();
    await settle(tester);
    final beforeShown = drawn();

    readerViewer(tester).onLoaded!();
    await settle(tester);
    expect(drawn().sublist(beforeShown.length), [
      contains(_HeldHighlights.range),
    ], reason: 'the new page shows the highlight');
    expect(
      beforeShown,
      isEmpty,
      reason: 'nothing is drawn on a page before it shows the book',
    );
    await closeReader(tester);
  });

  testWidgets('a dead renderer gets a new viewer at the page it showed', (
    tester,
  ) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();
    relocate(tester, _pageB, 0.5);
    await tester.pump();
    final oldKey = readerViewer(tester).key;

    readerViewer(tester).onRendererGone!();
    await settle(tester);
    expect(readerViewer(tester).key, isNot(oldKey));
    expect(readerViewer(tester).initialCfi, _pageB);
    expect(spinner, findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('a renderer that dies while the app is away is replaced on '
      'return, and its load is timed from then', (tester) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();
    relocate(tester, _pageB, 0.5);
    await tester.pump();
    final oldKey = readerViewer(tester).key;

    // Killed for memory in the background, where no frame is built.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    readerViewer(tester).onRendererGone!();
    await tester.pump(const Duration(seconds: 20));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.textContaining('took too long'), findsNothing);
    expect(readerViewer(tester).key, isNot(oldKey));
    expect(
      readerViewer(tester).initialCfi,
      _pageB,
      reason: 'the place it showed',
    );
    expect(spinner, findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    readerViewer(tester).onLoaded!();
    await tester.pump();
    expect(spinner, findsNothing);
    expect(find.textContaining('took too long'), findsNothing);
    await closeReader(tester);
  });

  testWidgets('a renderer that dies while the app shows unfocused (split '
      'screen) is replaced at once', (tester) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();
    final oldKey = readerViewer(tester).key;

    // Frames are still built.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    readerViewer(tester).onRendererGone!();
    await settle(tester);
    expect(readerViewer(tester).key, isNot(oldKey));
    await closeReader(tester);
  });

  testWidgets('a book sent to the background before it shows is given its '
      'time to load on return', (tester) async {
    await openReader(tester);

    // Away for longer than a load may take, where no frame is built.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.textContaining('took too long'), findsNothing);
    expect(spinner, findsOneWidget);

    readerViewer(tester).onLoaded!();
    await tester.pump();
    expect(spinner, findsNothing);
    expect(find.textContaining('took too long'), findsNothing);
    await closeReader(tester);
  });

  testWidgets('Retry opens at the place the reader had got to, not the one '
      'the book was opened at', (tester) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();
    relocate(tester, _pageB, 0.5);
    await tester.pump();

    readerViewer(tester).onLoadError!('net::ERR_FAILED');
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await pumpUntilViewerBuilt(tester);
    expect(readerViewer(tester).initialCfi, _pageB);
    await closeReader(tester);
  });

  testWidgets('a bookmark marks the start of the page on screen, and the '
      'progress the place a re-layout holds mid-page', (tester) async {
    const held = 'epubcfi(/6/4!/4/10/1:150)';
    const pageStart = 'epubcfi(/6/4!/4/8/1:231)';
    const pageEnd = 'epubcfi(/6/4!/4/12/1:20)';
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    readerViewer(tester).onLocationsReady!();
    // What the bridge reports after a re-layout that holds the place.
    readerViewer(tester).onRelocated!(
      const EpubLocation(
        startCfi: held,
        pageStartCfi: pageStart,
        endCfi: pageEnd,
        progress: 0.3,
      ),
    );
    await flushSaves(tester);
    expect(books.saves.last, (cfi: held, progress: 0.3));

    // A tap in the middle of the page brings up the controls.
    readerViewer(tester).onTouchDown!(0.5, 0.5, null);
    readerViewer(tester).onTouchUp!(0.5, 0.5, false, false, null);
    await settle(tester);
    await tester.tap(find.byTooltip(_en.readerBookmarkPageTooltip));
    await settle(tester);
    final saved = await tester.runAsync(
      () => BookmarkRepository(db).getBookmarksForBook(book.id),
    );
    expect([for (final b in saved!) b.cfi], [pageStart]);

    // The same page turned back to, with nothing held.
    relocate(tester, pageStart, 0.3);
    await settle(tester);
    expect(find.byTooltip(_en.readerRemoveBookmarkTooltip), findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('a renderer that dies while the book opens offers Retry', (
    tester,
  ) async {
    await openReader(tester);

    readerViewer(tester).onRendererGone!();
    await tester.pump();
    expect(
      find.text(
        'The reader stopped while opening the book. Tap Retry to try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    expect(
      find.text(
        'The reader stopped while opening the book. Tap Retry to try again.',
      ),
      findsOneWidget,
    );
    await closeReader(tester);
  });

  testWidgets('a dead renderer waits for the screen covering the reader', (
    tester,
  ) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();
    final oldKey = readerViewer(tester).key;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    unawaited(
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Text('x'))),
    );
    await settle(tester);
    readerViewer(tester).onRendererGone!();
    await settle(tester);
    expect(readerViewer(tester).key, oldKey);

    navigator.pop();
    await settle(tester);
    expect(readerViewer(tester).key, isNot(oldKey));
    await closeReader(tester);
  });

  testWidgets('a reading-mode change under the full settings screen waits '
      'until it closes', (tester) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();
    final oldKey = readerViewer(tester).key;

    // A tap in the middle of the page brings up the controls.
    readerViewer(tester).onTouchDown!(0.5, 0.5, null);
    readerViewer(tester).onTouchUp!(0.5, 0.5, false, false, null);
    await settle(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await settle(tester);
    expect(find.byType(ReadingSettingsScreen), findsOneWidget);

    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    expect(readerViewer(tester).key, oldKey);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(readerViewer(tester).key, isNot(oldKey));
    expect(spinner, findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('a reading-mode change under the full settings screen while a '
      'new viewer loads is applied once it loads', (tester) async {
    await openReader(tester);
    readerViewer(tester).onLoaded!();
    await tester.pump();

    // The quick settings sheet stays open over the reader while the new
    // viewer loads; its "All settings" button opens the full screen.
    readerViewer(tester).onTouchDown!(0.5, 0.5, null);
    readerViewer(tester).onTouchUp!(0.5, 0.5, false, false, null);
    await settle(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    container.read(readerSettingsProvider.notifier).setScrollView(true);
    await settle(tester);
    final loading = readerViewer(tester);
    expect(loading.scrollView, isTrue);

    await tester.tap(find.byIcon(Icons.tune));
    await settle(tester);
    expect(find.byType(ReadingSettingsScreen), findsOneWidget);
    container.read(readerSettingsProvider.notifier).setScrollView(false);
    await settle(tester);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(
      readerViewer(tester).key,
      loading.key,
      reason: 'left to finish loading',
    );

    loading.onLoaded!();
    await settle(tester);
    expect(readerViewer(tester).key, isNot(loading.key));
    expect(readerViewer(tester).scrollView, isFalse);
    await closeReader(tester);
  });
}
