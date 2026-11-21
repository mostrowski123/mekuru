import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/data/models/epub_models.dart';
import 'package:mekuru/features/reader/presentation/viewer_session.dart';

const _page = 'epubcfi(/6/4!/4/2/1:0)';
const _location = EpubLocation(startCfi: _page, endCfi: _page, progress: 0);

void main() {
  late List<String> heard;

  ViewerSession firstSession() => ViewerSession.first((
    loaded: () => heard.add('loaded'),
    locationsReady: () => heard.add('locationsReady'),
    relocated: (EpubLocation location, {required bool trusted}) =>
        heard.add(trusted ? 'relocated trusted' : 'relocated untrusted'),
    failed: (String? description) =>
        heard.add('failed: ${description ?? 'web view stopped'}'),
    rendererGone: () => heard.add('rendererGone'),
  ));

  /// Past a watchdog started with a 1 ms timeout.
  Future<void> afterTimeout() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() => heard = []);

  test('a viewer loads, then reports every display', () {
    final session = firstSession();
    expect(session.phase, ViewerPhase.loading);
    expect(session.isLoaded, isFalse);

    session.loaded();
    session.loaded();
    expect(session.phase, ViewerPhase.ready);
    expect(session.isLoaded, isTrue);
    expect(heard, ['loaded', 'loaded']);
  });

  test('a page is trusted only once locations exist', () {
    final session = firstSession();
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

  test('a rebuild starts a session that knows nothing yet', () {
    final old = firstSession()
      ..loaded()
      ..locationsArrived()
      ..markStale();
    expect(old.beginReplacement(), isTrue);
    expect(old.beginReplacement(), isFalse, reason: 'one at a time');
    expect(old.isReplacing, isTrue);

    final session = old.next();
    heard.clear();
    expect(session.epoch, old.epoch + 1);
    expect(session.phase, ViewerPhase.loading);
    expect(session.isLoaded, isFalse);
    expect(session.locationsReady, isFalse);
    expect(session.isReplacing, isFalse);
    expect(session.takeStale(), isFalse);

    // Its first page comes before its own locations (f6ed8def).
    session.relocated(_location);
    expect(heard, ['relocated untrusted']);
  });

  test('what a replaced viewer still sends reaches nothing', () {
    final old = firstSession()..loaded();
    final session = old.next();
    heard.clear();

    old
      ..loaded()
      ..locationsArrived()
      ..relocated(_location)
      ..loadFailed('late')
      ..rendererDied();
    expect(heard, isEmpty);
    expect(old.phase, ViewerPhase.retired);
    expect(session.phase, ViewerPhase.loading);
    expect(session.locationsReady, isFalse);
  });

  test('a renderer that dies after the book showed waits for a new viewer', () {
    final session = firstSession()..loaded();
    heard.clear();

    session.rendererDied();
    session.rendererDied();
    expect(session.phase, ViewerPhase.rendererGone);
    expect(session.isLoaded, isTrue);
    expect(heard, ['rendererGone']);
    expect(session.beginReplacement(), isTrue);
  });

  test('a renderer that dies while the book opens fails the load', () {
    final session = firstSession()..rendererDied();

    expect(session.phase, ViewerPhase.failed);
    expect(session.isLoaded, isFalse);
    expect(heard, ['failed: web view stopped']);
    expect(session.beginReplacement(), isFalse);
  });

  test('a book that does not show in time fails the load', () async {
    final session = firstSession();
    var timedOut = 0;
    session.startWatchdog(const Duration(milliseconds: 1), () => timedOut++);

    await afterTimeout();
    expect(timedOut, 1);
    expect(session.phase, ViewerPhase.failed);

    // A late load changes nothing.
    session.loaded();
    expect(heard, isEmpty);
  });

  test('the watchdog does not overwrite a load error', () async {
    final session = firstSession();
    var timedOut = 0;
    session.startWatchdog(const Duration(milliseconds: 1), () => timedOut++);

    session.loadFailed('net::ERR_FAILED');
    await afterTimeout();
    expect(timedOut, 0);
    expect(heard, ['failed: net::ERR_FAILED']);

    // A second error in the same burst still shows.
    session.loadFailed('HTTP 404');
    expect(heard.last, 'failed: HTTP 404');
  });

  test(
    'a book that shows, or a viewer that goes, stops the watchdog',
    () async {
      var timedOut = 0;
      final loaded = firstSession()
        ..startWatchdog(const Duration(milliseconds: 1), () => timedOut++)
        ..loaded();
      final retired = firstSession()
        ..startWatchdog(const Duration(milliseconds: 1), () => timedOut++)
        ..retire();

      await afterTimeout();
      expect(timedOut, 0);
      expect(loaded.phase, ViewerPhase.ready);
      expect(retired.phase, ViewerPhase.retired);
    },
  );

  test(
    'a stale viewer is reported once, and a loading one is not replaced',
    () {
      final session = firstSession()..markStale();
      expect(session.beginReplacement(), isFalse);
      expect(session.takeStale(), isTrue);
      expect(session.takeStale(), isFalse);
    },
  );
}
