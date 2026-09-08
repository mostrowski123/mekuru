import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/full_backup_job_api.dart';
import 'package:mekuru/features/backup/presentation/providers/full_backup_job_provider.dart';
import 'package:mekuru/features/backup/presentation/screens/full_backup_job_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/shared/utils/format_bytes.dart';

import '../../test_app.dart';
import 'fake_full_backup_job_api.dart';

/// The job page is the only thing reachable while a job exists: it covers
/// the app, shows progress, offers a guarded cancel, and shows the outcome
/// until acknowledged.
void main() {
  final l10n = AppLocalizationsEn();
  late FakeFullBackupJobApi api;
  late int exitCalls;

  setUp(() {
    api = FakeFullBackupJobApi();
    exitCalls = 0;
  });

  /// Lets the notifier see the job disappear so no poll timer is pending.
  Future<void> settle(WidgetTester tester, ProviderContainer container) async {
    api.current = FullBackupJobStatus.none;
    await container.read(fullBackupJobProvider.notifier).refresh();
    await tester.pump();
  }

  Future<ProviderContainer> pumpGate(
    WidgetTester tester, {
    required FullBackupJobStatus status,
  }) async {
    api.current = status;
    final container = ProviderContainer(
      overrides: [
        fullBackupJobApiProvider.overrideWithValue(api),
        appExitProvider.overrideWithValue(() async => exitCalls++),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: const FullBackupJobGate(
            child: Scaffold(body: Center(child: Text('the app'))),
          ),
        ),
      ),
    );
    await container.read(fullBackupJobProvider.notifier).refresh();
    await tester.pump();
    return container;
  }

  testWidgets('a job found at cold start keeps the app unbuilt until Done', (
    tester,
  ) async {
    api.current = const FullBackupJobStatus(
      lifecycle: FullBackupJobLifecycle.done,
      bytes: 10,
    );
    api.result = api.current;
    final container = ProviderContainer(
      overrides: [
        fullBackupJobApiProvider.overrideWithValue(api),
        initialFullBackupJobPendingProvider.overrideWithValue(true),
        appExitProvider.overrideWithValue(() async => exitCalls++),
      ],
    );
    addTearDown(container.dispose);
    var appBuilds = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildLocalizedTestApp(
          home: FullBackupJobGate(
            child: Builder(
              builder: (_) {
                appBuilds++;
                return const Scaffold(body: Text('the app'));
              },
            ),
          ),
        ),
      ),
    );
    expect(find.byType(FullBackupJobScreen), findsOneWidget);
    expect(appBuilds, 0);

    await container.read(fullBackupJobProvider.notifier).refresh();
    await tester.pump();
    await tester.tap(find.text(l10n.backupFullJobDone));
    await tester.pump();
    await tester.pump();
    expect(find.text('the app').hitTestable(), findsOneWidget);
    expect(appBuilds, 1);
  });

  testWidgets('idle: the app shows and the page does not', (tester) async {
    await pumpGate(tester, status: FullBackupJobStatus.none);
    expect(find.text('the app').hitTestable(), findsOneWidget);
    expect(find.byType(FullBackupJobScreen), findsNothing);
  });

  testWidgets('running: covers the app with phase, progress and a hint', (
    tester,
  ) async {
    final container = await pumpGate(
      tester,
      status: const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.running,
        phase: 'writing',
        done: 50 * 1024 * 1024,
        total: 100 * 1024 * 1024,
      ),
    );

    expect(find.text('the app').hitTestable(), findsNothing);
    expect(find.text(l10n.backupFullJobExportTitle), findsOneWidget);
    expect(find.text(l10n.backupFullJobPhaseWriting), findsOneWidget);
    expect(find.text(l10n.backupFullJobBackgroundHint), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.5, 0.001));
    expect(
      find.text(
        l10n.backupFullProgressBytes(
          done: formatBytes(50 * 1024 * 1024),
          total: formatBytes(100 * 1024 * 1024),
        ),
      ),
      findsOneWidget,
    );
    await settle(tester, container);
  });

  testWidgets('cancel asks first, then forwards to the service', (
    tester,
  ) async {
    final container = await pumpGate(
      tester,
      status: const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.running,
        kind: FullBackupJobKind.restore,
        phase: 'extracting',
        done: 1,
        total: 4,
      ),
    );
    expect(find.text(l10n.backupFullJobRestoreTitle), findsOneWidget);

    await tester.tap(find.text(l10n.commonCancel));
    await tester.pump();
    expect(find.text(l10n.backupFullJobCancelConfirmRestore), findsOneWidget);
    expect(api.calls, isNot(contains('cancel')));

    await tester.tap(find.text(l10n.backupFullJobKeepGoing));
    await tester.pump();
    expect(find.text(l10n.backupFullJobCancelConfirmRestore), findsNothing);

    await tester.tap(find.text(l10n.commonCancel));
    await tester.pump();
    api.current = const FullBackupJobStatus(
      lifecycle: FullBackupJobLifecycle.cancelled,
      kind: FullBackupJobKind.restore,
    );
    await tester.tap(find.text(l10n.backupFullJobStop));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('cancel'));
    expect(find.text(l10n.backupFullCancelled), findsOneWidget);
    await settle(tester, container);
  });

  testWidgets('a paused job explains itself', (tester) async {
    final container = await pumpGate(
      tester,
      status: const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.paused,
        error: 'IOException',
      ),
    );
    expect(
      find.text(l10n.backupFullJobPaused(details: 'IOException')),
      findsOneWidget,
    );
    await settle(tester, container);
  });

  testWidgets('a finished export shows the size and Done reveals the app', (
    tester,
  ) async {
    await pumpGate(
      tester,
      status: const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.done,
        bytes: 2048,
        skippedFiles: 2,
        renamed: false,
      ),
    );
    expect(
      find.text(l10n.backupFullExported(size: formatBytes(2048))),
      findsOneWidget,
    );
    expect(
      find.text(l10n.backupFullExportedWithSkipped(count: 2)),
      findsOneWidget,
    );
    expect(find.text(l10n.backupFullJobRenameFailed), findsOneWidget);

    api.current = FullBackupJobStatus.none;
    await tester.tap(find.text(l10n.backupFullJobDone));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('consumeResult'));
    expect(find.text('the app').hitTestable(), findsOneWidget);
  });

  testWidgets('a finished restore offers to close Mekuru', (tester) async {
    await pumpGate(
      tester,
      status: const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.done,
        kind: FullBackupJobKind.restore,
      ),
    );
    expect(find.text(l10n.backupFullRestartTitle), findsOneWidget);
    expect(find.text(l10n.backupFullRestartBody), findsOneWidget);
    expect(exitCalls, 0);

    await tester.tap(find.text(l10n.backupFullRestartButton));
    await tester.pump();
    expect(exitCalls, 1);
  });

  testWidgets('a failure names the code and Close dismisses it', (
    tester,
  ) async {
    await pumpGate(
      tester,
      status: const FullBackupJobStatus(
        lifecycle: FullBackupJobLifecycle.failed,
        kind: FullBackupJobKind.restore,
        error: 'corrupt_archive',
      ),
    );
    expect(
      find.text(l10n.backupFullRestoreFailed(details: 'corrupt_archive')),
      findsOneWidget,
    );
    api.current = FullBackupJobStatus.none;
    await tester.tap(find.text(l10n.backupFullJobClose));
    await tester.pump();
    await tester.pump();
    expect(find.byType(FullBackupJobScreen), findsNothing);
  });
}
