import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/review/review_prompt_service.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';

/// Reader screens currently on screen. While this is non-zero the review
/// dialog must not appear — the user is reading.
int _activeReadingSessions = 0;

final reviewPromptServiceProvider = Provider<ReviewPromptService>((ref) {
  return ReviewPromptService(
    storage: SharedPreferencesReviewPromptStorage(),
    isSafeToPrompt: () => _activeReadingSessions == 0,
  );
});

/// Treats the lifetime of a reader screen as one reading session and lets the
/// review service consider a prompt when the session ends — whichever route
/// opened the reader. The prompt can therefore never appear at launch or
/// while a reader is open, only back at the screen the reader was opened
/// from.
///
/// The service is captured in [initState] because `ref` must not be used
/// while the widget is unmounting.
mixin ReadingSessionReviewPrompt<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  late final ReviewPromptService _reviewPromptService;
  late final DateTime _reviewSessionStartedAt;

  @override
  void initState() {
    super.initState();
    _reviewPromptService = ref.read(reviewPromptServiceProvider);
    _reviewSessionStartedAt = DateTime.now();
    _activeReadingSessions++;
  }

  @override
  void dispose() {
    _activeReadingSessions--;
    unawaited(
      _reviewPromptService.maybeRequestReview(
        sessionStartedAt: _reviewSessionStartedAt,
      ),
    );
    super.dispose();
  }
}
