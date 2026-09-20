import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';

import '../../../../test_app.dart';

void main() {
  testWidgets('offers the optional manga-ocr pack with its size', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Scaffold(body: MangaOcrIosDownloadTile()),
      ),
    );
    // The installed check is real file I/O, which the fake clock never runs.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(find.text('Download'), findsOneWidget);
    // Encoder, decoder and vocabulary, without Android's detector.
    expect(find.textContaining('201.5 MB'), findsOneWidget);
    expect(find.textContaining('Optional'), findsOneWidget);
  });
}
