import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_viewer.dart';

void main() {
  group('buildEpubGestureRecognizers', () {
    late Set<Factory<OneSequenceGestureRecognizer>> recognizers;

    setUp(() {
      recognizers = buildEpubGestureRecognizers();
    });

    test('returns four recognizer factories', () {
      expect(recognizers.length, 4);
    });

    test('includes TapGestureRecognizer for single taps', () {
      final hasTap = recognizers.any((f) => f.type == TapGestureRecognizer);
      expect(hasTap, isTrue, reason: 'Tap recognizer needed for word lookups');
    });

    test('includes HorizontalDragGestureRecognizer for swipe navigation', () {
      final hasHDrag = recognizers.any(
        (f) => f.type == HorizontalDragGestureRecognizer,
      );
      expect(
        hasHDrag,
        isTrue,
        reason: 'Horizontal drag needed for swipe page turns',
      );
    });

    test('includes VerticalDragGestureRecognizer for vertical swipes', () {
      final hasVDrag = recognizers.any(
        (f) => f.type == VerticalDragGestureRecognizer,
      );
      expect(
        hasVDrag,
        isTrue,
        reason: 'Vertical drag needed for show/hide controls gesture',
      );
    });

    test('includes LongPressGestureRecognizer for text selection', () {
      final hasLongPress = recognizers.any(
        (f) => f.type == LongPressGestureRecognizer,
      );
      expect(
        hasLongPress,
        isTrue,
        reason: 'Long press needed for text selection in WKWebView',
      );
    });

    test('LongPressGestureRecognizer has 30ms deadline', () {
      final longPressFactory = recognizers.firstWhere(
        (f) => f.type == LongPressGestureRecognizer,
      );
      final recognizer =
          longPressFactory.constructor() as LongPressGestureRecognizer;
      expect(
        recognizer.deadline,
        const Duration(milliseconds: 30),
        reason: '30ms ensures fast taps still reach the web view',
      );
    });

    test('does not include EagerGestureRecognizer (breaks iOS UiKitView)', () {
      final hasEager = recognizers.any((f) => f.type == EagerGestureRecognizer);
      expect(
        hasEager,
        isFalse,
        reason:
            'EagerGestureRecognizer conflicts with iOS touch forwarding '
            'and prevents WKWebView from receiving touch events',
      );
    });

    test('each factory produces a distinct recognizer type', () {
      final types = recognizers.map((f) => f.type).toSet();
      expect(
        types.length,
        recognizers.length,
        reason: 'No duplicate recognizer types',
      );
    });

    test('all recognizers are OneSequenceGestureRecognizer subtypes', () {
      for (final factory in recognizers) {
        final recognizer = factory.constructor();
        expect(
          recognizer,
          isA<OneSequenceGestureRecognizer>(),
          reason:
              '${recognizer.runtimeType} must be a OneSequenceGestureRecognizer '
              'to work with UiKitView gestureRecognizers',
        );
      }
    });
  });
}
