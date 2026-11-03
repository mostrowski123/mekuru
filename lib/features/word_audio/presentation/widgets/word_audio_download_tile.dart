import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_ocr_ios_download_tile.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/presentation/providers/word_audio_providers.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Downloads screen row for the word list behind the lookup's speaker button.
class WordAudioDownloadTile extends ConsumerWidget {
  const WordAudioDownloadTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(wordAudioProvider);
    final l10n = context.l10n;
    return ModelDownloadTile(
      icon: Icons.volume_up_outlined,
      title: l10n.wordAudioTitle,
      description: l10n.wordAudioDescription,
      files: const [wordAudioIndexFile],
      installed: () => audio.installed,
      download: audio.download,
      remove: audio.remove,
      readyText: l10n.wordAudioReady,
      mobileDataBody: (size) => l10n.wordAudioMobileBody(size: size),
    );
  }
}
