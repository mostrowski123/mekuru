import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/review/review_prompt_service.dart';
import 'package:mekuru/core/review/review_prompt_storage.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';

final reviewPromptServiceProvider = Provider<ReviewPromptService>((ref) {
  return ReviewPromptService(
    storage: SharedPreferencesReviewPromptStorage(),
    // Resolved lazily inside the callback so building the service never
    // touches the database provider.
    countSavedWords: () => ref.read(vocabularyRepositoryProvider).countWords(),
  );
});

/// Treats the lifetime of a reader screen as one reading session and lets the
/// review service consider a prompt when the session ends — whichever route
/// opened the reader.
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
  }

  @override
  void dispose() {
    unawaited(
      _reviewPromptService.maybeRequestReview(
        sessionStartedAt: _reviewSessionStartedAt,
      ),
    );
    super.dispose();
  }
}
