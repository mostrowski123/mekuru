import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/android_saf_service.dart';
import 'package:mekuru/features/backup/data/models/backup_kind.dart';
import 'package:mekuru/features/backup/data/models/full_backup_endpoints.dart';
import 'package:mekuru/features/backup/data/models/full_backup_manifest.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart';
import 'package:mekuru/features/backup/data/services/staged_full_restore.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_full_backup_api.dart';

/// Drives the full backup screen state without any platform: the service,
/// the pickers and the process exit are all injected.
void main() {
  late FakeFullBackupApi api;
  late String? pickedTreeUri;
  late AndroidSafDocument? pickedDocument;
  late int exitCalls;
  late ProviderContainer container;
  late List<FullBackupState> states;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeFullBackupApi();
    pickedTreeUri = 'content://tree/backups';
    pickedDocument = const AndroidSafDocument(
      uri: 'content://doc/picked.zip',
      displayName: 'mekuru-full-backup.zip',
      sizeBytes: 4321,
    );
    exitCalls = 0;
    container = ProviderContainer(
      overrides: [
        fullBackupServiceProvider.overrideWith((ref) async => api),
        fullBackupPickersProvider.overrideWithValue(
          FullBackupPickers(
            pickExportTarget: () async {
              final uri = pickedTreeUri;
              return uri == null ? null : FullBackupTarget.tree(uri);
            },
            pickSource: () async {
              final document = pickedDocument;
              return document == null
                  ? null
                  : FullBackupSource.uri(
                      document.uri,
                      sizeBytes: document.sizeBytes,
                      displayName: document.displayName,
                    );
            },
          ),
        ),
        appExitProvider.overrideWithValue(() async => exitCalls++),
      ],
    );
    states = [];
    container.listen(
      fullBackupNotifierProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  });

  tearDown(() => container.dispose());

  FullBackupNotifier notifier() =>
      container.read(fullBackupNotifierProvider.notifier);
  FullBackupState state() => container.read(fullBackupNotifierProvider);

  group('exportToFolder', () {
    test('does nothing when the folder picker is dismissed', () async {
      pickedTreeUri = null;

      await notifier().exportToFolder();

      expect(api.calls, isEmpty);
      expect(state().isWorking, isFalse);
      expect(state().error, isNull);
    });

    test('exports into the picked folder and reports the size', () async {
      api.exportedBytes = 3 * 1024 * 1024;

      await notifier().exportToFolder();

      expect(api.calls, ['export']);
      expect(
        (api.exportTarget! as FullBackupTreeTarget).treeUri,
        'content://tree/backups',
      );
      expect(state().successMessage?.kind, BackupMessageKind.fullExported);
      expect(state().successMessage?.details, '3.0 MB');
      expect(state().isWorking, isFalse);
    });

    test(
      'mentions skipped files when the archiver could not read some',
      () async {
        api.skippedFiles = 2;

        await notifier().exportToFolder();

        expect(
          state().successMessage?.kind,
          BackupMessageKind.fullExportedWithSkipped,
        );
        expect(state().successMessage?.count, 2);
      },
    );

    test('surfaces progress while exporting', () async {
      api.progressToEmit = [(50, 200), (200, 200)];

      await notifier().exportToFolder();

      final exporting = states.where(
        (s) => s.phase == FullBackupPhase.exporting,
      );
      expect(exporting.map((s) => (s.done, s.total)), [(50, 200), (200, 200)]);
    });

    test('maps busy, space, cancel and unknown failures to messages', () async {
      final cases = <Object, (BackupMessageKind, String?)>{
        const FullBackupBusyException(): (BackupMessageKind.fullBusy, null),
        const InsufficientSpaceException(neededBytes: 2048): (
          BackupMessageKind.fullNotEnoughSpace,
          '2.0 KB',
        ),
        const FullBackupCancelledException(): (
          BackupMessageKind.fullCancelled,
          null,
        ),
        Exception('disk on fire'): (BackupMessageKind.fullFailed, null),
      };
      for (final entry in cases.entries) {
        api.exportError = entry.key;

        await notifier().exportToFolder();

        final (kind, details) = entry.value;
        expect(state().error?.kind, kind, reason: '${entry.key}');
        if (details != null) expect(state().error?.details, details);
        expect(state().isWorking, isFalse);
        notifier().clearState();
      }
      expect(state().error?.details, isNull);
    });
  });

  group('pickAndInspect', () {
    test(
      'returns null without inspecting when the picker is dismissed',
      () async {
        pickedDocument = null;

        expect(await notifier().pickAndInspect(), isNull);
        expect(api.calls, isEmpty);
      },
    );

    test('remembers the picked source and returns the preview', () async {
      final preview = await notifier().pickAndInspect();

      expect(preview?.manifest.bookCount, 7);
      expect(preview?.currentBookCount, 2);
      final source = state().source! as FullBackupUriSource;
      expect(source.uri, 'content://doc/picked.zip');
      expect(source.sizeBytes, 4321);
      expect(source.displayName, 'mekuru-full-backup.zip');
      expect(state().isWorking, isFalse);
    });

    test('maps validation failures to messages and returns null', () async {
      final cases = <Object, (BackupMessageKind, String?)>{
        const FullBackupTooNewException(
          appVersion: '1.40.0',
          format: 2,
          schemaVersion: 30,
        ): (
          BackupMessageKind.fullTooNew,
          '1.40.0',
        ),
        const WrongBackupKindException(BackupKind.readingData): (
          BackupMessageKind.wrongKindReadingData,
          null,
        ),
        const FullBackupFormatException('nope'): (
          BackupMessageKind.fullInvalid,
          null,
        ),
        const FullBackupPendingRestoreException(): (
          BackupMessageKind.fullPendingRestore,
          null,
        ),
        const InsufficientSpaceException(neededBytes: 1024 * 1024): (
          BackupMessageKind.fullNotEnoughSpace,
          '1.0 MB',
        ),
      };
      for (final entry in cases.entries) {
        api.inspectError = entry.key;

        expect(await notifier().pickAndInspect(), isNull);

        final (kind, details) = entry.value;
        expect(state().error?.kind, kind, reason: '${entry.key}');
        if (details != null) expect(state().error?.details, details);
        expect(state().source, isNull);
        notifier().clearState();
      }
    });
  });

  group('stageForRestart', () {
    test('does nothing without an inspected source', () async {
      expect(await notifier().stageForRestart(), isFalse);

      expect(api.calls, isEmpty);
      expect(exitCalls, 0);
    });

    test('stages the inspected source and reports ready to restart', () async {
      await notifier().pickAndInspect();
      final source = state().source;
      api.progressToEmit = [(10, 4321)];

      expect(await notifier().stageForRestart(), isTrue);

      expect(api.calls, ['inspect', 'stage']);
      expect(api.stagedSource, same(source));
      expect(
        states.any(
          (s) => s.phase == FullBackupPhase.extracting && s.done == 10,
        ),
        isTrue,
      );
      // Exiting is the screen's explicit last step, after its closing dialog.
      expect(exitCalls, 0);
      expect(state().readyToRestart, isTrue);
      expect(state().isWorking, isFalse);

      await notifier().exitApp();
      expect(exitCalls, 1);
    });

    test(
      'reports failure and stays restartable-false when staging fails',
      () async {
        await notifier().pickAndInspect();
        api.stageError = const FullBackupFormatException('bad zip');

        expect(await notifier().stageForRestart(), isFalse);

        expect(exitCalls, 0);
        expect(state().readyToRestart, isFalse);
        expect(state().error?.kind, BackupMessageKind.fullInvalid);
        expect(state().isWorking, isFalse);
      },
    );

    test('reports a cancelled extraction as cancelled', () async {
      await notifier().pickAndInspect();
      api.stageError = const FullBackupCancelledException();

      expect(await notifier().stageForRestart(), isFalse);

      expect(exitCalls, 0);
      expect(state().error?.kind, BackupMessageKind.fullCancelled);
    });
  });

  test('cancel forwards to the service', () async {
    await notifier().cancel();
    expect(api.calls, ['cancel']);
  });

  group('consumeFullRestoreResult', () {
    test('returns and clears the boot result', () async {
      SharedPreferences.setMockInitialValues({
        StagedFullRestore.resultPrefKey: 'ok',
      });

      expect(await consumeFullRestoreResult(), 'ok');
      expect(await consumeFullRestoreResult(), isNull);
    });
  });
}
