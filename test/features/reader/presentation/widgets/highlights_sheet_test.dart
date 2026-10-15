import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/reader/data/repositories/highlight_repository.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';
import 'package:mekuru/l10n/generated/app_localizations_en.dart';
import 'package:mekuru/l10n/generated/app_localizations_es.dart';

import '../../../../shared/test_database.dart';
import '../../../../test_app.dart';

/// Records the writes the sheets make instead of running them.
class _RecordingRepository extends HighlightRepository {
  _RecordingRepository(super.db);

  final notes = <int, String>{};
  final deleted = <int>[];

  @override
  Future<void> updateHighlightNote(int id, String note) async =>
      notes[id] = note;

  @override
  Future<void> deleteHighlight(int id) async => deleted.add(id);
}

Highlight _highlight(
  int id,
  String cfiRange,
  String text, {
  String note = '',
}) => Highlight(
  id: id,
  bookId: 1,
  cfiRange: cfiRange,
  selectedText: text,
  color: 'yellow',
  userNote: note,
  dateAdded: DateTime(2026, 10, 15),
);

void main() {
  final en = AppLocalizationsEn();
  late AppDatabase db;
  late _RecordingRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = _RecordingRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Pumps a page whose "open" button runs [open], with the book's
  /// highlights served as [highlights].
  Future<void> pumpOpener(
    WidgetTester tester,
    List<Highlight> highlights,
    void Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          highlightRepositoryProvider.overrideWithValue(repo),
          highlightsForBookProvider(
            1,
          ).overrideWith((ref) => Stream.value(highlights)),
        ],
        child: buildLocalizedTestApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('HighlightDetailsSheet', () {
    final highlights = [
      _highlight(1, 'epubcfi(/6/4!/4/2,/1:0,/1:3)', '吾輩は'),
      _highlight(2, 'epubcfi(/6/4!/4/4,/1:0,/1:5)', '猫である', note: '名前はまだ無い'),
    ];
    String? removedCfi;

    Future<void> openFor(WidgetTester tester, String cfiRange) {
      removedCfi = null;
      return pumpOpener(
        tester,
        highlights,
        (context) => showModalBottomSheet<void>(
          context: context,
          builder: (_) => HighlightDetailsSheet(
            bookId: 1,
            cfiRange: cfiRange,
            onRemoveHighlight: (cfi) => removedCfi = cfi,
          ),
        ),
      );
    }

    testWidgets('shows the pressed highlight and its note', (tester) async {
      await openFor(tester, highlights[1].cfiRange);

      expect(find.text('猫である'), findsOneWidget);
      expect(find.text('名前はまだ無い'), findsOneWidget);
      expect(find.text('吾輩は'), findsNothing);
      expect(find.text(en.readerEditNoteTitle), findsOneWidget);
    });

    testWidgets('offers to add a note when there is none', (tester) async {
      await openFor(tester, highlights[0].cfiRange);

      expect(find.text('吾輩は'), findsOneWidget);
      expect(find.text(en.readerAddNote), findsOneWidget);
    });

    testWidgets('delete removes the row and the drawn highlight', (
      tester,
    ) async {
      await openFor(tester, highlights[1].cfiRange);

      await tester.tap(find.text(en.commonDelete));
      await tester.pumpAndSettle();

      expect(repo.deleted, [2]);
      expect(removedCfi, highlights[1].cfiRange);
      expect(find.byType(HighlightDetailsSheet), findsNothing);
    });

    testWidgets('edit note opens the note editor on the current note', (
      tester,
    ) async {
      await openFor(tester, highlights[1].cfiRange);

      await tester.tap(find.text(en.readerEditNoteTitle));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '名前はまだ無い',
      );

      await tester.enterText(find.byType(TextField), '猫の話');
      await tester.tap(find.text(en.commonSave));
      await tester.pumpAndSettle();

      expect(repo.notes, {2: '猫の話'});
    });
  });

  group('showHighlightNoteEditor', () {
    void openEditor(BuildContext context) =>
        showHighlightNoteEditor(context, highlightId: 7);

    testWidgets('save stores the note', (tester) async {
      await pumpOpener(tester, const [], openEditor);

      await tester.enterText(find.byType(TextField), 'メモ');
      await tester.tap(find.text(en.commonSave));
      await tester.pumpAndSettle();

      expect(repo.notes, {7: 'メモ'});
    });

    testWidgets('cancel leaves the highlight without a note', (tester) async {
      await pumpOpener(tester, const [], openEditor);

      await tester.enterText(find.byType(TextField), 'メモ');
      await tester.tap(find.text(en.commonCancel));
      await tester.pumpAndSettle();

      expect(repo.notes, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('the sheet and its empty state speak the app language', (
    tester,
  ) async {
    final es = AppLocalizationsEs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          highlightsForBookProvider(
            1,
          ).overrideWith((ref) => Stream.value(const [])),
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('es'),
          home: const Scaffold(body: HighlightsSheet(bookId: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(es.readerHighlightsTooltip), findsOneWidget);
    expect(find.text(es.readerNoHighlightsYet), findsOneWidget);
    expect(find.textContaining('Highlights'), findsNothing);
  });
}
