import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/analytics_service.dart';

void main() {
  // Firebase is never initialized in unit tests, as in an isolate that never
  // initializes it (the WorkManager OCR worker). Every path must stay silent
  // there and never throw, before and after the startup decision.
  test('without Firebase the service stays silent and never throws', () async {
    final service = AnalyticsService.instance;

    for (final configure in [
      () {},
      () => service.configure(isSynthetic: true, installSource: 'sideload'),
    ]) {
      configure();
      expect(service.navigatorObserver, isNull);
      expect(
        () => service.logEvent('book_imported', {'format': 'cbz'}),
        returnsNormally,
      );
      expect(() => service.setUserProperty('reader', 'manga'), returnsNormally);
      await expectLater(service.applyToFirebase(), completes);
    }
  });
}
