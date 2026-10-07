import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/data/repositories/book_repository.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/widgets/manga_cbz_export_action.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../../shared/test_database.dart';
import '../../test_app.dart';

class _CbzRepository extends BookRepository {
  _CbzRepository(super.db);

  @override
  Future<(String, int)> exportMangaCbz(
    Book book, {
    required String fileName,
  }) async => ('/missing/$fileName', 3);
}

class _RecordingShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('', ShareResultStatus.dismissed);
  }
}

void main() {
  testWidgets('the share sheet points at the tapped tile, cut to the screen', (
    tester,
  ) async {
    // iPad refuses to show the sheet without a rect on screen to point at.
    final share = _RecordingShare();
    SharePlatform.instance = share;
    final db = createTestDatabase();
    addTearDown(db.close);
    final book = Book(
      id: 1,
      title: 'Manga',
      filePath: '/unused',
      bookType: 'manga',
      totalPages: 3,
      readProgress: 0,
      dateAdded: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(_CbzRepository(db)),
        ],
        child: buildLocalizedTestApp(
          home: Stack(
            children: [
              // Half scrolled off the bottom of the 800x600 screen.
              Positioned(
                left: 100,
                top: 500,
                width: 200,
                height: 200,
                child: Consumer(
                  builder: (context, ref, _) => GestureDetector(
                    onTap: () => runMangaCbzExport(context, ref, book),
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 550));
    await tester.pumpAndSettle();

    expect(
      share.shared.single.sharePositionOrigin,
      const Rect.fromLTWH(100, 500, 200, 100),
    );
  });
}
