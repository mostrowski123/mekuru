import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/utils/storage_full.dart';
import 'package:mekuru/features/dictionary/data/repositories/dictionary_repository.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_importer.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/downloads/download.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:path/path.dart' as p;

import '../../test_app.dart';

/// A Yomitan zip of [entries] terms, each with a long gloss.
List<int> _zip(int entries) {
  final index = utf8.encode(jsonEncode({'title': 'Big', 'format': 3}));
  final bank = utf8.encode(
    jsonEncode([
      for (var i = 0; i < entries; i++)
        [
          '語$i',
          'ご$i',
          '',
          '',
          0,
          ['gloss ' * 40],
          i,
          '',
        ],
    ]),
  );
  return ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile('index.json', index.length, index))
      ..addFile(ArchiveFile('term_bank_1.json', bank.length, bank)),
  );
}

/// A dictionary import into a database that can't grow, as on a full phone.
/// The app's database runs on drift's background isolate, which hands the
/// SQLITE_FULL it hits to the app wrapped.
void main() {
  late Directory root;
  late AppDatabase db;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dictionary_full_disk_');
    db = AppDatabase(
      NativeDatabase.createInBackground(File(p.join(root.path, 'db.sqlite'))),
    );
    // Created now, then held at its size: every page it needs more fails.
    final pages = await db.customSelect('PRAGMA page_count').getSingle();
    await db.customStatement(
      'PRAGMA max_page_count = ${pages.data.values.single}',
    );
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  testWidgets('a full disk during an import reads as the storage message, '
      'in Japanese', (tester) async {
    final ja = lookupAppLocalizations(const Locale('ja'));
    final zip = File(p.join(root.path, 'big.zip'))
      ..writeAsBytesSync(_zip(3000));

    final error = await tester.runAsync(() async {
      try {
        await DictionaryImporter(
          DictionaryRepository(db),
        ).importFromFile(zip.path);
      } catch (e) {
        return e;
      }
      return null;
    });

    expect(isStorageFull(error), isTrue, reason: '$error');
    expect(dictionaryDownloadError(ja, error), ja.localOcrStorageFull);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Scaffold(
          body: DownloadOutcomeText((
            action: TileAction.download,
            error: error,
          ), kind: DownloadKind.catalogDictionary),
        ),
        locale: const Locale('ja'),
      ),
    );
    expect(find.text(ja.localOcrStorageFull), findsOneWidget);
    expect(find.textContaining(RegExp('Exception|SQLITE|full')), findsNothing);
  });
}
