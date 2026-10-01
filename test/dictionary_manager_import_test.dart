import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// Answers each pick with whatever the test scripted.
class _ScriptedFilePicker extends FilePickerPlatform {
  Future<FilePickerResult?> Function() next = () async => null;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) => next();
}

/// Records the files the screen hands over instead of importing them.
class _RecordingImportNotifier extends DictionaryImportNotifier {
  final imported = <String>[];

  @override
  Future<void> importDictionary(String filePath) async =>
      imported.add(filePath);
}

/// MEKURU-1W/1X: on Android the picker copies the chosen file before it
/// answers (~18 s for a large zip), so users tap import again or leave the
/// screen while it works.
void main() {
  late _ScriptedFilePicker picker;
  late FilePickerPlatform originalPicker;
  late _RecordingImportNotifier importer;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPicker = FilePickerPlatform.instance;
    picker = _ScriptedFilePicker();
    FilePickerPlatform.instance = picker;
    importer = _RecordingImportNotifier();
  });

  tearDown(() => FilePickerPlatform.instance = originalPicker);

  Future<void> openDictionaryManager(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dictionaryImportProvider.overrideWith(() => importer),
          dictionariesProvider.overrideWith((ref) => Stream.value([])),
          pendingDictionaryRestorePreviewProvider.overrideWith(
            (ref) async => null,
          ),
        ],
        child: buildLocalizedTestApp(
          home: Navigator(
            key: navigatorKey,
            onGenerateRoute: (_) =>
                MaterialPageRoute(builder: (_) => const Scaffold()),
          ),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const DictionaryManagerScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('imports the picked file even after the screen was closed', (
    tester,
  ) async {
    final pick = Completer<FilePickerResult?>();
    picker.next = () => pick.future;
    await openDictionaryManager(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(DictionaryManagerScreen), findsNothing);

    pick.complete(
      FilePickerResult([
        PlatformFile(name: 'jmdict.zip', size: 0, path: '/picked/jmdict.zip'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(importer.imported, ['/picked/jmdict.zip']);
  });

  // already_active: a tap while the previous pick is still copying its file.
  // unknown_activity: the system picker came back without a file.
  for (final code in ['already_active', 'unknown_activity']) {
    testWidgets('a pick that fails with $code does nothing', (tester) async {
      picker.next = () async => throw PlatformException(code: code);
      await openDictionaryManager(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(importer.imported, isEmpty);
      expect(find.byType(DictionaryManagerScreen), findsOneWidget);
    });
  }
}
