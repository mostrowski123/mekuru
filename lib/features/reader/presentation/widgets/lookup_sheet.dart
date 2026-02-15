import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/dictionary/presentation/providers/dictionary_providers.dart';
import 'package:mekuru/features/vocabulary/presentation/providers/vocabulary_providers.dart';

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

  @override
  void initState() {
    super.initState();
    _searchResultsFuture = _searchWithFallback();
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

        return ListView.separated(
          controller: scrollController,
          shrinkWrap: widget.showAtTop,
          itemCount: results.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = results[index];
            return _DictionaryEntryItem(
              entry: result.entry,
              dictionaryName: result.dictionaryName,
              sentenceContext: widget.sentenceContext,
            );
          },
        );
      },
    );
  }
}

class _DictionaryEntryItem extends ConsumerStatefulWidget {
  const _DictionaryEntryItem({
    required this.entry,
    required this.dictionaryName,
    this.sentenceContext,
  });

  final DictionaryEntry entry;
  final String dictionaryName;
  final String? sentenceContext;

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

    List<String> definitions = [];
    try {
      final List<dynamic> jsonList = jsonDecode(widget.entry.glossaries);
      definitions = jsonList.map((e) => e.toString()).toList();
    } catch (_) {
      definitions = [widget.entry.glossaries];
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.entry.expression,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.entry.reading.isNotEmpty &&
                        widget.entry.reading != widget.entry.expression)
                      Text(
                        widget.entry.reading,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
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
          const SizedBox(height: 8),
          ...definitions.map(
            (def) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '- ',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                  Expanded(child: Text(def)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
