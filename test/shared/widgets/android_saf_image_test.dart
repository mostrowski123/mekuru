import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/widgets/android_saf_image.dart';

import '../saf_image_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> readPaths;

  setUp(() => readPaths = stubSafImageReads());
  tearDown(clearSafImageStub);

  Widget buildSafImage() => const MaterialApp(
    home: AndroidSafImage(
      treeUri: 'content://tree/test',
      relativePath: 'imgs/p1.png',
      cacheWidth: 32,
    ),
  );

  testWidgets('re-showing the same SAF image reuses the decoded image '
      'instead of re-reading bytes', (tester) async {
    await tester.pumpWidget(buildSafImage());
    await pumpUntilPainted(tester);
    expect(readPaths, hasLength(1));

    // Navigate away — the widget (and any per-widget state) is disposed.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    // Show the same image again: it must come from the image cache, with no
    // second platform-channel read and pixels on the very first frame —
    // this is what prevents a black flash on instant page jumps.
    await tester.pumpWidget(buildSafImage());
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(
      raw.image,
      isNotNull,
      reason: 'cached SAF image must paint on the first frame',
    );
    expect(
      readPaths,
      hasLength(1),
      reason: 'bytes must not be re-read from SAF',
    );
  });

  testWidgets('a precached page paints on the first frame with no extra read', (
    tester,
  ) async {
    // Same provider + cacheWidth shape as _precacheAdjacentPages uses.
    const provider = AndroidSafImageProvider(
      treeUri: 'content://tree/test',
      relativePath: 'imgs/p1.png',
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(const ResizeImage(provider, width: 32), ctx),
    );
    expect(readPaths, hasLength(1));

    await tester.pumpWidget(buildSafImage());
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(
      raw.image,
      isNotNull,
      reason: 'precached SAF image must paint on the very first frame',
    );
    expect(readPaths, hasLength(1));
  });

  test('providers with the same source are equal cache keys', () {
    const a = AndroidSafImageProvider(treeUri: 't', relativePath: 'x/p.png');
    const b = AndroidSafImageProvider(treeUri: 't', relativePath: 'x/p.png');
    const other = AndroidSafImageProvider(
      treeUri: 't',
      relativePath: 'x/q.png',
    );
    const byUri = AndroidSafImageProvider(uri: 'content://doc/p.png');

    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(other)));
    expect(a, isNot(equals(byUri)));
  });
}
