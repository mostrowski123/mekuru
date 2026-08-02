import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/reading_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../test_app.dart';

class _FakeProUnlocked extends ProUnlockedNotifier {
  _FakeProUnlocked(this._unlocked);
  final bool _unlocked;

  @override
  Future<bool> build() async => _unlocked;
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  bool proUnlocked = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      proUnlockedProvider.overrideWith(() => _FakeProUnlocked(proUnlocked)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: buildLocalizedTestApp(home: const ReadingSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the three section headers', (tester) async {
    await _pumpScreen(tester);
    expect(find.text('All books'), findsOneWidget);
    await _scrollTo(tester, find.text('EPUB'));
    expect(find.text('EPUB'), findsOneWidget);
    await _scrollTo(tester, find.text('Manga'));
    expect(find.text('Manga'), findsOneWidget);
  });

  testWidgets('font size slider writes through the shared provider', (
    tester,
  ) async {
    final container = await _pumpScreen(tester);
    final before = container.read(readerSettingsProvider).fontSize;

    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(container.read(readerSettingsProvider).fontSize, isNot(before));
  });

  testWidgets('Pro manga tiles are hidden without Pro', (tester) async {
    await _pumpScreen(tester);
    await _scrollTo(tester, find.text('Manga'));
    // Scroll to the very bottom to be sure the Pro tiles would have built.
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -1200),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('White Threshold'), findsNothing);
    expect(find.text('Custom OCR Server'), findsNothing);
  });
}
