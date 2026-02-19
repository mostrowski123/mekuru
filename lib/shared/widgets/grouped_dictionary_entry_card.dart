import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/ankidroid/data/models/anki_note_data.dart';
import 'package:mekuru/features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/anki_card_creation_screen.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_definition_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_expression_text.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:mekuru/main.dart' show scaffoldMessengerKey;
import 'package:mekuru/shared/widgets/furigana_text.dart';
import 'package:mekuru/shared/widgets/pitch_accent_diagram.dart';

/// A card that displays all dictionary definitions for a single
/// (expression, reading) group.
///
/// Multiple dictionaries' definitions are shown inside one card, each
/// tagged with the dictionary name. This replaces rendering one
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

  DictionaryEntry get _primaryEntry => widget.entries.first.entry;
  int? get _frequencyRank => widget.entries.first.frequencyRank;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
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
          content: Text('Saved "${_primaryEntry.expression}"'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyExpression() {
    Clipboard.setData(ClipboardData(text: _primaryEntry.expression));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${_primaryEntry.expression}"'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _sendToAnki() {
    final config = ref.read(ankidroidConfigProvider);
    if (!config.isConfigured) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AnkidroidSettingsScreen(),
        ),
      );
      return;
    }

    final noteData = AnkiNoteData(
      expression: _primaryEntry.expression,
      reading: _primaryEntry.reading,
      glossaries: _primaryEntry.glossaries,
      dictionaryName: widget.entries.first.dictionaryName,
      frequencyRank: _frequencyRank,
      sentenceContext: widget.sentenceContext,
      pitchAccents: widget.pitchAccents,
    );
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnkiCardCreationScreen(noteData: noteData),
      ),
    ).then((result) {
      if (result == true) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Added "${_primaryEntry.expression}" to Anki'),
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

    final definitionStyle = TextStyle(
      fontSize: fs,
      color: theme.colorScheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Expression + reading, frequency, action buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildExpression(expressionStyle, furiganaStyle),
                    const SizedBox(width: 8),
                    if (_frequencyRank != null)
                      _FrequencyTag(rank: _frequencyRank!, fontSize: fs),
                  ],
                ),
              ),
              IconButton(
                onPressed: _copyExpression,
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copy',
                iconSize: 20,
              ),
              if (defaultTargetPlatform == TargetPlatform.android)
                IconButton(
                  onPressed: _sendToAnki,
                  icon: const Icon(Icons.electric_bolt_outlined),
                  tooltip: 'Send to AnkiDroid',
                  iconSize: 20,
                ),
              IconButton.filledTonal(
                onPressed: _isSaved ? null : _toggleSave,
                icon: Icon(
                  _isSaved ? Icons.check : Icons.bookmark_add_outlined,
                ),
                tooltip: _isSaved ? 'Saved' : 'Save to Vocabulary',
              ),
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
      ),
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

  /// Build definitions for each dictionary in the group, with dictionary
  /// name tags separating them. Entries from the same dictionary are grouped
  /// under a single tag and numbered when there are multiple.
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
    for (final dictName in dictOrder) {
      // Dictionary name tag (once per dictionary)
      widgets.add(
        Padding(
          padding: EdgeInsets.only(
            top: widgets.length <= 1 ? 0 : 8,
            bottom: 4,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              dictName,
              style: TextStyle(
                fontSize: fs * 0.75,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: bySource.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: entry.value.map((p) {
                    return PitchAccentDiagram(
                      reading: p.reading,
                      downstepPosition: p.downstepPosition,
                      fontSize: fontSize * 0.9,
                      color: theme.colorScheme.onSurface,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: fontSize * 0.6,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// A small colored tag showing word frequency level.
class _FrequencyTag extends StatelessWidget {
  const _FrequencyTag({required this.rank, required this.fontSize});

  final int rank;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final label = DictionaryEntryWithSource.frequencyLabel(rank);
    if (label == null) return const SizedBox.shrink();

    final Color color;
    if (rank <= 5000) {
      color = Colors.green;
    } else if (rank <= 15000) {
      color = Colors.blue;
    } else if (rank <= 30000) {
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
