import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/file_dialog_fakes.dart';
import '../../../shared/test_database.dart';
import '../../../test_app.dart';

void main() {
  final ja = AppLocalizationsJa();
  late AppDatabase db;
  final logs = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    logs.clear();
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        logs.add(message);
    usageAnalyticsSinkOverride = (_, _) {};
    usageIssueSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    usageIssueSinkOverride = null;
    await db.close();
  });

  Future<void> pumpLibrary(
    WidgetTester tester, {
    Stream<List<Book>> Function()? books,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          if (books != null) booksProvider.overrideWith((ref) => books()),
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Unmounts the tree so drift's streams close before the database does.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a library that cannot load says so in Japanese', (tester) async {
    await pumpLibrary(
      tester,
      books: () => Stream.error(
        Exception('SqliteException(11): database disk image is malformed'),
      ),
    );
    // Riverpod tries a failed stream again for about a minute first.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 10));
    }

    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text(ja.commonLoadFailed), findsOneWidget);
    expect(logs, contains('library.books_load_failed'));
    await unmount(tester);
  });

  testWidgets('a picked folder that cannot be read says so in Japanese', (
    tester,
  ) async {
    final gone = p.join(Directory.systemTemp.path, '秘密のフォルダ_gone');
    fakeChannel(const MethodChannel('mekuru/ios_files'), (_) => gone);
    await pumpLibrary(tester);

    await tester.tap(find.text(ja.libraryImportManga));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ja.libraryImportMokuroFolder));
    // Listing the folder is real file IO.
    for (var i = 0; i < 50 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('秘密'), findsNothing);
    expect(find.text(ja.libraryReadFolderFailed), findsOneWidget);
    expect(logs, contains('library.folder_read_failed'));
    await unmount(tester);
  });
}
