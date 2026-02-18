import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/reader/data/services/deinflection.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/widgets/dictionary_entry_card.dart';

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

  void _navigateToWord(String word) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DictionarySearchScreen(initialQuery: word),
      ),
    );
  }

  /// Search by dictionary form first, then try deinflected alternatives
  /// from the surface form to handle cases where MeCab chose the wrong
  /// base form (e.g., 行って → 行う instead of 行く).
  Future<List<DictionaryEntryWithSource>> _searchWithFallback() async {
    final queryService = ref.read(dictionaryQueryServiceProvider);

    // 1. Primary search by MeCab's dictionary form.
    final primaryResults =
        await queryService.searchWithSource(widget.selectedText);

    // 2. Try deinflected alternatives from the surface form.
    final seenIds = <int>{};
    for (final r in primaryResults) {
      seenIds.add(r.entry.id);
    }

    var alternativeResults = <DictionaryEntryWithSource>[];
    if (widget.surfaceForm != null &&
        widget.surfaceForm != widget.selectedText) {
      final candidates = deinflect(widget.surfaceForm!);
      // Remove the dictionary form MeCab already gave us.
      candidates.remove(widget.selectedText);

      if (candidates.isNotEmpty) {
        final altResults =
            await queryService.searchMultipleWithSource(candidates);
        alternativeResults =
            altResults.where((r) => seenIds.add(r.entry.id)).toList();
      }

      // 3. Last resort: search by the raw surface form itself.
      if (primaryResults.isEmpty && alternativeResults.isEmpty) {
        return queryService.searchWithSource(widget.surfaceForm!);
      }
    }

    if (alternativeResults.isEmpty) return primaryResults;
    return [...primaryResults, ...alternativeResults];
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
                return DictionaryEntryCard(
                  entry: result.entry,
                  dictionaryName: result.dictionaryName,
                  sentenceContext: widget.sentenceContext,
                  pitchAccents: entryPitchAccents,
                  fontSize: fontSize,
                  frequencyRank: result.frequencyRank,
                  onWordTap: _navigateToWord,
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

    final filtered = allPitchAccents.where((p) {
      // Match if pitch reading matches entry reading
      if (entry.reading.isNotEmpty && p.reading == entry.reading) return true;
      // Match if pitch reading matches expression (for kana-only words)
      if (p.reading == entry.expression) return true;
      // Match if pitch has no reading (legacy data)
      if (p.reading.isEmpty) return true;
      return false;
    });

    // Deduplicate by (reading, downstepPosition) across dictionaries
    final seen = <(String, int)>{};
    return filtered.where((p) => seen.add((p.reading, p.downstepPosition))).toList();
  }
}
