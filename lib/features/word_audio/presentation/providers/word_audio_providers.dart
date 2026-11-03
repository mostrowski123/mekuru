import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';

final wordAudioProvider = Provider<WordAudio>((ref) {
  final audio = WordAudio();
  ref.onDispose(audio.dispose);
  return audio;
});
