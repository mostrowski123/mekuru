import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart'
    show modelFilesSize;
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/presentation/providers/word_audio_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// The speaker in a dictionary lookup. It offers the word list until that is
/// installed, then shows only for words that have a clip.
class WordAudioButton extends ConsumerStatefulWidget {
  const WordAudioButton({
    super.key,
    required this.expression,
    required this.reading,
    required this.glossaries,
  });

  final String expression;
  final String reading;
  final String glossaries;

  @override
  ConsumerState<WordAudioButton> createState() => _WordAudioButtonState();
}

class _WordAudioButtonState extends ConsumerState<WordAudioButton> {
  bool _shown = false;
  bool _busy = false;
  String? _clip;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant WordAudioButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expression != widget.expression ||
        oldWidget.reading != widget.reading) {
      _check();
    }
  }

  Future<void> _check() async {
    final requestId = ++_requestId;
    final audio = ref.read(wordAudioProvider);
    var shown = false;
    String? clip;
    try {
      clip = await audio.clipFor(
        widget.expression,
        widget.reading,
        glossaries: widget.glossaries,
      );
      shown = clip != null || !await audio.installed;
    } catch (e) {
      logFailure('word_audio.lookup_failed', e);
    }
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _shown = shown;
      _clip = clip;
    });
  }

  Future<void> _play() async {
    final audio = ref.read(wordAudioProvider);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (_clip == null) {
        if (!await audio.installed) {
          final size = modelFilesSize([wordAudioIndexFile]);
          if (!mounted ||
              !await okToDownload(
                context,
                size: size,
                body: l10n.wordAudioMobileBody(size: size),
              )) {
            return;
          }
          await audio.download();
        }
        // A word the list turns out not to have loses its speaker here.
        await _check();
      }
      if (_clip case final clip?) await audio.play(clip);
    } catch (e) {
      logFailure('word_audio.failed', e);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is WordAudioPlaybackException
                ? l10n.wordAudioFailed
                : dictionaryDownloadError(l10n, e)!,
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    return IconButton(
      onPressed: _busy ? null : _play,
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.volume_up_outlined),
      tooltip: context.l10n.wordAudioPlayTooltip,
      iconSize: 20,
    );
  }
}
