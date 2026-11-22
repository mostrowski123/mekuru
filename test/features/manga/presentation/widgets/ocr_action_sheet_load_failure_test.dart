import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/presentation/providers/local_ocr_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_action_sheet.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart' show SentryAttribute;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

/// The manga's folder: a name the user gave it, which never reaches the
/// screen or telemetry.
const _folder = '秘密の漫画';

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));
  late Directory root;
  final logs = <(String, Map<String, SentryAttribute>)>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('ocr-sheet-load');
    logs.clear();
    usageLogSinkOverride = (message, attributes, {required isWarning}) =>
        logs.add((message, attributes));
    usageAnalyticsSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    await root.delete(recursive: true);
  });

  /// Opens the sheet on the manga in [folder], read from disk as the app
  /// reads it.
  Future<void> openSheet(WidgetTester tester, String folder) async {
    final book = Book(
      id: 1,
      isFavorite: false,
      title: _folder,
      filePath: folder,
      bookType: 'manga',
      totalPages: 3,
      readProgress: 0,
      dateAdded: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localOcrJobsProvider.overrideWith((ref) => Stream.value(const [])),
          ocrProgressProvider(1).overrideWith((ref) => Stream.value(null)),
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: Scaffold(body: OcrActionSheet(book: book)),
        ),
      ),
    );
    // The page data is read from disk, outside the test's clock.
    for (var i = 0; i < 50; i++) {
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  void expectNothingLeaked() {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining(_folder), findsNothing);
    final failures = logs.where((log) => log.$1 == 'ocr.sheet_load_failed');
    expect(failures, hasLength(1));
    for (final attribute in failures.single.$2.values) {
      expect('${attribute.value}', isNot(contains(_folder)));
    }
  }

  testWidgets('a manga whose page data is gone says to import it again', (
    tester,
  ) async {
    await openSheet(tester, p.join(root.path, _folder));

    expectNothingLeaked();
    expect(find.text(ja.mangaReaderPagesMissing), findsOneWidget);
  });

  testWidgets('page data that cannot be read says it did not load', (
    tester,
  ) async {
    final folder = Directory(p.join(root.path, _folder))..createSync();
    File(
      p.join(folder.path, mangaPagesCacheFileName),
    ).writeAsStringSync('{"title": "$_folder", "pages": ');
    await openSheet(tester, folder.path);

    expectNothingLeaked();
    expect(find.text(ja.commonLoadFailed), findsOneWidget);
  });
}
