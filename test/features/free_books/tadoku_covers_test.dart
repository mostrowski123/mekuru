import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/free_books/data/services/tadoku_covers.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('tadoku_covers_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uri url(int i) => Uri.parse('https://tadoku.org/wp/cover$i.jpg');

  Future<void> writeCover(String path) => File(path).writeAsBytes([1, 2, 3]);

  test('downloads a cover once, then reads it from disk', () async {
    var fetches = 0;
    final covers = TadokuCovers(
      Future.value(dir),
      fetch: (_, path) async {
        fetches++;
        await writeCover(path);
      },
    );

    final first = await covers.cover(url(1));
    final second = await covers.cover(url(1));

    expect(first.path, second.path);
    expect(first.readAsBytesSync(), [1, 2, 3]);
    expect(fetches, 1);
    // The next launch finds it on disk too.
    final nextLaunch = TadokuCovers(
      Future.value(dir),
      fetch: (_, _) async => fail('downloaded again'),
    );
    expect((await nextLaunch.cover(url(1))).path, first.path);
  });

  test('a cover asked for while it downloads is downloaded once', () async {
    final gate = Completer<void>();
    var fetches = 0;
    final covers = TadokuCovers(
      Future.value(dir),
      fetch: (_, path) async {
        fetches++;
        await gate.future;
        await writeCover(path);
      },
    );

    final first = covers.cover(url(1));
    final second = covers.cover(url(1));
    gate.complete();

    expect((await first).path, (await second).path);
    expect(fetches, 1);
  });

  test('downloads at most two covers at a time', () async {
    var running = 0;
    var most = 0;
    final covers = TadokuCovers(
      Future.value(dir),
      fetch: (_, path) async {
        most = math.max(most, ++running);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await writeCover(path);
        running--;
      },
    );

    final files = await Future.wait([
      for (var i = 0; i < 12; i++) covers.cover(url(i)),
    ]);

    expect(most, 2);
    expect(files.map((f) => f.existsSync()), everyElement(isTrue));
  });

  test('a failed cover waits a minute before another try', () async {
    var now = DateTime(2026, 10, 5);
    var fetches = 0;
    final covers = TadokuCovers(
      Future.value(dir),
      now: () => now,
      fetch: (_, _) async {
        fetches++;
        throw const SocketException('offline');
      },
    );

    await expectLater(covers.cover(url(1)), throwsA(isA<SocketException>()));
    // Scrolled away and back: no new request yet.
    await expectLater(covers.cover(url(1)), throwsStateError);
    expect(fetches, 1);

    now = now.add(const Duration(minutes: 1));
    await expectLater(covers.cover(url(1)), throwsA(isA<SocketException>()));
    expect(fetches, 2);
  });
}
