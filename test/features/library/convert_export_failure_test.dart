import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/data/services/epub_manga_converter.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/widgets/epub_manga_convert_action.dart';
import 'package:mekuru/features/library/presentation/widgets/furigana_export_action.dart';
import 'package:mekuru/features/library/presentation/widgets/manga_cbz_export_action.dart';
import 'package:mekuru/l10n/generated/app_localizations_ja.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/fake_path_provider.dart';
import '../../shared/test_database.dart';
import '../../test_app.dart';

/// What a full disk says, with the book's name in it.
final _diskFull = FileSystemException(
  'Cannot write file',
  '/books/秘密の本.cbz',
  const OSError('No space left on device', 28),
);

/// Each build step ends in [failure], or works when it is null.
class _Repository extends BookRepository {
  _Repository(super.db, {this.failure});

  final Object? failure;

  @override
  Future<Book> convertEpubToManga(Book book) async {
    if (failure case final failure?) throw failure;
    return book.copyWith(bookType: 'manga');
  }

  @override
  Future<(String, int)> exportMangaCbz(
    Book book, {
    required String fileName,
    required bool rtl,
  }) async {
    if (failure case final failure?) throw failure;
    return ('/missing/$fileName', 3);
  }
}

/// SharePlus keeps the first platform it sees, so one instance serves every
/// test.
class _Share extends SharePlatform {
  Object? failure;

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (failure case final failure?) throw failure;
    return const ShareResult('', ShareResultStatus.success);
  }
}

Book _book(String type) => Book(
  id: 1,
  isFavorite: false,
  title: '秘密の本',
  filePath: '/books/missing/content',
  bookType: type,
  totalPages: 3,
  readProgress: 0,
  dateAdded: DateTime(2026),
);

void main() {
  final ja = AppLocalizationsJa();
  final share = _Share();
  late AppDatabase db;

  setUpAll(() => SharePlatform.instance = share);
  late Directory temp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    temp = Directory.systemTemp.createTempSync('convert_export_');
    PathProviderPlatform.instance = FakePathProviderPlatform(temp.path);
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  /// A page whose button runs [action] on [book], in Japanese.
  Future<void> run(
    WidgetTester tester,
    BookRepository repo,
    Future<void> Function(BuildContext, WidgetRef) action,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bookRepositoryProvider.overrideWithValue(repo)],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => action(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// Lets real file work finish until a snack bar shows.
  Future<void> waitForSnackBar(WidgetTester tester) async {
    for (var i = 0; i < 100 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  void expectNoRawError() {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('秘密'), findsNothing);
    expect(find.textContaining('No space'), findsNothing);
  }

  group('convert to manga', () {
    Future<void> convert(WidgetTester tester, {Object? failure}) async {
      await run(
        tester,
        _Repository(db, failure: failure),
        (context, ref) => runEpubMangaConversion(context, ref, _book('epub')),
      );
      await tester.tap(find.text(ja.libraryConvertToMangaAction));
      await waitForSnackBar(tester);
    }

    testWidgets('that fails says so in Japanese, without the error', (
      tester,
    ) async {
      await convert(tester, failure: _diskFull);

      expectNoRawError();
      expect(find.text(ja.libraryConvertToMangaFailed), findsOneWidget);
    });

    testWidgets('of a book that is not a manga still says so', (tester) async {
      await convert(tester, failure: const EpubNotMangaException('not manga'));

      expect(find.text(ja.libraryConvertToMangaNotEligible), findsOneWidget);
    });

    testWidgets('that works says it converted', (tester) async {
      await convert(tester);

      expect(find.text(ja.libraryConvertToMangaDone), findsOneWidget);
    });
  });

  group('CBZ export', () {
    Future<void> export(
      WidgetTester tester, {
      Object? buildFailure,
      Object? shareFailure,
    }) async {
      share.failure = shareFailure;
      await run(
        tester,
        _Repository(db, failure: buildFailure),
        (context, ref) => runMangaCbzExport(context, ref, _book('manga')),
      );
      await waitForSnackBar(tester);
    }

    testWidgets('whose build fails says so in Japanese', (tester) async {
      await export(tester, buildFailure: _diskFull);

      expectNoRawError();
      expect(find.text(ja.commonExportFailed(format: 'CBZ')), findsOneWidget);
    });

    testWidgets('whose share sheet fails says so in Japanese', (tester) async {
      await export(tester, shareFailure: _diskFull);

      expectNoRawError();
      expect(find.text(ja.commonExportFailed(format: 'CBZ')), findsOneWidget);
    });

    testWidgets('that is shared says it exported', (tester) async {
      await export(tester);

      expect(find.text(ja.libraryExportCbzDone), findsOneWidget);
    });
  });

  testWidgets('a furigana EPUB whose build fails says so in Japanese', (
    tester,
  ) async {
    // The book's EPUB is gone, so the build cannot read it.
    await run(
      tester,
      _Repository(db),
      (context, ref) => runFuriganaExport(context, ref, _book('epub')),
    );
    await tester.tap(find.text(ja.libraryExportFuriganaAction));
    await waitForSnackBar(tester);

    expectNoRawError();
    expect(find.text(ja.commonExportFailed(format: 'EPUB')), findsOneWidget);
  });
}
