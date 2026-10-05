import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/background_work.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/background_work');
  late List<MethodCall> calls;
  late BackgroundWork work;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'begin' ? true : null;
        });
    work = BackgroundWork.forTesting(channel);
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<void> expireFromNative() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('expired')),
          (_) {},
        );
  }

  test(
    'one system task covers every job, with their combined progress',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      work.start('download:a', BackgroundJobKind.download, onStopped: () {});
      work.start('ocr:1', BackgroundJobKind.scan, onStopped: () {});
      work.progress('download:a', 0.5);
      work.progress('ocr:1', 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(calls.where((c) => c.method == 'begin'), hasLength(1));
      final update = calls.lastWhere((c) => c.method == 'update');
      expect(update.arguments['total'], 2000);
      expect(update.arguments['completed'], 750);
      expect(update.arguments['subtitle'], '37%');

      work.finish('download:a');
      expect(calls.where((c) => c.method == 'end'), isEmpty);
      work.finish('ocr:1');
      expect(calls.last.method, 'end');
      expect(calls.last.arguments, true);
    },
  );

  test('the last progress reaches iOS before the task ends', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    work.start('dictionary:a', BackgroundJobKind.dictionary, onStopped: () {});
    work.progress('dictionary:a', 0.95);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // Inside the throttle window: only finish() can send it.
    work.progress('dictionary:a', 1.0);
    work.finish('dictionary:a');

    expect(calls.map((c) => c.method).toList().sublist(calls.length - 2), [
      'update',
      'end',
    ]);
    final update = calls[calls.length - 2];
    expect(update.arguments['completed'], update.arguments['total']);
  });

  test('dictionary downloads have their own words in the text', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    work.text =
        ({
          required int downloads,
          required int scans,
          required int dictionaries,
          required int percent,
        }) => (title: '$downloads/$scans/$dictionaries', subtitle: '');
    work.start('dictionary:a', BackgroundJobKind.dictionary, onStopped: () {});
    work.start('download:b', BackgroundJobKind.download, onStopped: () {});
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(
      calls.lastWhere((c) => c.method == 'update').arguments['title'],
      '1/0/1',
    );
  });

  test('when iOS ends the task, every job is stopped', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final stopped = <String>[];
    work.start(
      'download:a',
      BackgroundJobKind.download,
      onStopped: () => stopped.add('a'),
    );
    work.start(
      'ocr:1',
      BackgroundJobKind.scan,
      onStopped: () => stopped.add('1'),
    );

    await expireFromNative();

    expect(stopped, unorderedEquals(['a', '1']));
    expect(work.isRunning('download:a'), isFalse);
    // New work opens a new task.
    work.start('download:b', BackgroundJobKind.download, onStopped: () {});
    expect(calls.where((c) => c.method == 'begin'), hasLength(2));
  });

  test('does nothing off iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    work.start('download:a', BackgroundJobKind.download, onStopped: () {});
    work.progress('download:a', 0.5);
    work.finish('download:a');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(calls, isEmpty);
  });
}
