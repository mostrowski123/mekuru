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
    this.editable = false,
    this.transparent = false,
    this.onEditingStarted,
    this.onEditingEnded,
  });

  /// The dictionary/base form to look up (primary search term).
  final String selectedText;

  /// The surface form as it appears in the text (fallback search term).
  final String? surfaceForm;

  final String? sentenceContext;

  /// When true, render as a top-aligned card instead of a draggable bottom sheet.
  final bool showAtTop;

  /// When true, the word header can be tapped to edit and re-search.
  final bool editable;

  /// When true, use semi-transparent background with a visible border.
  final bool transparent;

  /// Called when the user starts editing the word header.
  final VoidCallback? onEditingStarted;

  /// Called when the user finishes editing the word header.
  final VoidCallback? onEditingEnded;

  @override
  ConsumerState<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends ConsumerState<LookupSheet> {
  late Future<List<DictionaryEntryWithSource>> _searchResultsFuture;
  late Future<List<PitchAccentResult>> _pitchAccentsFuture;

  bool _isEditing = false;
  late TextEditingController _editController;
  String? _editedText;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _searchResultsFuture = _search(widget.selectedText, widget.surfaceForm);
    _pitchAccentsFuture = _searchPitchAccents(
      widget.selectedText,
      widget.surfaceForm,
    );
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _navigateToWord(String word) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DictionarySearchScreen(initialQuery: word),
      ),
    );
  }

  /// Search by dictionary form, surface form, and all deinflected candidates.
  Future<List<DictionaryEntryWithSource>> _search(
    String primary, [
    String? secondary,
  ]) async {
    final queryService = ref.read(dictionaryQueryServiceProvider);
    return queryService.searchLookupWithSource(primary, secondary);
  }

  /// Search pitch accents for the given terms.
  Future<List<PitchAccentResult>> _searchPitchAccents(
    String primary, [
    String? secondary,
  ]) async {
    final queryService = ref.read(dictionaryQueryServiceProvider);
    final allTerms = <String>{primary};
    if (secondary != null) {
      allTerms.addAll(deinflect(secondary));
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

  void _onEditSubmitted(String value) {
    if (value.trim().isEmpty) {
      setState(() => _isEditing = false);
      widget.onEditingEnded?.call();
      return;
    }
    setState(() {
      _isEditing = false;
      _editedText = value.trim();
      _searchResultsFuture = _search(_editedText!);
      _pitchAccentsFuture = _searchPitchAccents(_editedText!);
    });
    widget.onEditingEnded?.call();
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
        Widget content = Column(
          children: [
            _buildDragHandle(context),
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(child: _buildResultsList(context, scrollController)),
          ],
        );

        // Wrap in styled container for transparent mode.
        if (widget.transparent) {
          content = Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withAlpha(210),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withAlpha(180),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: content,
          );
        }

        return content;
      },
    );
  }

  Widget _buildTopSheet(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.5;

    final bgColor = widget.transparent
        ? Theme.of(context).colorScheme.surface.withAlpha(210)
        : Theme.of(context).colorScheme.surface;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
          border: widget.transparent
              ? Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withAlpha(180),
                )
              : null,
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
    final displayText =
        _editedText ?? widget.surfaceForm ?? widget.selectedText;

    // Editing mode: show TextField
    if (widget.editable && _isEditing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: TextField(
          controller: _editController,
          autofocus: true,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
          ),
          onSubmitted: _onEditSubmitted,
        ),
      );
    }

    // Display mode: show tappable text (if editable)
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: widget.editable
            ? () {
                setState(() {
                  _isEditing = true;
                  _editController.text = displayText;
                  _editController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: displayText.length,
                  );
                });
                widget.onEditingStarted?.call();
              }
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                displayText,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            if (widget.editable) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
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
