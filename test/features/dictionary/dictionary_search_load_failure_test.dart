import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/test_database.dart';
import '../../test_app.dart';

void main() {
  final ja = lookupAppLocalizations(const Locale('ja'));
  late AppDatabase db;
  final logs = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = createTestDatabase();
    logs.clear();
    usageLogSinkOverride = (message, _, {required isWarning}) =>
        logs.add(message);
    usageAnalyticsSinkOverride = (_, _) {};
  });

  tearDown(() async {
    usageLogSinkOverride = null;
    usageAnalyticsSinkOverride = null;
    await db.close();
  });

  testWidgets('dictionaries that cannot be read say so in Japanese', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionariesProvider.overrideWith(
            (ref) =>
                Stream.error(Exception('database disk image is malformed')),
          ),
        ],
        child: buildLocalizedTestApp(
          locale: const Locale('ja'),
          home: const DictionarySearchScreen(),
        ),
      ),
    );
    // Riverpod retries a failed provider, showing it as loading, for about a
    // minute before the error stands.
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();

    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('malformed'), findsNothing);
    expect(find.text(ja.commonLoadFailed), findsOneWidget);
    expect(logs, contains('dictionary.list_load_failed'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
