import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/file_pick.dart';
import 'package:path/path.dart' as p;

import '../../shared/file_dialog_fakes.dart';

const _saf = MethodChannel('mekuru/android_saf');
const _iosFiles = MethodChannel('mekuru/ios_files');

/// Codes that mean a dialog was already open, or there was no screen to
/// show one on: nothing happened, so nothing to say.
const _cancelCodes = [
  'already_active',
  'multiple_request',
  'busy',
  'picker_unavailable',
  'unknown_activity',
  'no_activity',
];

Matcher _done(Object? value) =>
    isA<FileDialogDone<Object?>>().having((r) => r.value, 'value', value);

Matcher _failed(FileDialogFailure failure) => isA<FileDialogFailed<Object?>>()
    .having((r) => r.failure, 'failure', failure);

final _cancelled = isA<FileDialogCancelled<Object?>>();

/// The platform's error comes back through the channel as a new exception.
Matcher _throwsCode(String code) =>
    throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('on ${platform.name}', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      group('pickFiles', () {
        test('hands back the picked paths, asking for what the caller '
            'wants', () async {
          final calls = <MethodCall>[];
          fakeFilePicker((call) {
            calls.add(call);
            return ['/cache/a.epub', '/cache/b.epub'];
          });

          expect(
            await pickFiles(extensions: ['epub'], multiple: true),
            _done(['/cache/a.epub', '/cache/b.epub']),
          );
          expect(await pickFiles(images: true), _done(['/cache/a.epub']));
          expect(await pickFiles(), _done(['/cache/a.epub']));

          expect(
            [
              for (final call in calls)
                '${call.method} '
                    '${(call.arguments as Map)['allowedExtensions']} '
                    'multiple: ${(call.arguments as Map)['allowMultipleSelection']}',
            ],
            [
              'custom [epub] multiple: true',
              'image null multiple: false',
              'any null multiple: false',
            ],
          );
        });

        test('a closed picker is cancelled', () async {
          fakeFilePicker((_) => null);
          expect(await pickFiles(), _cancelled);
        });

        for (final code in _cancelCodes) {
          test('$code is cancelled', () async {
            fakeFilePicker((_) => throw PlatformException(code: code));
            expect(await pickFiles(), _cancelled);
          });
        }

        test('no picker app on the device', () async {
          fakeFilePicker(
            (_) => throw PlatformException(code: 'explorer_not_found'),
          );
          expect(await pickFiles(), _failed(FileDialogFailure.noPicker));
        });

        test('a file name too long to copy', () async {
          fakeFilePicker(
            (_) => throw PlatformException(
              code: 'file_picker_error',
              message:
                  '/data/user/0/x/cache/本.epub: open failed: '
                  'ENAMETOOLONG (File name too long)',
            ),
          );
          expect(await pickFiles(), _failed(FileDialogFailure.nameTooLong));
        });

        test('a missing plugin is no picker', () async {
          expect(await pickFiles(), _failed(FileDialogFailure.noPicker));
        });

        test('anything else is a bug, and is rethrown', () async {
          for (final error in [
            PlatformException(code: 'out_of_memory'),
            PlatformException(code: 'file_picker_error', message: 'EIO'),
          ]) {
            fakeFilePicker((_) => throw error);
            await expectLater(pickFiles(), _throwsCode(error.code));
          }
        });
      });

      group('the folder and zip pickers', () {
        final pickers = [
          (
            pickAndroidFolder,
            _saf,
            'pickDirectory',
            {'treeUri': 'content://tree/1', 'treeDocumentId': 'primary:Manga'},
            isA<AndroidSafDirectoryAccess>()
                .having((a) => a.treeUri, 'treeUri', 'content://tree/1')
                .having(
                  (a) => a.treeDocumentId,
                  'treeDocumentId',
                  'primary:Manga',
                ),
          ),
          (
            pickAndroidZip,
            _saf,
            'pickDocument',
            {'uri': 'content://doc/1', 'sizeBytes': 4321},
            isA<AndroidSafDocument>()
                .having((d) => d.uri, 'uri', 'content://doc/1')
                .having((d) => d.sizeBytes, 'sizeBytes', 4321),
          ),
          (pickIosFolder, _iosFiles, 'pickFolder', '/Manga', '/Manga'),
          (pickIosZip, _iosFiles, 'pickZip', '/tmp/b.zip', '/tmp/b.zip'),
        ];
        for (final (pick, channel, method, answer, picked) in pickers) {
          test(
            '$method: picked, closed, busy, no picker app, missing plugin',
            () async {
              final calls = <String>[];
              Object? next;
              fakeChannel(channel, (call) {
                calls.add(call.method);
                if (next is PlatformException) throw next;
                return next;
              });

              next = answer;
              expect(await pick(), _done(picked));
              next = null;
              expect(await pick(), _cancelled);
              for (final code in ['busy', 'picker_unavailable']) {
                next = PlatformException(code: code);
                expect(await pick(), _cancelled);
              }
              next = PlatformException(code: 'explorer_not_found');
              expect(await pick(), _failed(FileDialogFailure.noPicker));
              expect(calls, everyElement(method));

              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(channel, null);
              expect(await pick(), _failed(FileDialogFailure.noPicker));
            },
          );
        }
      });

      group('saveFile', () {
        late Directory dir;
        late File file;
        final calls = <(String, MethodCall)>[];

        /// Answers both save channels with [answer]; a "saved" on iOS moves
        /// the file out, as the document picker does.
        void answerSaves(Object? Function() answer) {
          for (final channel in [_saf, _iosFiles]) {
            fakeChannel(channel, (call) {
              calls.add((channel.name, call));
              final reply = answer();
              if (reply is PlatformException) throw reply;
              if (reply == true && call.method == 'exportFile') {
                file.renameSync(p.join(dir.path, 'moved.epub'));
              }
              return reply;
            });
          }
        }

        setUp(() {
          calls.clear();
          dir = Directory.systemTemp.createTempSync('file_pick_save_');
          file = File(p.join(dir.path, '本 (furigana).epub'))
            ..writeAsStringSync('book');
        });

        tearDown(() => dir.deleteSync(recursive: true));

        test('only the path crosses the channel', () async {
          answerSaves(() => true);

          expect(
            await saveFile(file.path, mimeType: 'application/epub+zip'),
            _done(null),
          );

          final (channel, call) = calls.single;
          if (platform == TargetPlatform.iOS) {
            expect((channel, call.method), ('mekuru/ios_files', 'exportFile'));
            expect(call.arguments, file.path);
          } else {
            expect(
              (channel, call.method),
              ('mekuru/android_saf', 'saveDocument'),
            );
            expect(call.arguments, {
              'path': file.path,
              'name': '本 (furigana).epub',
              'mimeType': 'application/epub+zip',
            });
          }
          expect(file.existsSync(), isFalse);
        });

        test('a cancelled save is cancelled, and the file is gone', () async {
          answerSaves(() => false);
          expect(await saveFile(file.path, mimeType: 'x/y'), _cancelled);
          expect(file.existsSync(), isFalse);
        });

        test('a busy save dialog is cancelled, and the file is gone', () async {
          answerSaves(() => PlatformException(code: 'busy'));
          expect(await saveFile(file.path, mimeType: 'x/y'), _cancelled);
          expect(file.existsSync(), isFalse);
        });

        test('no save dialog app fails, and the file is gone', () async {
          answerSaves(() => PlatformException(code: 'explorer_not_found'));
          expect(
            await saveFile(file.path, mimeType: 'x/y'),
            _failed(FileDialogFailure.noSaveDialog),
          );
          expect(file.existsSync(), isFalse);
        });

        test('a missing plugin fails, and the file is gone', () async {
          expect(
            await saveFile(file.path, mimeType: 'x/y'),
            _failed(FileDialogFailure.noSaveDialog),
          );
          expect(file.existsSync(), isFalse);
        });

        test('a failed copy is rethrown, and the file is gone', () async {
          answerSaves(() => PlatformException(code: 'saf_io_error'));
          await expectLater(
            saveFile(file.path, mimeType: 'x/y'),
            _throwsCode('saf_io_error'),
          );
          expect(file.existsSync(), isFalse);
        });

        test('keepIfNotSaved keeps an unsaved file for another try', () async {
          answerSaves(() => false);
          expect(
            await saveFile(file.path, mimeType: 'x/y', keepIfNotSaved: true),
            _cancelled,
          );
          expect(file.existsSync(), isTrue);

          answerSaves(() => true);
          expect(
            await saveFile(file.path, mimeType: 'x/y', keepIfNotSaved: true),
            _done(null),
          );
          expect(file.existsSync(), isFalse);
        });
      });
    });
  }

  test('map turns a picked value and keeps the other outcomes', () {
    expect(const FileDialogDone(2).map((v) => '$v'), _done('2'));
    expect(const FileDialogCancelled<int>().map((v) => '$v'), _cancelled);
    expect(
      const FileDialogFailed<int>(FileDialogFailure.noPicker).map((v) => '$v'),
      _failed(FileDialogFailure.noPicker),
    );
  });
}
