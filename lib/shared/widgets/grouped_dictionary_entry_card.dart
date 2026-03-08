import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/data/services/anki_field_mapper.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/anki_card_creation_screen.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/features/dictionary/data/services/kanji_reading_parser.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/kanji_readings_block.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/source_section_label.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_definition_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_expression_text.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/main.dart' show scaffoldMessengerKey;
import 'package:mekuru/shared/widgets/furigana_text.dart';
import 'package:mekuru/shared/widgets/pitch_accent_diagram.dart';

/// A card that displays all dictionary definitions for a single
/// (expression, reading) group.
///
/// Multiple dictionaries' definitions are shown inside one card, each
/// grouped under a subtle source label. This replaces rendering one
/// [DictionaryEntryCard] per dictionary entry.
class GroupedDictionaryEntryCard extends ConsumerStatefulWidget {
  const GroupedDictionaryEntryCard({
    super.key,
    required this.entries,
    required this.pitchAccents,
    this.fontSize = 16.0,
    this.sentenceContext,
    this.onWordTap,
  });

  /// All dictionary entries sharing the same (expression, reading).
  /// Must be non-empty. Ordered by dictionary sort order.
  final List<DictionaryEntryWithSource> entries;

  /// Pre-fetched and pre-filtered pitch accent results for this group.
  final List<PitchAccentResult> pitchAccents;

  /// Base font size for the card content.
  final double fontSize;

  /// Sentence context from the reader (used when saving to vocabulary).
  final String? sentenceContext;

  /// Callback when a Japanese word or kanji character is tapped.
  final void Function(String word)? onWordTap;

  @override
  ConsumerState<GroupedDictionaryEntryCard> createState() =>
      _GroupedDictionaryEntryCardState();
}

class _GroupedDictionaryEntryCardState
    extends ConsumerState<GroupedDictionaryEntryCard> {
  bool _isSaved = false;
  bool _isInAnki = false;
  bool _isCheckingAnki = false;
  int _ankiLookupRequestId = 0;
  String? _lastAnkiLookupCacheKey;

  DictionaryEntryWithSource get _primaryResult => widget.entries.first;
  DictionaryEntry get _primaryEntry => _primaryResult.entry;
  int? get _frequencyRank => widget.entries.first.frequencyRank;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
    _checkIfInAnki();
    ref.listenManual(ankidroidConfigProvider, (previous, next) {
      _checkIfInAnki(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant GroupedDictionaryEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final entryChanged =
        oldWidget.entries.first.entry.expression != _primaryEntry.expression ||
        oldWidget.entries.first.entry.reading != _primaryEntry.reading;
    if (entryChanged) {
      _checkIfSaved();
    }

    _checkIfInAnki();
  }

  Future<void> _checkIfSaved() async {
    final repo = ref.read(vocabularyRepositoryProvider);
    final saved = await repo.isWordSaved(
      _primaryEntry.expression,
      _primaryEntry.reading,
    );
    if (mounted) {
      setState(() => _isSaved = saved);
    }
  }

  Future<void> _toggleSave() async {
    if (_isSaved) return;
    final repo = ref.read(vocabularyRepositoryProvider);
    await repo.addWord(
      entry: _primaryEntry,
      sentenceContext: widget.sentenceContext ?? '',
    );
    if (mounted) {
      setState(() => _isSaved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.dictionarySavedWord(
              expression: _primaryEntry.expression,
            ),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showVocabAlreadySavedToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.dictionaryWordAlreadyExistsInVocab),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyExpression() {
    Clipboard.setData(ClipboardData(text: _primaryEntry.expression));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.dictionaryCopiedWord(
            expression: _primaryEntry.expression,
          ),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAnkiAlreadySavedToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.dictionaryWordAlreadyExistsInAnki),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  AnkiNoteData _buildAnkiNoteData() {
    return AnkiNoteData(
      expression: _primaryEntry.expression,
      reading: _primaryEntry.reading,
      glossaries: _primaryEntry.glossaries,
      dictionaryName: _primaryResult.dictionaryName,
      frequencyRank: _frequencyRank,
      sentenceContext: widget.sentenceContext,
      pitchAccents: widget.pitchAccents,
    );
  }

  ({String cacheKey, int modelId, int deckId, String firstFieldValue})?
  _buildAnkiDuplicateLookup() {
    final config = ref.read(ankidroidConfigProvider);
    final modelId = config.modelId;
    final deckId = config.deckId;
    if (modelId == null || deckId == null) return null;

    final firstFieldValue = resolveAnkiFirstFieldValue(
      config: config,
      noteData: _buildAnkiNoteData(),
    );
    if (firstFieldValue == null) return null;

    return (
      cacheKey: '$modelId\u0000$deckId\u0000$firstFieldValue',
      modelId: modelId,
      deckId: deckId,
      firstFieldValue: firstFieldValue,
    );
  }

  Future<void> _checkIfInAnki({bool force = false}) async {
    final lookup = _buildAnkiDuplicateLookup();
    final cacheKey = lookup?.cacheKey;
    if (!force && cacheKey == _lastAnkiLookupCacheKey) return;
    _lastAnkiLookupCacheKey = cacheKey;

    final requestId = ++_ankiLookupRequestId;
    if (lookup == null) {
      if (mounted) {
        setState(() {
          _isInAnki = false;
          _isCheckingAnki = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isInAnki = false;
        _isCheckingAnki = true;
      });
    }

    final exists = await ref
        .read(ankidroidServiceProvider)
        .hasDuplicateInDeck(
          modelId: lookup.modelId,
          deckId: lookup.deckId,
          firstFieldValue: lookup.firstFieldValue,
        );
    if (!mounted || requestId != _ankiLookupRequestId) return;

    setState(() {
      _isInAnki = exists;
      _isCheckingAnki = false;
    });
  }

  void _sendToAnki() {
    final config = ref.read(ankidroidConfigProvider);
    final addedToAnkiMessage = context.l10n.dictionaryAddedToAnki(
      expression: _primaryEntry.expression,
    );
    if (!config.isConfigured) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AnkidroidSettingsScreen()),
      );
      return;
    }

    final noteData = _buildAnkiNoteData();
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => AnkiCardCreationScreen(noteData: noteData),
          ),
        )
        .then((result) {
          if (result == true) {
            _checkIfInAnki(force: true);
            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text(addedToAnkiMessage),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fs = widget.fontSize;
    final kanjiDisplayData = parseKanjiEntryDisplayData(
      entry: _primaryEntry,
      dictionaryName: _primaryResult.dictionaryName,
    );

    final expressionStyle = TextStyle(
      fontSize: fs * 1.25,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface,
    );

    final furiganaStyle = TextStyle(
      fontSize: fs * 0.7,
      fontWeight: FontWeight.w400,
      color: theme.colorScheme.onSurface,
      height: 1.0,
    );

    final definitionStyle = TextStyle(
      fontSize: fs,
      color: theme.colorScheme.onSurface,
    );

    final actionButtons = _buildActionButtons();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 260;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact) ...[
                _buildHeaderContent(
                  theme,
                  expressionStyle,
                  furiganaStyle,
                  kanjiDisplayData,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: actionButtons),
              ] else
                Row(
                  crossAxisAlignment: kanjiDisplayData == null
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildHeaderContent(
                        theme,
                        expressionStyle,
                        furiganaStyle,
                        kanjiDisplayData,
                      ),
                    ),
                    ...actionButtons,
                  ],
                ),

              // Row 2: Pitch accent diagrams (if available)
              if (widget.pitchAccents.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildPitchAccents(theme, fs),
              ],

              // Row 3+: Definitions grouped by dictionary
              const SizedBox(height: 8),
              ..._buildGroupedDefinitions(theme, fs, definitionStyle),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildActionButtons() {
    final ankidroidConfig = ref.watch(ankidroidConfigProvider);
    return [
      IconButton(
        onPressed: _copyExpression,
        icon: const Icon(Icons.copy_outlined),
        tooltip: context.l10n.dictionaryCopyTooltip,
        iconSize: 20,
      ),
      if (defaultTargetPlatform == TargetPlatform.android)
        IconButton(
          onPressed: _isCheckingAnki && ankidroidConfig.isConfigured
              ? null
              : _isInAnki
              ? _showAnkiAlreadySavedToast
              : _sendToAnki,
          onLongPress: _isInAnki ? _sendToAnki : null,
          icon: _isCheckingAnki && ankidroidConfig.isConfigured
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isInAnki ? Icons.check : Icons.electric_bolt_outlined),
          tooltip: _isInAnki
              ? context.l10n.dictionaryAlreadyInAnkiTooltip
              : _isCheckingAnki && ankidroidConfig.isConfigured
              ? context.l10n.dictionaryCheckingAnkiTooltip
              : context.l10n.dictionarySendToAnkiTooltip,
          iconSize: 20,
        ),
      IconButton.filledTonal(
        onPressed: _isSaved ? _showVocabAlreadySavedToast : _toggleSave,
        icon: Icon(_isSaved ? Icons.check : Icons.bookmark_add_outlined),
        tooltip: _isSaved
            ? context.l10n.dictionaryAlreadyInVocabTooltip
            : context.l10n.dictionarySaveToVocabularyTooltip,
      ),
    ];
  }

  Widget _buildHeaderContent(
    ThemeData theme,
    TextStyle expressionStyle,
    TextStyle furiganaStyle,
    KanjiEntryDisplayData? kanjiDisplayData,
  ) {
    if (kanjiDisplayData == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: _buildExpression(expressionStyle, furiganaStyle)),
          const SizedBox(width: 8),
          _FrequencyTag(rank: _frequencyRank, fontSize: widget.fontSize),
        ],
      );
    }

    final readingLabelStyle = TextStyle(
      fontSize: widget.fontSize * 0.72,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final readingStyle = TextStyle(
      fontSize: widget.fontSize * 0.9,
      color: theme.colorScheme.onSurface,
      height: 1.2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKanjiExpression(theme, expressionStyle),
        if (kanjiDisplayData.hasReadings) ...[
          const SizedBox(height: 4),
          KanjiReadingsBlock(
            data: kanjiDisplayData,
            labelStyle: readingLabelStyle,
            readingStyle: readingStyle,
          ),
        ],
      ],
    );
  }

  Widget _buildKanjiExpression(ThemeData theme, TextStyle expressionStyle) {
    if (widget.onWordTap == null) {
      return Text(_primaryEntry.expression, style: expressionStyle);
    }

    final tappableStyle = expressionStyle.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: theme.colorScheme.primary.withAlpha(100),
    );

    return GestureDetector(
      onTap: () => widget.onWordTap!(_primaryEntry.expression),
      child: Text(_primaryEntry.expression, style: tappableStyle),
    );
  }

  /// Build the expression widget — tappable or plain.
  Widget _buildExpression(TextStyle expressionStyle, TextStyle furiganaStyle) {
    if (widget.onWordTap != null) {
      return TappableExpressionText(
        expression: _primaryEntry.expression,
        reading: _primaryEntry.reading,
        expressionStyle: expressionStyle,
        furiganaStyle: furiganaStyle,
        onKanjiTap: widget.onWordTap!,
      );
    }
    return FuriganaText(
      expression: _primaryEntry.expression,
      reading: _primaryEntry.reading,
      expressionStyle: expressionStyle,
      furiganaStyle: furiganaStyle,
    );
  }

  /// Build definitions for each dictionary in the group, with a subdued source
  /// footer shown after each section. Entries from the same dictionary are
  /// grouped under a single footer label and numbered when there are multiple.
  List<Widget> _buildGroupedDefinitions(
    ThemeData theme,
    double fs,
    TextStyle definitionStyle,
  ) {
    // Group entries by dictionary name, preserving order.
    final byDict = <String, List<DictionaryEntryWithSource>>{};
    final dictOrder = <String>[];
    for (final result in widget.entries) {
      if (!byDict.containsKey(result.dictionaryName)) {
        dictOrder.add(result.dictionaryName);
        byDict[result.dictionaryName] = [];
      }
      byDict[result.dictionaryName]!.add(result);
    }

    final widgets = <Widget>[];
    for (var dictIndex = 0; dictIndex < dictOrder.length; dictIndex++) {
      final dictName = dictOrder[dictIndex];
      final entries = byDict[dictName]!;
      final showNumbers = entries.length > 1;

      for (var i = 0; i < entries.length; i++) {
        final definitions = GlossaryParser.parse(entries[i].entry.glossaries);
        // Flatten multi-line bulleted definitions into a single
        // semicolon-separated line.
        final fragments = definitions
            .expand((d) => d.split('\n'))
            .map((s) => s.replaceFirst(RegExp(r'^\s*\u25b8\s*'), '').trim())
            .where((s) => s.isNotEmpty);
        final joined = fragments.join('; ');
        final text = showNumbers ? '${i + 1}. $joined' : joined;

        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildDefinition(text, definitionStyle),
          ),
        );
      }

      widgets.add(
        SourceSectionLabel(
          label: dictName,
          topPadding: 2,
          bottomPadding: dictIndex < dictOrder.length - 1 ? 10 : 0,
          fontSize: fs * 0.64,
        ),
      );
    }

    return widgets;
  }

  /// Build a definition line — tappable or plain.
  Widget _buildDefinition(String text, TextStyle style) {
    if (widget.onWordTap != null) {
      return TappableDefinitionText(
        text: text,
        style: style,
        onWordTap: widget.onWordTap!,
      );
    }
    return Text(text, style: style);
  }

  /// Build pitch accent diagrams grouped by source dictionary.
  Widget _buildPitchAccents(ThemeData theme, double fontSize) {
    final bySource = <String, List<PitchAccentResult>>{};
    for (final p in widget.pitchAccents) {
      bySource.putIfAbsent(p.dictionaryName, () => []).add(p);
    }

    final sourceEntries = bySource.entries.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sourceEntries.length; i++)
          _buildPitchAccentSourceGroup(
            sourceEntries[i].key,
            sourceEntries[i].value,
            theme,
            fontSize,
            showDivider: i > 0,
          ),
      ],
    );
  }

  Widget _buildPitchAccentSourceGroup(
    String sourceName,
    List<PitchAccentResult> accents,
    ThemeData theme,
    double fontSize, {
    required bool showDivider,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: showDivider ? 8 : 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: accents.map((p) {
              return PitchAccentDiagram(
                reading: p.reading,
                downstepPosition: p.downstepPosition,
                fontSize: fontSize * 0.9,
                color: theme.colorScheme.onSurface,
              );
            }).toList(),
          ),
          SourceSectionLabel(
            label: sourceName,
            topPadding: 4,
            bottomPadding: 0,
            fontSize: fontSize * 0.6,
          ),
        ],
      ),
    );
  }
}

/// A small colored tag showing word frequency level.
class _FrequencyTag extends StatelessWidget {
  const _FrequencyTag({required this.rank, required this.fontSize});

  final int? rank;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final label = DictionaryEntryWithSource.frequencyLabel(rank);
    final resolvedRank = DictionaryEntryWithSource.sortFrequencyRank(rank);

    final Color color;
    if (resolvedRank <= 5000) {
      color = Colors.green;
    } else if (resolvedRank <= 15000) {
      color = Colors.blue;
    } else if (resolvedRank <= 30000) {
      color = Colors.orange;
    } else {
      color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withAlpha(150)),
        borderRadius: BorderRadius.circular(4),
        color: color.withAlpha(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize * 0.65,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
