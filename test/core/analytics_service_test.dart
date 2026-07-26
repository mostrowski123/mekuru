import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/analytics_service.dart';

void main() {
  // Firebase is never initialized in unit tests, so `_instance` is null either
  // way and `logEvent` is unobservable here. What is worth pinning down is
  // that suppression silences the automatic screen-tracking observer as well
  // as explicit events — that observer was the leak a per-call-site gate
  // could not close — and that neither path throws without Firebase.
  test('suppress() withholds the screen-tracking observer', () {
    final service = AnalyticsService.instance;

    service.suppress();

    expect(service.navigatorObserver, isNull);
    expect(() => service.logEvent('book_imported', {'format': 'cbz'}),
        returnsNormally);
  });
}
