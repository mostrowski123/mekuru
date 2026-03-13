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
import 'package:mekuru/features/dictionary/data/services/part_of_speech_resolver.dart';
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
class GroupedDictionaryEntryCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupedDictionaryEntryHeader(
          entries: entries,
          pitchAccents: pitchAccents,
          fontSize: fontSize,
          sentenceContext: sentenceContext,
          onWordTap: onWordTap,
        ),
        GroupedDictionaryEntryBody(
          entries: entries,
          pitchAccents: pitchAccents,
          fontSize: fontSize,
          onWordTap: onWordTap,
        ),
      ],
    );
  }
}

class GroupedDictionaryEntryHeader extends ConsumerStatefulWidget {
  const GroupedDictionaryEntryHeader({
    super.key,
    required this.entries,
    required this.pitchAccents,
    this.fontSize = 16.0,
    this.sentenceContext,
    this.onWordTap,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 10),
  });

  final List<DictionaryEntryWithSource> entries;
  final List<PitchAccentResult> pitchAccents;
  final double fontSize;
  final String? sentenceContext;
  final void Function(String word)? onWordTap;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<GroupedDictionaryEntryHeader> createState() =>
      _GroupedDictionaryEntryHeaderState();
}

class _GroupedDictionaryEntryHeaderState
    extends ConsumerState<GroupedDictionaryEntryHeader> {
  bool _isSaved = false;
  bool _isInAnki = false;
  bool _isCheckingAnki = false;
  int _ankiLookupRequestId = 0;
  String? _lastAnkiLookupCacheKey;
  KanjiEntryDisplayData? _kanjiDisplayData;

  DictionaryEntryWithSource get _primaryResult => widget.entries.first;
  DictionaryEntry get _primaryEntry => _primaryResult.entry;
  int? get _frequencyRank => _primaryResult.frequencyRank;

  @override
  void initState() {
    super.initState();
    _kanjiDisplayData = parseKanjiEntryDisplayData(
      entry: _primaryEntry,
      dictionaryName: _primaryResult.dictionaryName,
    );
    _checkIfSaved();
    _checkIfInAnki();
    ref.listenManual(ankidroidConfigProvider, (previous, next) {
      _checkIfInAnki(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant GroupedDictionaryEntryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);

    final entryChanged =
        oldWidget.entries.first.entry.expression != _primaryEntry.expression ||
        oldWidget.entries.first.entry.reading != _primaryEntry.reading;

    if (_didEntriesChange(oldWidget.entries, widget.entries)) {
      _kanjiDisplayData = parseKanjiEntryDisplayData(
        entry: _primaryEntry,
        dictionaryName: _primaryResult.dictionaryName,
      );
    }
    if (entryChanged) {
      _checkIfSaved();
    }

    _checkIfInAnki();
  }

  bool _didEntriesChange(
    List<DictionaryEntryWithSource> oldEntries,
    List<DictionaryEntryWithSource> newEntries,
  ) {
    if (identical(oldEntries, newEntries)) return false;
    if (oldEntries.length != newEntries.length) return true;

    for (var i = 0; i < oldEntries.length; i++) {
      final oldEntry = oldEntries[i];
      final newEntry = newEntries[i];
      if (oldEntry.dictionaryName != newEntry.dictionaryName ||
          oldEntry.frequencyRank != newEntry.frequencyRank ||
          oldEntry.entry.id != newEntry.entry.id ||
          oldEntry.entry.expression != newEntry.entry.expression ||
          oldEntry.entry.reading != newEntry.entry.reading ||
          oldEntry.entry.entryKind != newEntry.entry.entryKind ||
          oldEntry.entry.kanjiOnyomi != newEntry.entry.kanjiOnyomi ||
          oldEntry.entry.kanjiKunyomi != newEntry.entry.kanjiKunyomi ||
          oldEntry.entry.glossaries != newEntry.entry.glossaries) {
        return true;
      }
    }

    return false;
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

    final actionButtons = _buildActionButtons();
    final partOfSpeech = PartOfSpeechResolver.resolve(_primaryEntry);

    return Padding(
      padding: widget.padding,
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
                  _kanjiDisplayData,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: actionButtons),
              ] else
                Row(
                  crossAxisAlignment: _kanjiDisplayData == null
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildHeaderContent(
                        theme,
                        expressionStyle,
                        furiganaStyle,
                        _kanjiDisplayData,
                      ),
                    ),
                    ...actionButtons,
                  ],
                ),

              if (partOfSpeech.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildPartOfSpeechChips(theme, partOfSpeech),
              ],
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

  Widget _buildPartOfSpeechChips(
    ThemeData theme,
    List<ResolvedPartOfSpeech> items,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withAlpha(140),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withAlpha(160),
                ),
              ),
              child: Text(
                _localizePartOfSpeech(item),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  String _localizePartOfSpeech(ResolvedPartOfSpeech item) {
    switch (item.localizationKey) {
      case 'noun':
        return context.l10n.dictionaryPartOfSpeechNoun;
      case 'pronoun':
        return context.l10n.dictionaryPartOfSpeechPronoun;
      case 'prefix':
        return context.l10n.dictionaryPartOfSpeechPrefix;
      case 'suffix':
        return context.l10n.dictionaryPartOfSpeechSuffix;
      case 'counter':
        return context.l10n.dictionaryPartOfSpeechCounter;
      case 'numeric':
        return context.l10n.dictionaryPartOfSpeechNumeric;
      case 'expression':
        return context.l10n.dictionaryPartOfSpeechExpression;
      case 'interjection':
        return context.l10n.dictionaryPartOfSpeechInterjection;
      case 'conjunction':
        return context.l10n.dictionaryPartOfSpeechConjunction;
      case 'particle':
        return context.l10n.dictionaryPartOfSpeechParticle;
      case 'copula':
        return context.l10n.dictionaryPartOfSpeechCopula;
      case 'auxiliary':
        return context.l10n.dictionaryPartOfSpeechAuxiliary;
      case 'auxiliaryVerb':
        return context.l10n.dictionaryPartOfSpeechAuxiliaryVerb;
      case 'auxiliaryAdjective':
        return context.l10n.dictionaryPartOfSpeechAuxiliaryAdjective;
      case 'iAdjective':
        return context.l10n.dictionaryPartOfSpeechIAdjective;
      case 'naAdjective':
        return context.l10n.dictionaryPartOfSpeechNaAdjective;
      case 'noAdjective':
        return context.l10n.dictionaryPartOfSpeechNoAdjective;
      case 'preNounAdjectival':
        return context.l10n.dictionaryPartOfSpeechPreNounAdjectival;
      case 'adverb':
        return context.l10n.dictionaryPartOfSpeechAdverb;
      case 'toAdverb':
        return context.l10n.dictionaryPartOfSpeechToAdverb;
      case 'adverbialNoun':
        return context.l10n.dictionaryPartOfSpeechAdverbialNoun;
      case 'suruVerb':
        return context.l10n.dictionaryPartOfSpeechSuruVerb;
      case 'kuruVerb':
        return context.l10n.dictionaryPartOfSpeechKuruVerb;
      case 'ichidanVerb':
        return context.l10n.dictionaryPartOfSpeechIchidanVerb;
      case 'godanVerb':
        return context.l10n.dictionaryPartOfSpeechGodanVerb;
      case 'zuruVerb':
        return context.l10n.dictionaryPartOfSpeechZuruVerb;
      case 'intransitiveVerb':
        return context.l10n.dictionaryPartOfSpeechIntransitiveVerb;
      case 'transitiveVerb':
        return context.l10n.dictionaryPartOfSpeechTransitiveVerb;
      case null:
        return item.label;
    }

    return item.label;
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
}

class GroupedDictionaryEntryBody extends StatelessWidget {
  const GroupedDictionaryEntryBody({
    super.key,
    required this.entries,
    required this.pitchAccents,
    this.fontSize = 16.0,
    this.onWordTap,
    this.padding = const EdgeInsets.fromLTRB(16, 2, 16, 16),
  });

  final List<DictionaryEntryWithSource> entries;
  final List<PitchAccentResult> pitchAccents;
  final double fontSize;
  final void Function(String word)? onWordTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definitionStyle = TextStyle(
      fontSize: fontSize,
      color: theme.colorScheme.onSurface,
    );
    final definitionSections = _buildDefinitionSections(entries);
    final hasPitchAccents = pitchAccents.isNotEmpty;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPitchAccents) ...[
            const SizedBox(height: 6),
            _buildPitchAccents(theme, fontSize),
          ],
          if (definitionSections.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._buildGroupedDefinitions(
              fontSize,
              definitionStyle,
              definitionSections,
            ),
          ],
        ],
      ),
    );
  }

  /// Build definitions for each dictionary in the group, with a subdued source
  /// footer shown after each section. Entries from the same dictionary are
  /// grouped under a single footer label and numbered when there are multiple.
  List<Widget> _buildGroupedDefinitions(
    double fs,
    TextStyle definitionStyle,
    List<_DefinitionSectionData> definitionSections,
  ) {
    final widgets = <Widget>[];
    for (
      var dictIndex = 0;
      dictIndex < definitionSections.length;
      dictIndex++
    ) {
      final section = definitionSections[dictIndex];
      for (final line in section.lines) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildDefinition(line, definitionStyle),
          ),
        );
      }

      widgets.add(
        SourceSectionLabel(
          label: section.dictionaryName,
          topPadding: 2,
          bottomPadding: dictIndex < definitionSections.length - 1 ? 10 : 0,
          fontSize: fs * 0.64,
        ),
      );
    }

    return widgets;
  }

  /// Build a definition line — tappable or plain.
  Widget _buildDefinition(String text, TextStyle style) {
    if (onWordTap != null) {
      return TappableDefinitionText(
        text: text,
        style: style,
        onWordTap: onWordTap!,
      );
    }
    return Text(text, style: style);
  }

  /// Build pitch accent diagrams grouped by source dictionary.
  Widget _buildPitchAccents(ThemeData theme, double fontSize) {
    final bySource = <String, List<PitchAccentResult>>{};
    for (final p in pitchAccents) {
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

List<_DefinitionSectionData> _buildDefinitionSections(
  List<DictionaryEntryWithSource> entries,
) {
  final byDict = <String, List<DictionaryEntryWithSource>>{};
  final dictOrder = <String>[];
  for (final result in entries) {
    if (!byDict.containsKey(result.dictionaryName)) {
      dictOrder.add(result.dictionaryName);
      byDict[result.dictionaryName] = [];
    }
    byDict[result.dictionaryName]!.add(result);
  }

  return [
    for (final dictName in dictOrder)
      _DefinitionSectionData(
        dictionaryName: dictName,
        lines: _buildDefinitionLines(byDict[dictName]!),
      ),
  ];
}

List<String> _buildDefinitionLines(List<DictionaryEntryWithSource> entries) {
  final showNumbers = entries.length > 1;
  return [
    for (var i = 0; i < entries.length; i++)
      _formatDefinitionLine(
        entries[i].entry.glossaries,
        index: i,
        showNumbers: showNumbers,
      ),
  ];
}

String _formatDefinitionLine(
  String glossaries, {
  required int index,
  required bool showNumbers,
}) {
  final definitions = GlossaryParser.parse(glossaries);
  final fragments = definitions
      .expand((definition) => definition.split('\n'))
      .map((line) => line.replaceFirst(RegExp(r'^\s*\u25b8\s*'), '').trim())
      .where((line) => line.isNotEmpty);
  final joined = fragments.join('; ');
  return showNumbers ? '${index + 1}. $joined' : joined;
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

class _DefinitionSectionData {
  const _DefinitionSectionData({
    required this.dictionaryName,
    required this.lines,
  });

  final String dictionaryName;
  final List<String> lines;
}
