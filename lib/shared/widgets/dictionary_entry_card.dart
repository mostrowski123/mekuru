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
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_definition_text.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/tappable_expression_text.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:mekuru/main.dart' show scaffoldMessengerKey;
import 'package:mekuru/shared/widgets/furigana_text.dart';
import 'package:mekuru/shared/widgets/pitch_accent_diagram.dart';

/// A unified card for displaying a single dictionary entry.
///
/// Used by both the dictionary search screen and the reader lookup sheet.
/// When [onWordTap] is provided, expressions and definitions become tappable
/// (interactive mode). When null, plain text is displayed (non-interactive mode).
class DictionaryEntryCard extends ConsumerStatefulWidget {
  const DictionaryEntryCard({
    super.key,
    required this.entry,
    required this.dictionaryName,
    required this.pitchAccents,
    this.fontSize = 16.0,
    this.frequencyRank,
    this.sentenceContext,
    this.onWordTap,
  });

  /// The dictionary entry to display.
  final DictionaryEntry entry;

  /// Name of the source dictionary (shown as a badge).
  final String dictionaryName;

  /// Pre-fetched and pre-filtered pitch accent results for this entry.
  final List<PitchAccentResult> pitchAccents;

  /// Base font size for the card content.
  final double fontSize;

  /// Frequency rank from the JPDB frequency dictionary.
  final int? frequencyRank;

  /// Sentence context from the reader (used when saving to vocabulary).
  final String? sentenceContext;

  /// Callback when a Japanese word or kanji character is tapped.
  /// When null, non-interactive FuriganaText and plain Text are used.
  final void Function(String word)? onWordTap;

  @override
  ConsumerState<DictionaryEntryCard> createState() =>
      _DictionaryEntryCardState();
}

class _DictionaryEntryCardState extends ConsumerState<DictionaryEntryCard> {
  bool _isSaved = false;
  bool _isInAnki = false;
  bool _isCheckingAnki = false;
  int _ankiLookupRequestId = 0;
  String? _lastAnkiLookupCacheKey;

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
  void didUpdateWidget(covariant DictionaryEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final entryChanged =
        oldWidget.entry.expression != widget.entry.expression ||
        oldWidget.entry.reading != widget.entry.reading;
    if (entryChanged) {
      _checkIfSaved();
    }

    _checkIfInAnki();
  }

  Future<void> _checkIfSaved() async {
    final repo = ref.read(vocabularyRepositoryProvider);
    final saved = await repo.isWordSaved(
      widget.entry.expression,
      widget.entry.reading,
    );
    if (mounted) {
      setState(() => _isSaved = saved);
    }
  }

  Future<void> _toggleSave() async {
    if (_isSaved) return;
    final repo = ref.read(vocabularyRepositoryProvider);
    await repo.addWord(
      entry: widget.entry,
      sentenceContext: widget.sentenceContext ?? '',
    );
    if (mounted) {
      setState(() => _isSaved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${widget.entry.expression}"'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showVocabAlreadySavedToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Word already exists in vocab list'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyExpression() {
    Clipboard.setData(ClipboardData(text: widget.entry.expression));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${widget.entry.expression}"'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAnkiAlreadySavedToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Word already exists in default deck'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  AnkiNoteData _buildAnkiNoteData() {
    return AnkiNoteData(
      expression: widget.entry.expression,
      reading: widget.entry.reading,
      glossaries: widget.entry.glossaries,
      dictionaryName: widget.dictionaryName,
      frequencyRank: widget.frequencyRank,
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
                content: Text('Added "${widget.entry.expression}" to Anki'),
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
    final ankidroidConfig = ref.watch(ankidroidConfigProvider);
    final fs = widget.fontSize;
    final definitions = GlossaryParser.parse(widget.entry.glossaries);

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

    final badgeStyle = TextStyle(
      fontSize: fs * 0.75,
      color: theme.colorScheme.onSurfaceVariant,
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
          // Row 1: Expression + reading, badges, copy & bookmark buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildExpression(expressionStyle, furiganaStyle),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.dictionaryName,
                              style: badgeStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _FrequencyTag(
                            rank: widget.frequencyRank,
                            fontSize: fs,
                          ),
                        ],
                      ),
                    ),
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
                      : Icon(
                          _isInAnki
                              ? Icons.check
                              : Icons.electric_bolt_outlined,
                        ),
                  tooltip: _isInAnki
                      ? 'Already in default Anki deck. Long press to add anyway'
                      : _isCheckingAnki && ankidroidConfig.isConfigured
                      ? 'Checking default Anki deck'
                      : 'Send to AnkiDroid',
                  iconSize: 20,
                ),
              IconButton.filledTonal(
                onPressed: _isSaved ? _showVocabAlreadySavedToast : _toggleSave,
                icon: Icon(
                  _isSaved ? Icons.check : Icons.bookmark_add_outlined,
                ),
                tooltip: _isSaved
                    ? 'Already in vocab list'
                    : 'Save to Vocabulary',
              ),
            ],
          ),

          // Row 2: Pitch accent diagrams grouped by source (if available)
          if (widget.pitchAccents.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildPitchAccents(theme, fs),
          ],

          // Row 3+: Definitions
          const SizedBox(height: 8),
          ...definitions.map(
            (def) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '- ',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: fs,
                    ),
                  ),
                  Expanded(child: _buildDefinition(def, definitionStyle)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the expression widget — tappable or plain depending on [onWordTap].
  Widget _buildExpression(TextStyle expressionStyle, TextStyle furiganaStyle) {
    if (widget.onWordTap != null) {
      return TappableExpressionText(
        expression: widget.entry.expression,
        reading: widget.entry.reading,
        expressionStyle: expressionStyle,
        furiganaStyle: furiganaStyle,
        onKanjiTap: widget.onWordTap!,
      );
    }
    return FuriganaText(
      expression: widget.entry.expression,
      reading: widget.entry.reading,
      expressionStyle: expressionStyle,
      furiganaStyle: furiganaStyle,
    );
  }

  /// Builds a definition line — tappable or plain depending on [onWordTap].
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

  /// Builds pitch accent diagrams grouped by source dictionary.
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
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
