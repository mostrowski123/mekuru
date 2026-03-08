import 'package:flutter/gestures.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen listing all downloadable assets (dictionaries, kanji data, etc.).
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kanjiVgProvider.notifier).checkStatus();
      ref.read(jpdbFreqProvider.notifier).checkStatus();
      ref.read(jmdictProvider.notifier).checkStatus();
      ref.read(kanjidicProvider.notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kanjiVgState = ref.watch(kanjiVgProvider);
    final jpdbFreqState = ref.watch(jpdbFreqProvider);
    final jmdictState = ref.watch(jmdictProvider);
    final kanjidicState = ref.watch(kanjidicProvider);
    final theme = Theme.of(context);
    final starterPackReady = jmdictState.isImported && jpdbFreqState.isImported;
    final starterPackBusy =
        jmdictState.isDownloading || jpdbFreqState.isDownloading;
    final hasDictionarySuccess =
        jmdictState.successMessage != null ||
        kanjidicState.successMessage != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadsTitle)),
      body: ListView(
        children: [
          // ── Dictionaries ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.downloadsRecommendedStarterPackTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.downloadsRecommendedStarterPackSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StarterPackStatusRow(
                    label: l10n.downloadsStarterPackJmdict,
                    isReady: jmdictState.isImported,
                  ),
                  const SizedBox(height: 8),
                  _StarterPackStatusRow(
                    label: l10n.downloadsStarterPackWordFrequency,
                    isReady: jpdbFreqState.isImported,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: starterPackBusy
                            ? null
                            : () {
                                AppHaptics.light();
                                if (starterPackReady) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const DictionarySearchScreen(),
                                    ),
                                  );
                                  return;
                                }
                                _installStarterPack();
                              },
                        icon: Icon(
                          starterPackReady
                              ? Icons.search
                              : Icons.download_outlined,
                        ),
                        label: Text(
                          starterPackReady
                              ? l10n.commonOpenDictionary
                              : l10n.downloadsInstallStarterPack,
                        ),
                      ),
                      if (hasDictionarySuccess && !starterPackReady)
                        OutlinedButton(
                          onPressed: () {
                            AppHaptics.light();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DictionarySearchScreen(),
                              ),
                            );
                          },
                          child: Text(l10n.commonOpenDictionary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _SectionHeader(title: l10n.downloadsSectionDictionaries),

          // JMdict English
          _JmdictTile(state: jmdictState, theme: theme),
          if (jmdictState.isDownloading)
            _DownloadProgress(
              progress: jmdictState.progress,
              label: jmdictState.progress < 0.05
                  ? l10n.downloadsFetchingLatestRelease
                  : jmdictState.progress < 0.7
                  ? l10n.downloadsDownloadingPercent(
                      percent: ((jmdictState.progress - 0.05) / 0.65 * 100)
                          .toInt(),
                    )
                  : l10n.downloadsImporting,
              theme: theme,
            ),
          if (jmdictState.error != null)
            _ErrorText(text: jmdictState.error!, theme: theme),
          if (jmdictState.successMessage != null)
            _SuccessText(text: jmdictState.successMessage!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _AttributionText(
              prefix: '',
              linkText: 'JMdict',
              url:
                  'https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project',
              suffix:
                  ' by the Electronic Dictionary Research and '
                  'Development Group (EDRDG), licensed under CC BY-SA 4.0.',
              theme: theme,
            ),
          ),
          const SizedBox(height: 8),

          // KANJIDIC
          _KanjidicTile(state: kanjidicState, theme: theme),
          if (kanjidicState.isDownloading)
            _DownloadProgress(
              progress: kanjidicState.progress,
              label: kanjidicState.progress < 0.05
                  ? 'Fetching latest release...'
                  : kanjidicState.progress < 0.7
                  ? 'Downloading... ${((kanjidicState.progress - 0.05) / 0.65 * 100).toInt()}%'
                  : 'Importing...',
              theme: theme,
            ),
          if (kanjidicState.error != null)
            _ErrorText(text: kanjidicState.error!, theme: theme),
          if (kanjidicState.successMessage != null)
            _SuccessText(text: kanjidicState.successMessage!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _AttributionText(
              prefix: '',
              linkText: 'KANJIDIC',
              url: 'https://www.edrdg.org/wiki/index.php/KANJIDIC_Project',
              suffix:
                  ' by the Electronic Dictionary Research and '
                  'Development Group (EDRDG), licensed under CC BY-SA 4.0.',
              theme: theme,
            ),
          ),
          const Divider(),

          // ── Assets ──
          _SectionHeader(title: l10n.downloadsSectionAssets),

          // KanjiVG
          _KanjiVgTile(state: kanjiVgState, theme: theme),
          if (kanjiVgState.isDownloading)
            _DownloadProgress(
              progress: kanjiVgState.progress,
              label: kanjiVgState.progress < 0.9
                  ? l10n.downloadsDownloadingPercent(
                      percent: (kanjiVgState.progress * 100).toInt(),
                    )
                  : l10n.downloadsExtractingFiles,
              theme: theme,
            ),
          if (kanjiVgState.error != null)
            _ErrorText(text: kanjiVgState.error!, theme: theme),
          if (kanjiVgState.successMessage != null)
            _SuccessText(text: kanjiVgState.successMessage!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _AttributionText(
              prefix: 'Kanji stroke order data by ',
              linkText: 'KanjiVG',
              url: 'https://kanjivg.tagaini.net/',
              suffix: ' (Ulrich Apel), licensed under CC BY-SA 3.0.',
              theme: theme,
            ),
          ),
          const SizedBox(height: 8),

          // JPDB Frequency
          _JpdbFreqTile(state: jpdbFreqState, theme: theme),
          if (jpdbFreqState.isDownloading)
            _DownloadProgress(
              progress: jpdbFreqState.progress,
              label: jpdbFreqState.progress < 0.7
                  ? l10n.downloadsDownloadingPercent(
                      percent: (jpdbFreqState.progress / 0.7 * 100).toInt(),
                    )
                  : l10n.downloadsImporting,
              theme: theme,
            ),
          if (jpdbFreqState.error != null)
            _ErrorText(text: jpdbFreqState.error!, theme: theme),
          if (jpdbFreqState.successMessage != null)
            _SuccessText(text: jpdbFreqState.successMessage!),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              l10n.downloadsJpdbAttribution,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _installStarterPack() {
    // Start both imports right away so they can continue even if the user
    // leaves this screen before the downloads finish.
    if (!ref.read(jmdictProvider).isImported) {
      unawaited(
        ref
            .read(jmdictProvider.notifier)
            .download(YomitanDictType.jmdictEnglish),
      );
    }
    if (!ref.read(jpdbFreqProvider).isImported) {
      unawaited(ref.read(jpdbFreqProvider.notifier).download());
    }
  }
}

// ── Shared helper widgets ──

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({
    required this.progress,
    required this.label,
    required this.theme,
  });

  final double progress;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
      ),
    );
  }
}

class _SuccessText extends StatelessWidget {
  const _SuccessText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.green, fontSize: 13),
      ),
    );
  }
}

class _AttributionText extends StatelessWidget {
  const _AttributionText({
    required this.prefix,
    required this.linkText,
    required this.url,
    required this.suffix,
    required this.theme,
  });

  final String prefix;
  final String linkText;
  final String url;
  final String suffix;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final linkStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          TextSpan(
            text: linkText,
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
          ),
          TextSpan(text: suffix),
        ],
      ),
    );
  }
}

class _StarterPackStatusRow extends StatelessWidget {
  const _StarterPackStatusRow({required this.label, required this.isReady});

  final String label;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          isReady ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: isReady
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

// ── Download tile widgets ──

class _KanjiVgTile extends ConsumerWidget {
  const _KanjiVgTile({required this.state, required this.theme});

  final KanjiVgState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isDownloaded
        ? l10n.downloadsKanjiStrokeOrderDownloaded(count: state.fileCount)
        : l10n.downloadsKanjiStrokeOrderDescription;

    return ListTile(
      leading: Icon(Icons.brush_outlined, color: theme.colorScheme.primary),
      title: Text(l10n.downloadsKanjiStrokeOrderTitle),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isDownloaded) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.downloadsDeleteKanjiDataTooltip,
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        ref.read(kanjiVgProvider.notifier).download();
      },
      child: Text(context.l10n.commonDownload),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteKanjiDataTitle),
        content: Text(ctx.l10n.downloadsDeleteKanjiDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(kanjiVgProvider.notifier).delete();
            },
            child: Text(
              ctx.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _JpdbFreqTile extends ConsumerWidget {
  const _JpdbFreqTile({required this.state, required this.theme});

  final JpdbFreqState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isImported
        ? l10n.downloadsWordFrequencyDownloaded
        : l10n.downloadsWordFrequencyDescription;

    return ListTile(
      leading: Icon(Icons.bar_chart_outlined, color: theme.colorScheme.primary),
      title: Text(l10n.downloadsStarterPackWordFrequency),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isImported) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.downloadsDeleteFrequencyDataTooltip,
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        ref.read(jpdbFreqProvider.notifier).download();
      },
      child: Text(context.l10n.commonDownload),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteFrequencyDataTitle),
        content: Text(ctx.l10n.downloadsDeleteFrequencyDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(jpdbFreqProvider.notifier).delete();
            },
            child: Text(
              ctx.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _JmdictTile extends ConsumerWidget {
  const _JmdictTile({required this.state, required this.theme});

  final JmdictState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isImported
        ? l10n.downloadsJmdictDownloaded
        : l10n.downloadsJmdictDescription;

    return ListTile(
      leading: Icon(Icons.translate, color: theme.colorScheme.primary),
      title: Text(l10n.downloadsStarterPackJmdict),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isImported) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.downloadsDeleteJmdictTooltip,
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        _showVariantPicker(context, ref);
      },
      child: Text(context.l10n.commonDownload),
    );
  }

  void _showVariantPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                ctx.l10n.downloadsChooseJmdictVariant,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(ctx.l10n.downloadsStarterPackJmdict),
              subtitle: Text(ctx.l10n.downloadsJmdictStandardSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                AppHaptics.light();
                ref
                    .read(jmdictProvider.notifier)
                    .download(YomitanDictType.jmdictEnglish);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(ctx.l10n.downloadsJmdictExamplesTitle),
              subtitle: Text(ctx.l10n.downloadsJmdictExamplesSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                AppHaptics.light();
                ref
                    .read(jmdictProvider.notifier)
                    .download(YomitanDictType.jmdictEnglishWithExamples);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteJmdictTitle),
        content: Text(ctx.l10n.downloadsDeleteJmdictBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(jmdictProvider.notifier).delete();
            },
            child: Text(
              ctx.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanjidicTile extends ConsumerWidget {
  const _KanjidicTile({required this.state, required this.theme});

  final KanjidicState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final subtitle = state.isImported
        ? l10n.downloadsKanjidicDownloaded
        : l10n.downloadsKanjidicDescription;

    return ListTile(
      leading: Icon(
        Icons.font_download_outlined,
        color: theme.colorScheme.primary,
      ),
      title: const Text('KANJIDIC'),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isImported) {
      return IconButton(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: context.l10n.downloadsDeleteKanjidicTooltip,
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        ref.read(kanjidicProvider.notifier).download();
      },
      child: Text(context.l10n.commonDownload),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.downloadsDeleteKanjidicTitle),
        content: Text(ctx.l10n.downloadsDeleteKanjidicBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(kanjidicProvider.notifier).delete();
            },
            child: Text(
              ctx.l10n.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
