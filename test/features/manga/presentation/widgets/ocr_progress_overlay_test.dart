import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_background_worker.dart';
import 'package:mekuru/features/manga/presentation/providers/ocr_progress_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/ocr_progress_overlay.dart';

void main() {
  /// Builds a test widget with the ocrProgressProvider overridden to emit
  /// a single value (no polling), so the test framework isn't stuck waiting.
  Widget buildTestWidget({
    required int bookId,
    OcrProgress? progress,
  }) {
    return ProviderScope(
      overrides: [
        ocrProgressProvider(bookId)
            .overrideWith((ref) => Stream.value(progress)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: Stack(
              children: [
                Container(color: Colors.grey),
                OcrProgressOverlay(bookId: bookId),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('OcrProgressOverlay', () {
    testWidgets('shows nothing when no progress stored', (tester) async {
      await tester.pumpWidget(buildTestWidget(bookId: 999));
      await tester.pumpAndSettle();

      expect(find.text('OCR Complete'), findsNothing);
      expect(find.text('OCR Paused'), findsNothing);
      expect(find.text('OCR Failed'), findsNothing);
    });

    testWidgets('shows running overlay with page count', (tester) async {
      const progress = OcrProgress(
        completed: 42,
        total: 200,
        status: OcrStatus.running,
        avgSecondsPerPage: 1.5,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      // Use pump() — CircularProgressIndicator animates forever,
      // so pumpAndSettle would time out.
      await tester.pump();

      expect(find.text('42/200 pages'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows ETA text when avgSecondsPerPage available',
        (tester) async {
      const progress = OcrProgress(
        completed: 100,
        total: 200,
        status: OcrStatus.running,
        avgSecondsPerPage: 1.0,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      await tester.pump();

      // 100 remaining * 1.0 sec = 100 seconds = ~2 min
      expect(find.textContaining('min remaining'), findsOneWidget);
    });

    testWidgets('shows completed overlay', (tester) async {
      const progress = OcrProgress(
        completed: 200,
        total: 200,
        status: OcrStatus.completed,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      await tester.pumpAndSettle();

      expect(find.text('OCR Complete'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows failed overlay', (tester) async {
      const progress = OcrProgress(
        completed: 5,
        total: 200,
        status: OcrStatus.failed,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      await tester.pumpAndSettle();

      expect(find.text('OCR Failed'), findsOneWidget);
    });

    testWidgets('shows paused overlay with progress', (tester) async {
      const progress = OcrProgress(
        completed: 50,
        total: 200,
        status: OcrStatus.cancelled,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      await tester.pumpAndSettle();

      expect(find.text('50/200 pages'), findsOneWidget);
      expect(find.text('OCR Paused'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    });

    testWidgets('shows nothing for idle status', (tester) async {
      const progress = OcrProgress(
        completed: 0,
        total: 0,
        status: OcrStatus.idle,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      await tester.pumpAndSettle();

      expect(find.text('OCR Complete'), findsNothing);
      expect(find.text('OCR Paused'), findsNothing);
      expect(find.text('OCR Failed'), findsNothing);
    });

    testWidgets('ETA shows seconds for short estimates', (tester) async {
      const progress = OcrProgress(
        completed: 195,
        total: 200,
        status: OcrStatus.running,
        avgSecondsPerPage: 2.0,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      await tester.pump();

      // 5 remaining * 2.0 sec = 10 seconds
      expect(find.textContaining('~10s remaining'), findsOneWidget);
    });

    testWidgets('ETA shows hours for long estimates', (tester) async {
      const progress = OcrProgress(
        completed: 10,
        total: 1000,
        status: OcrStatus.running,
        avgSecondsPerPage: 5.0,
      );

      await tester.pumpWidget(buildTestWidget(bookId: 1, progress: progress));
      await tester.pump();

      // 990 remaining * 5.0 sec = 4950 seconds = 1h 22m
      expect(find.textContaining('h'), findsOneWidget);
      expect(find.textContaining('m remaining'), findsOneWidget);
    });
  });
}
