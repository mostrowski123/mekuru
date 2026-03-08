import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/library/presentation/providers/library_providers.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('empty library shows quick-start actions', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) => Stream.value(<Book>[])),
        ],
        child: const MaterialApp(home: LibraryScreen()),
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
        child: const MaterialApp(home: LibraryScreen()),
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
}
