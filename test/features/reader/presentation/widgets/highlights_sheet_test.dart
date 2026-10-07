import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/highlights_sheet.dart';
import 'package:mekuru/l10n/generated/app_localizations_es.dart';

import '../../../../test_app.dart';

void main() {
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
