import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';

import 'fake_full_backup_job_api.dart';

/// The notifier is the app's view of the native job: it must block the app
/// exactly while a job exists, follow it by polling, and hand the outcome
/// to the page once. `testWidgets` is used for its fake clock, so the poll
/// timer can be advanced with `tester.pump`.
void main() {
  late FakeFullBackupJobApi api;
  late int exitCalls;

  const poll = FullBackupJobNotifier.pollEvery;
  const running = FullBackupJobStatus(
    lifecycle: FullBackupJobLifecycle.running,
    phase: 'writing',
    done: 10,
    total: 100,
  );
  const paused = FullBackupJobStatus(
    lifecycle: FullBackupJobLifecycle.paused,
    done: 10,
    total: 100,
  );
  const exportDone = FullBackupJobStatus(
    lifecycle: FullBackupJobLifecycle.done,
    location: '/x/a.zip',
    bytes: 777,
    entries: 3,
  );
  const restoreDone = FullBackupJobStatus(
    lifecycle: FullBackupJobLifecycle.done,
    kind: FullBackupJobKind.restore,
  );

  setUp(() {
    api = FakeFullBackupJobApi();
    exitCalls = 0;
  });

  ProviderContainer container({bool initialPending = false}) {
    final c = ProviderContainer(
      overrides: [
        fullBackupJobApiProvider.overrideWithValue(api),
        initialFullBackupJobPendingProvider.overrideWithValue(initialPending),
        appExitProvider.overrideWithValue(() async => exitCalls++),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  int polls() => api.calls.where((c) => c == 'status').length;

  /// Ends a test that left a job active: the next poll sees no job and the
  /// notifier stops its timer (a pending timer fails the test otherwise).
  Future<void> settle(WidgetTester tester, ProviderContainer c) async {
    api.current = FullBackupJobStatus.none;
    await tester.pump(poll);
    expect(c.read(fullBackupJobProvider).blocksApp, isFalse);
  }

  testWidgets('starts idle and does not touch the service', (tester) async {
    final c = container();
    expect(c.read(fullBackupJobProvider).blocksApp, isFalse);
    await tester.pump(poll * 2);
    expect(api.calls, isEmpty);
  });

  testWidgets(
    'a pending job found at boot blocks the app before the first poll',
    (tester) async {
      api.current = running;
      final c = container(initialPending: true);
      expect(c.read(fullBackupJobProvider).stage, FullBackupJobStage.active);
      expect(polls(), 0);

      await tester.pump(poll);
      final state = c.read(fullBackupJobProvider);
      expect(state.status.phase, 'writing');
      expect(state.status.done, 10);
      expect(polls(), 1);
      await settle(tester, c);
    },
  );

  testWidgets('polls while active and stops on a terminal status', (
    tester,
  ) async {
    api.current = running;
    final c = container();
    await c
        .read(fullBackupJobProvider.notifier)
        .jobCommitted(FullBackupJobKind.export);
    expect(c.read(fullBackupJobProvider).stage, FullBackupJobStage.active);

    await tester.pump(poll * 3);
    expect(polls(), greaterThanOrEqualTo(3));

    api.current = exportDone;
    await tester.pump(poll);
    final state = c.read(fullBackupJobProvider);
    expect(state.stage, FullBackupJobStage.terminal);
    expect(state.status.bytes, 777);
    expect(state.blocksApp, isTrue);

    final after = polls();
    await tester.pump(poll * 3);
    expect(polls(), after);
  });

  testWidgets('a paused job still blocks the app and keeps polling', (
    tester,
  ) async {
    api.current = paused;
    final c = container(initialPending: true);
    c.read(fullBackupJobProvider);
    await tester.pump(poll);
    expect(c.read(fullBackupJobProvider).stage, FullBackupJobStage.active);
    expect(
      c.read(fullBackupJobProvider).status.lifecycle,
      FullBackupJobLifecycle.paused,
    );
    final before = polls();
    await tester.pump(poll);
    expect(polls(), greaterThan(before));
    await settle(tester, c);
  });

  testWidgets('preparing blocks the app without polling and can be released', (
    tester,
  ) async {
    final c = container();
    final notifier = c.read(fullBackupJobProvider.notifier);
    notifier.markPreparing(FullBackupJobKind.restore);
    expect(c.read(fullBackupJobProvider).stage, FullBackupJobStage.preparing);
    expect(c.read(fullBackupJobProvider).kind, FullBackupJobKind.restore);

    await tester.pump(poll * 2);
    expect(api.calls, isEmpty);

    notifier.preparationFailed();
    expect(c.read(fullBackupJobProvider).blocksApp, isFalse);
  });

  testWidgets('dismiss consumes the result and releases the app', (
    tester,
  ) async {
    api.current = exportDone;
    api.result = exportDone;
    final c = container();
    final notifier = c.read(fullBackupJobProvider.notifier);
    await notifier.refresh();
    expect(c.read(fullBackupJobProvider).stage, FullBackupJobStage.terminal);

    await notifier.dismiss();
    expect(api.calls, contains('consumeResult'));
    expect(api.result, isNull);
    expect(c.read(fullBackupJobProvider).blocksApp, isFalse);
  });

  testWidgets('cancel forwards to the service and re-reads', (tester) async {
    api.current = running;
    final c = container();
    final notifier = c.read(fullBackupJobProvider.notifier);
    await notifier.refresh();

    api.current = const FullBackupJobStatus(
      lifecycle: FullBackupJobLifecycle.cancelled,
    );
    await notifier.cancel();
    expect(api.calls, contains('cancel'));
    expect(
      c.read(fullBackupJobProvider).status.lifecycle,
      FullBackupJobLifecycle.cancelled,
    );
  });

  testWidgets('a finished restore exits the app on request only', (
    tester,
  ) async {
    api.current = restoreDone;
    final c = container();
    final notifier = c.read(fullBackupJobProvider.notifier);
    await notifier.refresh();
    expect(c.read(fullBackupJobProvider).kind, FullBackupJobKind.restore);
    expect(exitCalls, 0);

    await notifier.exitApp();
    expect(exitCalls, 1);
  });

  testWidgets('a job that vanished releases the app', (tester) async {
    api.current = running;
    final c = container();
    final notifier = c.read(fullBackupJobProvider.notifier);
    await notifier.refresh();
    expect(c.read(fullBackupJobProvider).blocksApp, isTrue);

    api.current = FullBackupJobStatus.none;
    await notifier.refresh();
    expect(c.read(fullBackupJobProvider).blocksApp, isFalse);
    await tester.pump(poll * 2);
  });
}
