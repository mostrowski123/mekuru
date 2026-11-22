import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/epub_models.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/viewer_session.dart';

const _page = 'epubcfi(/6/4!/4/2/1:0)';
const _location = EpubLocation(startCfi: _page, endCfi: _page, progress: 0);
final _paged = viewerLayoutOf(const ReaderSettings());
final _scrolled = viewerLayoutOf(const ReaderSettings(scrollView: true));

void main() {
  late List<String> heard;

  /// A new viewer for [_paged]; its watchdog fires after [loadTimeout].
  ViewerSession newSession({
    Duration loadTimeout = const Duration(minutes: 1),
  }) {
    final session = ViewerSession(_paged, (
      loaded: () => heard.add('loaded'),
      locationsReady: () => heard.add('locationsReady'),
      relocated: (EpubLocation location, {required bool trusted}) =>
          heard.add(trusted ? 'relocated trusted' : 'relocated untrusted'),
      failed: (Object? error) =>
          heard.add('failed: ${error ?? 'web view stopped'}'),
      timedOut: () => heard.add('timedOut'),
      rendererGone: () => heard.add('rendererGone'),
    ), loadTimeout: loadTimeout);
    addTearDown(session.retire);
    return session;
  }

  /// Past a watchdog started with a 1 ms timeout.
  Future<void> afterTimeout() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() => heard = []);

  test('a viewer loads, then reports every display', () {
    final session = newSession();
    expect(session.phase, ViewerPhase.loading);
    expect(session.isLoaded, isFalse);

    session.loaded();
    session.loaded();
    expect(session.phase, ViewerPhase.ready);
    expect(session.isLoaded, isTrue);
    expect(heard, ['loaded', 'loaded']);
  });

  test('a page is trusted only once locations exist', () {
    final session = newSession();
    // Cached locations can come before the book shows.
    session.relocated(_location);
    session.locationsArrived();
    session.relocated(_location);
    session.loaded();

    expect(heard, [
      'relocated untrusted',
      'locationsReady',
      'relocated trusted',
      'loaded',
    ]);
    expect(session.locationsReady, isTrue);
  });

  test('what a retired viewer still sends reaches nothing', () async {
    final old = newSession(loadTimeout: const Duration(milliseconds: 1))
      ..retire();

    old
      ..loaded()
      ..locationsArrived()
      ..relocated(_location)
      ..loadFailed('late')
      ..rendererDied();
    await afterTimeout();
    expect(heard, isEmpty);
    expect(old.phase, ViewerPhase.retired);
    expect(old.beginReplacement(_scrolled), isFalse);
  });

  test('a new viewer that does not show the book in time fails', () async {
    final session = newSession(loadTimeout: const Duration(milliseconds: 1));

    await afterTimeout();
    expect(heard, ['timedOut']);
    expect(session.phase, ViewerPhase.failed);

    // A late load changes nothing.
    session.loaded();
    expect(heard, ['timedOut']);
  });

  test('the watchdog does not overwrite a load error', () async {
    final session = newSession(loadTimeout: const Duration(milliseconds: 1));

    session.loadFailed('net::ERR_FAILED');
    await afterTimeout();
    expect(heard, ['failed: net::ERR_FAILED']);

    // A second error in the same burst still shows.
    session.loadFailed('HTTP 404');
    expect(heard.last, 'failed: HTTP 404');
  });

  test(
    'a book that shows, or a viewer that goes, stops the watchdog',
    () async {
      final loaded = newSession(loadTimeout: const Duration(milliseconds: 1))
        ..loaded();
      final retired = newSession(loadTimeout: const Duration(milliseconds: 1))
        ..retire();

      await afterTimeout();
      expect(heard, ['loaded']);
      expect(loaded.phase, ViewerPhase.ready);
      expect(retired.phase, ViewerPhase.retired);
    },
  );

  test('a viewer showing a layout no longer wanted is replaced, once', () {
    final session = newSession()..loaded();

    expect(session.beginReplacement(_paged), isFalse);
    expect(session.isReplacing, isFalse);
    expect(session.beginReplacement(_scrolled), isTrue);
    expect(session.isReplacing, isTrue);
    expect(
      session.beginReplacement(_scrolled),
      isFalse,
      reason: 'one at a time',
    );
  });

  test('a viewer still loading is judged once it loads', () {
    final session = newSession();
    expect(session.beginReplacement(_scrolled), isFalse);
    expect(session.isReplacing, isFalse);

    session.loaded();
    expect(session.beginReplacement(_scrolled), isTrue);
  });

  test('a viewer that failed is replaced for another layout only', () {
    final session = newSession()..loadFailed('net::ERR_FAILED');

    expect(session.beginReplacement(_paged), isFalse);
    expect(session.beginReplacement(_scrolled), isTrue);
  });

  test('a renderer that dies after the book showed waits for a new viewer', () {
    final session = newSession()..loaded();
    heard.clear();

    session.rendererDied();
    session.rendererDied();
    expect(session.phase, ViewerPhase.rendererGone);
    expect(session.isLoaded, isTrue);
    expect(heard, ['rendererGone']);
    expect(session.beginReplacement(_paged), isTrue, reason: 'same layout');
  });

  test('a renderer that dies while the book opens fails the load', () {
    final session = newSession()..rendererDied();

    expect(session.phase, ViewerPhase.failed);
    expect(session.isLoaded, isFalse);
    expect(heard, ['failed: web view stopped']);
    expect(session.beginReplacement(_paged), isFalse);
  });
}
