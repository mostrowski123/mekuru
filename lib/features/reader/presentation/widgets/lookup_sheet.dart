import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'package:mekuru/features/reader/data/services/deinflection.dart';
import 'package:mekuru/features/reader/data/services/gemma_translation.dart';
import 'package:mekuru/features/reader/presentation/widgets/sentence_translation_view.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/widgets/starter_pack_card.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';
import 'package:mekuru/shared/utils/app_routes.dart';

class LookupSheet extends ConsumerStatefulWidget {
  const LookupSheet({
    super.key,
    required this.selectedText,
    this.surfaceForm,
    this.sentenceContext,
    this.saveSource = 'other',
    this.initialEditedText,
    this.showAtTop = false,
    this.editable = false,
    this.transparent = false,
    this.onTermSubmitted,
    this.onEditingStarted,
    this.onEditingEnded,
    this.onLookupResolved,
    this.onWordSaved,
  });

  /// The dictionary/base form to look up (primary search term).
  final String selectedText;

  /// The surface form as it appears in the text (fallback search term).
  final String? surfaceForm;

  /// The sentence around the tapped word, shown and translated on the
  /// Sentence tab.
  final String? sentenceContext;

  /// Surface this sheet was opened from, recorded on the word event when a
  /// word is saved (`'epub'`, `'manga'`, or `'other'`).
  final String saveSource;

  /// Optional persisted manual lookup text to restore when reopening the sheet.
  final String? initialEditedText;

  /// When true, render as a top-aligned card instead of a draggable bottom sheet.
  final bool showAtTop;

  /// When true, the word header can be tapped to edit and re-search, and
  /// the sentence on the Sentence tab can be corrected before translating.
  final bool editable;

  /// When true, use semi-transparent background with a visible border.
  final bool transparent;

  /// Called after the user submits a new lookup term.
  final ValueChanged<String>? onTermSubmitted;

  /// Called when the user starts editing the word header.
  final VoidCallback? onEditingStarted;

  /// Called when the user finishes editing the word header.
  final VoidCallback? onEditingEnded;

  /// Called once when the initial lookup completes, with whether any
  /// dictionary results were found.
  final ValueChanged<bool>? onLookupResolved;

  /// Called when a word is saved to vocabulary from this sheet.
  final VoidCallback? onWordSaved;

  @override
  ConsumerState<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends ConsumerState<LookupSheet>
    with SingleTickerProviderStateMixin {
  late Future<List<DictionaryEntryWithSource>> _searchResultsFuture;
  late Future<List<PitchAccentResult>> _pitchAccentsFuture;

  /// Dictionary (0) or Sentence (1). Every new word starts on Dictionary.
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  /// The Sentence tab is built on its first visit, then kept like the
  /// results, so switching back and forth redoes nothing.
  bool _sentenceTabVisited = false;

  /// The user's correction of [LookupSheet.sentenceContext].
  String? _editedSentence;

  String? get _sentence {
    final sentence = (_editedSentence ?? widget.sentenceContext)?.trim();
    return sentence == null || sentence.isEmpty ? null : sentence;
  }

  bool _isEditing = false;
  late TextEditingController _editController;
  String? _editedText;

  String? _normalizeEditedText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Looks up the user's edit if there is one, else the tapped text.
  void _refreshLookupFutures() {
    final primarySearchTerm = _editedText ?? widget.selectedText;
    _searchResultsFuture = _search(primarySearchTerm, widget.surfaceForm);
    _pitchAccentsFuture = _searchPitchAccents(
      primarySearchTerm,
      widget.surfaceForm,
    );
  }

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _editedText = _normalizeEditedText(widget.initialEditedText);
    _refreshLookupFutures();

    final onLookupResolved = widget.onLookupResolved;
    if (onLookupResolved != null) {
      unawaited(
        _searchResultsFuture.then<void>(
          (results) => onLookupResolved(results.isNotEmpty),
          onError: (Object _) => onLookupResolved(false),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant LookupSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.sentenceContext != widget.sentenceContext) {
      _editedSentence = null;
    }
    final lookupChanged =
        oldWidget.selectedText != widget.selectedText ||
        oldWidget.surfaceForm != widget.surfaceForm ||
        oldWidget.initialEditedText != widget.initialEditedText;
    if (!lookupChanged) return;

    _tabController.index = 0;
    _sentenceTabVisited = false;
    _isEditing = false;
    _editedText = _normalizeEditedText(widget.initialEditedText);
    _refreshLookupFutures();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _editController.dispose();
    super.dispose();
  }

  void _navigateToWord(String word) {
    Navigator.of(context).push(
      namedRoute(
        'dictionary_search',
        (_) => DictionarySearchScreen(initialQuery: word),
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

    // One round-trip for every candidate; deinflection can hand back a
    // dozen of them for a stacked polite-progressive ending.
    final byTerm = await queryService.searchPitchAccentsBatch(allTerms);
    final allResults = <PitchAccentResult>[];
    final seenKeys = <(String, int)>{};
    for (final term in allTerms) {
      for (final r in byTerm[term] ?? const <PitchAccentResult>[]) {
        if (seenKeys.add((r.reading, r.downstepPosition))) {
          allResults.add(r);
        }
      }
    }
    return allResults;
  }

  void _onEditSubmitted(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      setState(() => _isEditing = false);
      widget.onEditingEnded?.call();
      return;
    }
    setState(() {
      _isEditing = false;
      _editedText = trimmedValue;
      _refreshLookupFutures();
    });
    widget.onTermSubmitted?.call(trimmedValue);
    widget.onEditingEnded?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Look the word up again when the first dictionary lands, so installing
    // the starter pack from this sheet resolves the word in place.
    ref.listen(noDictionariesProvider, (wasEmpty, isEmpty) {
      if (wasEmpty == true && !isEmpty) setState(_refreshLookupFutures);
    });
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
            _buildTabsOrDivider(context),
            Expanded(child: _buildBody(context, scrollController)),
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
            _buildTabsOrDivider(context),
            Flexible(child: _buildBody(context, null)),
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

  bool get _showSentenceTab =>
      _sentence != null &&
      ref.watch(sentenceTranslationModeProvider) !=
          SentenceTranslationMode.off &&
      !ref.watch(lowRamModeProvider);

  Widget _buildTabsOrDivider(BuildContext context) {
    if (!_showSentenceTab) return const Divider(height: 1);
    final l10n = context.l10n;
    return TabBar.secondary(
      controller: _tabController,
      onTap: (index) => setState(() => _sentenceTabVisited |= index == 1),
      tabs: [
        Tab(text: l10n.lookupTabDictionary),
        Tab(text: l10n.lookupTabSentence),
      ],
    );
  }

  /// Both tabs stay built once visited, so switching keeps the results, the
  /// translation and an edit in progress. The bottom sheet's controller can
  /// drive only one scrollable: the tab on screen gets it.
  Widget _buildBody(BuildContext context, ScrollController? scrollController) {
    final sentence = _sentence;
    final onSentence = _showSentenceTab && _tabController.index == 1;
    return Stack(
      children: [
        Offstage(
          offstage: onSentence,
          child: _buildResultsList(
            context,
            onSentence ? null : scrollController,
            primary: onSentence ? false : null,
          ),
        ),
        if (sentence != null && _showSentenceTab && _sentenceTabVisited)
          Offstage(
            offstage: !onSentence,
            child: SentenceTranslationView(
              sentence: sentence,
              word: widget.surfaceForm ?? widget.selectedText,
              fontSize: ref.watch(lookupFontSizeProvider),
              hidden:
                  ref.watch(sentenceTranslationModeProvider) ==
                  SentenceTranslationMode.hidden,
              source: widget.saveSource,
              highQuality:
                  ref.watch(translationModelProvider) ==
                      TranslationModelChoice.high &&
                  GemmaTranslation.supported,
              onSentenceEdited: widget.editable
                  ? (value) => setState(() => _editedSentence = value)
                  : null,
              onEditingStarted: widget.onEditingStarted,
              onEditingEnded: widget.onEditingEnded,
              scrollController: onSentence ? scrollController : null,
              shrinkWrap: widget.showAtTop,
            ),
          ),
      ],
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    ScrollController? scrollController, {
    bool? primary,
  }) {
    final fontSize = ref.watch(lookupFontSizeProvider);
    final noDictionaries = ref.watch(noDictionariesProvider);

    return FutureBuilder<List<DictionaryEntryWithSource>>(
      future: _searchResultsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              context.l10n.commonErrorWithDetails(details: '${snapshot.error}'),
            ),
          );
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty && noDictionaries) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.dictionaryNoDictionariesTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const StarterPackCard(),
              ],
            ),
          );
        }
        if (results.isEmpty) {
          return Center(child: Text(context.l10n.dictionaryNoResultsFound));
        }

        // Group results by (expression, reading).
        final groups = _groupResults(results);

        // A pinned header covers the definitions scrolling under it, so it
        // is painted opaque in the colour of the sheet behind it.
        final theme = Theme.of(context);
        final sheetTheme = theme.bottomSheetTheme;
        final headerColor = widget.showAtTop || widget.transparent
            ? theme.colorScheme.surface
            : sheetTheme.modalBackgroundColor ??
                  sheetTheme.backgroundColor ??
                  theme.colorScheme.surfaceContainerLow;

        return FutureBuilder<List<PitchAccentResult>>(
          future: _pitchAccentsFuture,
          builder: (context, pitchSnapshot) {
            final allPitchAccents = pitchSnapshot.data ?? [];
            final groupPitchAccents = [
              for (final group in groups)
                _filterPitchAccents(allPitchAccents, group.first.entry),
            ];

            return CustomScrollView(
              controller: scrollController,
              primary: primary,
              shrinkWrap: widget.showAtTop,
              slivers: [
                for (var index = 0; index < groups.length; index++) ...[
                  SliverMainAxisGroup(
                    key: ValueKey((
                      groups[index].first.entry.expression,
                      groups[index].first.entry.reading,
                    )),
                    slivers: [
                      PinnedHeaderSliver(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: headerColor,
                            border: Border(
                              bottom: BorderSide(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: GroupedDictionaryEntryHeader(
                            entries: groups[index],
                            pitchAccents: groupPitchAccents[index],
                            fontSize: fontSize,
                            sentenceContext: _sentence,
                            saveSource: widget.saveSource,
                            onWordTap: _navigateToWord,
                            onWordSaved: widget.onWordSaved,
                          ),
                        ),
                      ),
                      GroupedDictionaryEntryBody(
                        entries: groups[index],
                        pitchAccents: groupPitchAccents[index],
                        fontSize: fontSize,
                        onWordTap: _navigateToWord,
                        sliver: true,
                      ),
                    ],
                  ),
                  if (index < groups.length - 1)
                    const SliverToBoxAdapter(child: Divider(height: 1)),
                ],
              ],
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
