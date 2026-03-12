import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

void main() {
  testWidgets('empty library shows quick-start actions', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) => Stream.value(<Book>[])),
        ],
        child: buildLocalizedTestApp(home: const LibraryScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Import EPUB'), findsOneWidget);
    expect(find.text('Import Manga'), findsOneWidget);
    expect(find.text('Get Dictionaries'), findsOneWidget);
    expect(find.text('Restore Backup'), findsOneWidget);
  });

  testWidgets('import manga opens the type picker with Mokuro guidance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) => Stream.value(<Book>[])),
        ],
        child: buildLocalizedTestApp(home: const LibraryScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Import Manga'));
    await tester.pumpAndSettle();

    expect(find.text('Mokuro folder'), findsOneWidget);
    expect(find.text('CBZ archive'), findsOneWidget);
    expect(
      find.text(
        'Select the folder that contains a .mokuro or .html file alongside the images folder.',
      ),
      findsOneWidget,
    );
    expect(find.text('What is Mokuro?'), findsOneWidget);
  });

  testWidgets('completed OCR uses Delete OCR as the primary action title', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) => Text(
            mangaOcrPrimaryActionTitle(
              l10n: context.l10n,
              isRunning: false,
              isMokuroComplete: false,
              hasCompleteOcr: true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Delete OCR'), findsOneWidget);
    expect(find.text('Run OCR'), findsNothing);
  });
}
