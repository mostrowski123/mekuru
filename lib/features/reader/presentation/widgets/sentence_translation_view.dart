import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/data/services/sentence_translation.dart';
import 'package:mekuru/features/reader/presentation/providers/gemma_download_provider.dart';
import 'package:mekuru/features/reader/presentation/widgets/translation_memory_warning.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/main.dart' show scaffoldMessengerKey;
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// The lookup sheet's Sentence tab: the sentence around the tapped word and
/// its on-device translation into the app's language.
class SentenceTranslationView extends ConsumerStatefulWidget {
  const SentenceTranslationView({
    super.key,
    required this.sentence,
    required this.word,
    required this.fontSize,
    required this.hidden,
    required this.source,
    required this.highQuality,
    this.onSentenceEdited,
    this.onEditingStarted,
    this.onEditingEnded,
    this.scrollController,
    this.shrinkWrap = false,
  });

  final String sentence;

  /// The tapped word, highlighted in [sentence].
  final String word;

  final double fontSize;

  /// Keep the translation behind a "tap to show" placeholder.
  final bool hidden;

  /// Where the sheet was opened from, for telemetry (`'epub'`, `'manga'`).
  final String source;

  /// Translate with Gemma when it is ready (Android's High quality).
  final bool highQuality;

  /// Set when the user may correct the sentence (OCR mistakes) before
  /// translating.
  final ValueChanged<String>? onSentenceEdited;
  final VoidCallback? onEditingStarted;
  final VoidCallback? onEditingEnded;

  final ScrollController? scrollController;
  final bool shrinkWrap;

  @override
  ConsumerState<SentenceTranslationView> createState() =>
      _SentenceTranslationViewState();
}

class _SentenceTranslationViewState
    extends ConsumerState<SentenceTranslationView> {
  /// The engine's status, with the translation once it is installed.
  Future<(TranslationStatus, SentenceTranslation?)>? _translation;

  /// Counts loads so only the one on screen logs it.
  var _loads = 0;

  /// The last load found High quality unable to answer and Standard not
  /// downloaded ([StandardTranslationNeeded]).
  bool _standardNeeded = false;
  String? _target;
  bool _downloading = false;
  late bool _revealed = !widget.hidden;
  bool _editing = false;
  final _editController = TextEditingController();

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final target = translationTargetFor(Localizations.localeOf(context));
    if (target != _target) {
      _target = target;
      _translation = _load();
    }
  }

  @override
  void didUpdateWidget(covariant SentenceTranslationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentence != widget.sentence) _revealed = !widget.hidden;
    if (oldWidget.sentence != widget.sentence ||
        oldWidget.highQuality != widget.highQuality) {
      _translation = _load();
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<(TranslationStatus, SentenceTranslation?)> _load() async {
    final target = _target!;
    final load = ++_loads;
    _standardNeeded = false;
    try {
      final status = await translationStatus(
        target,
        highQuality: widget.highQuality,
      );
      if (status != TranslationStatus.installed) return (status, null);
      final result = await translateSentence(
        widget.sentence,
        target,
        highQuality: widget.highQuality,
      );
      // A newer load (Gemma just became ready) replaced this one on screen.
      if (load == _loads) {
        logUsage(
          'translation.shown',
          attrs: {
            'engine': result.highQuality
                ? 'gemma'
                : (_isIos ? 'apple' : 'mozilla'),
            'source': widget.source,
          },
        );
      }
      return (status, result);
    } on StandardTranslationNeeded {
      if (load == _loads) _standardNeeded = true;
      return (TranslationStatus.needsDownload, null);
    } catch (e) {
      logFailure('translation.failed', e);
      rethrow;
    }
  }

  void _reload() => setState(() {
    _translation = _load();
  });

  Future<void> _download() async {
    final target = _target!;
    if (!await confirmTranslationMemory(context) || !mounted) return;
    final size = translationDownloadSize(target);
    if (!_isIos &&
        !await okToDownload(
          context,
          size: size,
          body: context.l10n.translationMobileDataBody(size: size),
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _downloading = true);
    Object? failure;
    try {
      await downloadTranslation(target);
      logUsage('translation.model_downloaded');
    } catch (e) {
      logFailure('translation.download_failed', e);
      failure = e;
    }
    if (!mounted) return;
    setState(() {
      _downloading = false;
      // iOS users can decline Apple's prompt: ask again what is installed.
      _translation = failure == null
          ? _load()
          : (Future<(TranslationStatus, SentenceTranslation?)>.error(failure)
              ..ignore());
    });
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _editController.text = widget.sentence;
    });
    widget.onEditingStarted?.call();
  }

  void _submitEdit(String value) {
    final trimmed = value.trim();
    setState(() => _editing = false);
    if (trimmed.isNotEmpty && trimmed != widget.sentence) {
      widget.onSentenceEdited?.call(trimmed);
    }
    widget.onEditingEnded?.call();
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.readerCopiedToClipboard),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Never touched without High quality, so iOS leaves Gemma alone.
    GemmaDownloadState? gemma;
    if (widget.highQuality) {
      gemma = ref.watch(gemmaDownloadProvider);
      // The tab switches over once the model is ready.
      ref.listen(gemmaDownloadProvider, (previous, next) {
        if (next is GemmaInstalled && previous is! GemmaInstalled) _reload();
      });
    }
    return ListView(
      controller: widget.scrollController,
      // Never the route's scroll controller: offstage, this view sits next
      // to the dictionary results, which may use it.
      primary: false,
      shrinkWrap: widget.shrinkWrap,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _editing ? _buildEditor() : _buildSentence(context),
        const SizedBox(height: 16),
        FutureBuilder<(TranslationStatus, SentenceTranslation?)>(
          future: _translation,
          builder: (context, snapshot) =>
              _buildTranslation(context, snapshot, gemma),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    return TextField(
      controller: _editController,
      autofocus: true,
      maxLines: null,
      textInputAction: TextInputAction.done,
      style: TextStyle(fontSize: widget.fontSize + 2),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: _submitEdit,
    );
  }

  Widget _buildSentence(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontSize: widget.fontSize + 2,
      height: 1.6,
    );
    final sentence = widget.sentence;
    final word = widget.word;
    // ponytail: a word that occurs twice highlights its first occurrence;
    // the tap position is not carried this far.
    final at = word.isEmpty ? -1 : sentence.indexOf(word);
    final text = at < 0
        ? SelectableText(sentence, style: style)
        : SelectableText.rich(
            TextSpan(
              children: [
                TextSpan(text: sentence.substring(0, at)),
                TextSpan(
                  text: word,
                  style: TextStyle(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                TextSpan(text: sentence.substring(at + word.length)),
              ],
            ),
            style: style,
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 20),
          tooltip: context.l10n.commonCopy,
          onPressed: () => _copy(sentence),
        ),
        if (widget.onSentenceEdited != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: context.l10n.sentenceTranslationEdit,
            onPressed: _startEditing,
          ),
      ],
    );
  }

  Widget _buildTranslation(
    BuildContext context,
    AsyncSnapshot<(TranslationStatus, SentenceTranslation?)> snapshot,
    GemmaDownloadState? gemma,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (snapshot.hasError) {
      return Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.sentenceTranslationFailed,
              style: muted?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: _reload, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }
    final data = snapshot.data;
    if (data == null || snapshot.connectionState == ConnectionState.waiting) {
      const spinner = Center(child: CircularProgressIndicator());
      if (!widget.highQuality) return spinner;
      return ValueListenableBuilder<bool>(
        valueListenable: GemmaTranslation.instance.loading,
        builder: (context, loading, _) => Column(
          children: [
            spinner,
            if (loading) _note(l10n.translationHighQualityStarting),
          ],
        ),
      );
    }
    final (status, result) = data;
    switch (status) {
      case TranslationStatus.unsupported:
        return Text(l10n.sentenceTranslationUnsupported, style: muted);
      case TranslationStatus.needsDownload:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _standardNeeded
                  ? l10n.translationHighQualityNeedsStandard
                  : _isIos
                  ? l10n.sentenceTranslationDownloadIos
                  : l10n.sentenceTranslationDownload(
                      size: translationDownloadSize(_target!),
                    ),
              style: muted,
            ),
            const SizedBox(height: 12),
            if (_downloading)
              const LinearProgressIndicator()
            else
              FilledButton.tonal(
                onPressed: _download,
                child: Text(l10n.commonDownload),
              ),
          ],
        );
      case TranslationStatus.installed:
        if (!_revealed) {
          return InkWell(
            onTap: () => setState(() => _revealed = true),
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.sentenceTranslationTapToShow,
                      style: muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final text = result?.text ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: SelectableText(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: widget.fontSize,
                  height: 1.5,
                ),
              ),
            ),
            if (widget.highQuality)
              switch (gemma) {
                _ when result?.timedOut ?? false => _note(
                  l10n.translationHighQualityTooSlow,
                ),
                // Installed, so Gemma failed to load or translate.
                GemmaInstalled() when !(result?.highQuality ?? true) => _note(
                  l10n.translationHighQualityCouldNotLoad,
                ),
                _ when !(result?.highQuality ?? true) => _note(
                  l10n.translationHighQualityNotReady,
                ),
                _ => const SizedBox.shrink(),
              },
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isIos
                        ? l10n.sentenceTranslationEngineIos
                        : l10n.sentenceTranslationEngine,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  tooltip: l10n.commonCopy,
                  onPressed: () => _copy(text),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _note(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
