import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load returns defaults on a fresh install', () async {
    final state = await SharedPreferencesReviewPromptStorage().load();

    expect(state.firstSeenAt, isNull);
    expect(state.qualifyingSessions, 0);
    expect(state.requestCount, 0);
    expect(state.lastRequestAt, isNull);
  });

  test('round-trips first-seen, session, and request state', () async {
    final storage = SharedPreferencesReviewPromptStorage();
    final firstSeen = DateTime(2026, 7, 1, 9, 30);
    final requestedAt = DateTime(2026, 7, 12, 20);

    await storage.saveFirstSeenAt(firstSeen);
    await storage.saveQualifyingSessions(3);
    await storage.recordRequest(requestedAt, 2);
    final state = await storage.load();

    expect(state.firstSeenAt, firstSeen);
    expect(state.qualifyingSessions, 3);
    expect(state.requestCount, 2);
    expect(state.lastRequestAt, requestedAt);
  });
}
