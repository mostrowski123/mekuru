import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/backup/presentation/providers/backup_providers.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared/file_dialog_fakes.dart';
import 'test_app.dart';

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
  late Future<List<String>?> Function() nextPick;
  late _RecordingImportNotifier importer;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nextPick = () async => null;
    fakeFilePicker((_) => nextPick());
    importer = _RecordingImportNotifier();
  });

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
    final pick = Completer<List<String>?>();
    nextPick = () => pick.future;
    await openDictionaryManager(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(DictionaryManagerScreen), findsNothing);

    pick.complete(['/picked/jmdict.zip']);
    await tester.pumpAndSettle();

    expect(importer.imported, ['/picked/jmdict.zip']);
  });

  // already_active: a tap while the previous pick is still copying its file.
  // unknown_activity: the system picker came back without a file.
  for (final code in ['already_active', 'unknown_activity']) {
    testWidgets('a pick that fails with $code does nothing', (tester) async {
      nextPick = () async => throw PlatformException(code: code);
      await openDictionaryManager(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(importer.imported, isEmpty);
      expect(find.byType(DictionaryManagerScreen), findsOneWidget);
    });
  }

  // MEKURU-2Z: an e-reader with no system file picker.
  testWidgets('a device with no file picker says so', (tester) async {
    nextPick = () async => throw PlatformException(code: 'explorer_not_found');
    await openDictionaryManager(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        "This device has no file picker, so Mekuru can't open files from storage here.",
      ),
      findsOneWidget,
    );
  });
}
