import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/data/services/glossary_parser.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:mekuru/shared/widgets/furigana_text.dart';
import 'package:mekuru/shared/widgets/pitch_accent_diagram.dart';

class LookupSheet extends ConsumerStatefulWidget {
  const LookupSheet({
    super.key,
    required this.selectedText,
    this.surfaceForm,
    this.sentenceContext,
    this.showAtTop = false,
  });

  /// The dictionary/base form to look up (primary search term).
  final String selectedText;

  /// The surface form as it appears in the text (fallback search term).
  final String? surfaceForm;

  final String? sentenceContext;

  /// When true, render as a top-aligned card instead of a draggable bottom sheet.
  final bool showAtTop;

  @override
  ConsumerState<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends ConsumerState<LookupSheet> {
  late Future<List<DictionaryEntryWithSource>> _searchResultsFuture;
  late Future<List<PitchAccentResult>> _pitchAccentsFuture;

  @override
  void initState() {
    super.initState();
    _searchResultsFuture = _searchWithFallback();
    _pitchAccentsFuture = _searchPitchAccents();
  }

  /// Search by dictionary form first; if no results, try surface form.
  Future<List<DictionaryEntryWithSource>> _searchWithFallback() async {
    final queryService = ref.read(dictionaryQueryServiceProvider);
    final results = await queryService.searchWithSource(widget.selectedText);
    if (results.isNotEmpty) return results;

    // Fallback: try surface form if different from dictionary form
    if (widget.surfaceForm != null &&
        widget.surfaceForm != widget.selectedText) {
      return queryService.searchWithSource(widget.surfaceForm!);
    }
    return results;
  }

  /// Search pitch accents by expression; fallback to surface form.
  Future<List<PitchAccentResult>> _searchPitchAccents() async {
    final queryService = ref.read(dictionaryQueryServiceProvider);
    final results =
        await queryService.searchPitchAccents(widget.selectedText);
    if (results.isNotEmpty) return results;

    if (widget.surfaceForm != null &&
        widget.surfaceForm != widget.selectedText) {
      return queryService.searchPitchAccents(widget.surfaceForm!);
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showAtTop) {
      return _buildTopSheet(context);
    }
    return _buildBottomSheet(context);
  }

  Widget _buildBottomSheet(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            _buildDragHandle(context),
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(child: _buildResultsList(context, scrollController)),
          ],
        );
      },
    );
  }

  Widget _buildTopSheet(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.5;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Flexible(child: _buildResultsList(context, null)),
            _buildDragHandle(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        widget.selectedText,
        style: Theme.of(context).textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    ScrollController? scrollController,
  ) {
    final fontSize = ref.watch(lookupFontSizeProvider);

    return FutureBuilder<List<DictionaryEntryWithSource>>(
      future: _searchResultsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return const Center(child: Text('No definitions found.'));
        }

        return FutureBuilder<List<PitchAccentResult>>(
          future: _pitchAccentsFuture,
          builder: (context, pitchSnapshot) {
            final allPitchAccents = pitchSnapshot.data ?? [];

            return ListView.separated(
              controller: scrollController,
              shrinkWrap: widget.showAtTop,
              itemCount: results.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = results[index];
                // Filter pitch accents matching this entry's reading
                final entryPitchAccents = _filterPitchAccents(
                  allPitchAccents,
                  result.entry,
                );
                return _DictionaryEntryItem(
                  entry: result.entry,
                  dictionaryName: result.dictionaryName,
                  sentenceContext: widget.sentenceContext,
                  pitchAccents: entryPitchAccents,
                  fontSize: fontSize,
                  frequencyRank: result.frequencyRank,
                );
              },
            );
          },
        );
      },
    );
  }

  /// Filter pitch accents to match this entry's reading or expression.
  List<PitchAccentResult> _filterPitchAccents(
    List<PitchAccentResult> allPitchAccents,
    DictionaryEntry entry,
  ) {
    if (allPitchAccents.isEmpty) return [];

    return allPitchAccents.where((p) {
      // Match if pitch reading matches entry reading
      if (entry.reading.isNotEmpty && p.reading == entry.reading) return true;
      // Match if pitch reading matches expression (for kana-only words)
      if (p.reading == entry.expression) return true;
      // Match if pitch has no reading (legacy data)
      if (p.reading.isEmpty) return true;
      return false;
    }).toList();
  }
}

class _DictionaryEntryItem extends ConsumerStatefulWidget {
  const _DictionaryEntryItem({
    required this.entry,
    required this.dictionaryName,
    this.sentenceContext,
    this.pitchAccents = const [],
    this.fontSize = 16.0,
    this.frequencyRank,
  });

  final DictionaryEntry entry;
  final String dictionaryName;
  final String? sentenceContext;
  final List<PitchAccentResult> pitchAccents;
  final double fontSize;
  final int? frequencyRank;

  @override
  ConsumerState<_DictionaryEntryItem> createState() =>
      _DictionaryEntryItemState();
}

class _DictionaryEntryItemState extends ConsumerState<_DictionaryEntryItem> {
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
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
    final repo = ref.read(vocabularyRepositoryProvider);
    if (_isSaved) {
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          // Row 1: Furigana + expression, dictionary badge, bookmark button
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FuriganaText(
                      expression: widget.entry.expression,
                      reading: widget.entry.reading,
                      expressionStyle: expressionStyle,
                      furiganaStyle: furiganaStyle,
                    ),
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
                          if (widget.frequencyRank != null)
                            _buildFrequencyTag(fs),
                        ],
                      ),
                    ),
                  ],
                ),
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
                  Expanded(child: Text(def, style: definitionStyle)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyTag(double fontSize) {
    final rank = widget.frequencyRank!;
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

  Widget _buildPitchAccents(ThemeData theme, double fontSize) {
    // Group by dictionary name for display
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
              // Pitch diagrams
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
              // Source tag
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
