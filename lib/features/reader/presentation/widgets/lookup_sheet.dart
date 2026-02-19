import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/reader/data/services/deinflection.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';

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

  /// Search by dictionary form, surface form, and all deinflected candidates.
  ///
  /// Collects every plausible base form upfront and searches once via
  /// [searchMultipleWithSource], which handles deduplication and
  /// frequency-aware grouping automatically.
  Future<List<DictionaryEntryWithSource>> _searchWithFallback() async {
    final queryService = ref.read(dictionaryQueryServiceProvider);

    // Collect ALL possible dictionary forms to search.
    final allTerms = <String>{widget.selectedText};
    allTerms.addAll(deinflect(widget.selectedText));

    if (widget.surfaceForm != null) {
      allTerms.add(widget.surfaceForm!);
      allTerms.addAll(deinflect(widget.surfaceForm!));
    }

    return queryService.searchMultipleWithSource(allTerms.toList());
  }

  /// Search pitch accents for the dictionary form and all deinflected
  /// alternative base forms from the surface form.
  Future<List<PitchAccentResult>> _searchPitchAccents() async {
    final queryService = ref.read(dictionaryQueryServiceProvider);

    // Collect all base-form terms to search pitch accents for.
    final allTerms = <String>{widget.selectedText};
    if (widget.surfaceForm != null) {
      allTerms.addAll(deinflect(widget.surfaceForm!));
    }

    final allResults = <PitchAccentResult>[];
    final seenKeys = <(String, int)>{};
    for (final term in allTerms) {
      for (final r in await queryService.searchPitchAccents(term)) {
        if (seenKeys.add((r.reading, r.downstepPosition))) {
          allResults.add(r);
        }
      }
    }
    return allResults;
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
    // Show the surface form (what the user tapped) when available,
    // falling back to the MeCab dictionary form.
    final displayText = widget.surfaceForm ?? widget.selectedText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        displayText,
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

        // Group results by (expression, reading).
        final groups = _groupResults(results);

        return FutureBuilder<List<PitchAccentResult>>(
          future: _pitchAccentsFuture,
          builder: (context, pitchSnapshot) {
            final allPitchAccents = pitchSnapshot.data ?? [];

            return ListView.separated(
              controller: scrollController,
              shrinkWrap: widget.showAtTop,
              itemCount: groups.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final group = groups[index];
                final groupPitchAccents = _filterPitchAccents(
                  allPitchAccents,
                  group.first.entry,
                );
                return GroupedDictionaryEntryCard(
                  entries: group,
                  sentenceContext: widget.sentenceContext,
                  pitchAccents: groupPitchAccents,
                  fontSize: fontSize,
                  onWordTap: _navigateToWord,
                );
              },
            );
          },
        );
      },
    );
  }

  /// Group a flat list of results by (expression, reading), preserving
  /// the within-group order (dictionary sort order from SQL).
  List<List<DictionaryEntryWithSource>> _groupResults(
    List<DictionaryEntryWithSource> results,
  ) {
    final groups = <(String, String), List<DictionaryEntryWithSource>>{};
    final groupOrder = <(String, String)>[];

    for (final r in results) {
      final key = (r.entry.expression, r.entry.reading);
      if (groups.containsKey(key)) {
        groups[key]!.add(r);
      } else {
        groups[key] = [r];
        groupOrder.add(key);
      }
    }

    return [for (final key in groupOrder) groups[key]!];
  }

  /// Filter pitch accents to match this entry's reading or expression.
  List<PitchAccentResult> _filterPitchAccents(
    List<PitchAccentResult> allPitchAccents,
    DictionaryEntry entry,
  ) {
    if (allPitchAccents.isEmpty) return [];

    final filtered = allPitchAccents.where((p) {
      if (entry.reading.isNotEmpty && p.reading == entry.reading) return true;
      if (p.reading == entry.expression) return true;
      if (p.reading.isEmpty) return true;
      return false;
    });

    final seen = <(String, int)>{};
    return filtered
        .where((p) => seen.add((p.reading, p.downstepPosition)))
        .toList();
  }
}
