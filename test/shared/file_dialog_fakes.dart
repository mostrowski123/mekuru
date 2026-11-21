import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The channel file_picker opens the system picker through.
const filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

/// Answers [channel] with [answer], as the platform would, until the test
/// ends. Throw a [PlatformException] in [answer] to fail a call.
void fakeChannel(
  MethodChannel channel,
  FutureOr<Object?> Function(MethodCall call) answer,
) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async => answer(call));
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// Answers file_picker's picks with [answer]: the picked paths, or null for
/// a cancel. Throw a [PlatformException] in [answer] to fail the pick.
void fakeFilePicker(FutureOr<List<String>?> Function(MethodCall call) answer) =>
    fakeChannel(filePickerChannel, (call) async {
      final paths = await answer(call);
      return paths == null
          ? null
          : [
              for (final path in paths)
                {'path': path, 'name': p.basename(path), 'size': 0},
            ];
    });
