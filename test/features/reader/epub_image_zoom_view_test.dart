import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/presentation/widgets/epub_image_zoom_view.dart';

import '../../test_app.dart';

void main() {
  testWidgets('shows the halves side by side, left first, and closes on tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => const EpubImageZoomView(
                  images: [
                    (path: '/book/left.png', width: 30, height: 40),
                    (path: '/book/right.png', width: 60, height: 80),
                  ],
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.map((i) => (i.image as FileImage).file.path), [
      '/book/left.png',
      '/book/right.png',
    ]);
    final left = tester.getRect(find.byType(Image).first);
    final right = tester.getRect(find.byType(Image).last);
    expect(left.right, lessThanOrEqualTo(right.left + 0.5));
    // Same height on screen, whatever their pixel sizes.
    expect(left.height, closeTo(right.height, 0.5));
    expect(
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale,
      5,
    );
    expect(find.bySemanticsLabel('Close'), findsOneWidget);

    await tester.tap(find.byType(EpubImageZoomView));
    await tester.pumpAndSettle();
    expect(find.byType(EpubImageZoomView), findsNothing);
    semantics.dispose();
  });
}
