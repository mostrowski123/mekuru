import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mekuru/features/library/presentation/screens/library_screen.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:mekuru/shared/widgets/glass_tab_bar.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Widget screen({required bool strip}) => MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(466, 678),
        padding: EdgeInsets.only(right: 84, bottom: 20),
      ),
      child: GlassVerticalBar(
        data: strip
            ? const GlassVerticalBarData(
                edge: GlassVerticalBarEdge.trailing,
                width: 84,
                top: 170,
              )
            : null,
        child: const VerticalBarInset(child: SizedBox.expand(key: Key('c'))),
      ),
    ),
  );

  group('VerticalBarInset', () {
    testWidgets('keeps a screen out of the strip', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(466, 678);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen(strip: true));

      expect(tester.getSize(find.byKey(const Key('c'))).width, 466 - 84);
      final padding = MediaQuery.paddingOf(
        tester.element(find.byKey(const Key('c'))),
      );
      // The screen's own SafeAreas must not inset it a second time.
      expect(padding.right, 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('changes nothing without a strip', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(466, 678);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen(strip: false));

      expect(tester.getSize(find.byKey(const Key('c'))).width, 466);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('adds nothing on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await tester.pumpWidget(screen(strip: true));

      expect(
        find.descendant(
          of: find.byType(VerticalBarInset),
          matching: find.byType(SafeArea),
        ),
        findsNothing,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('readers draw under the strip, other screens stay clear of it', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    Widget built(String name) =>
        (namedRoute<void>(name, (_) => const SizedBox())
                as MaterialPageRoute<void>)
            .builder(context);

    expect(built('settings'), isA<VerticalBarInset>());
    for (final name in ['reader', 'manga_reader', 'epub_image_zoom']) {
      expect(built(name), isNot(isA<VerticalBarInset>()), reason: name);
    }
  });

  group('libraryGridColumns', () {
    test('iOS adds columns as the window widens, never below three', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(libraryGridColumns(375), 3); // iPhone
      expect(libraryGridColumns(466), 3); // iPhone Duo, closed
      expect(libraryGridColumns(669), 3); // iPhone Duo, open and upright
      expect(libraryGridColumns(951), 5); // iPhone Duo, open
      expect(libraryGridColumns(1024), 5); // iPad Pro 13
    });

    test('Android keeps three at any width', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(libraryGridColumns(1600), 3);
    });

    test('a chosen count wins on both platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(libraryGridColumns(375, 4), 4);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(libraryGridColumns(1024, 2), 2);
      expect(libraryGridColumns(1024, 0), 5); // Auto
    });
  });
}
