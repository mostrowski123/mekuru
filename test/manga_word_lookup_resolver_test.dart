import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/models/mokuro_models.dart';
import 'package:mekuru/features/manga/data/services/manga_word_lookup_resolver.dart';
import 'package:mekuru/features/reader/data/services/compound_word_resolver.dart';
import 'package:mekuru/features/reader/data/services/mecab_service.dart';

WordIdentification _buildIdentification({
  required List<TokenInfo> tokens,
  required int tappedIndex,
  String sentenceContext = 'どうしたの',
}) {
  final tapped = tokens[tappedIndex];
  return WordIdentification(
    result: WordLookupResult(
      surfaceForm: tapped.surface,
      dictionaryForm: tapped.dictionaryForm,
      reading: tapped.reading,
      sentenceContext: sentenceContext,
      tokenStartOffset: tapped.startInText,
    ),
    alignedTokens: tokens,
    tappedTokenIndex: tappedIndex,
  );
}

List<TokenInfo> _tokens(
  List<(String surface, String reading, String dictionaryForm)> defs,
) {
  final tokens = <TokenInfo>[];
  var offset = 0;
  for (final (surface, reading, dictionaryForm) in defs) {
    tokens.add(
      TokenInfo(
        surface: surface,
        dictionaryForm: dictionaryForm,
        reading: reading,
        pos: '名詞',
        startInText: offset,
      ),
    );
    offset += surface.length;
  }
  return tokens;
}

/// Vertical block whose line quads are 100px-wide columns side by side,
/// 100px per character, so expected highlight rects are easy to derive.
MokuroTextBlock _block(List<String> lines) {
  return MokuroTextBlock(
    box: const [0, 0, 100, 100],
    vertical: true,
    fontSize: 16,
    linesCoords: [
      for (var i = 0; i < lines.length; i++)
        [
          [100.0 * i, 0.0],
          [100.0 * i + 100, 0.0],
          [100.0 * i + 100, 100.0 * lines[i].length],
          [100.0 * i, 100.0 * lines[i].length],
        ],
    ],
    lines: lines,
  );
}

const _tappedWordBox = Rect.fromLTRB(1, 2, 3, 4);

MokuroWord _word({
  required String surface,
  String? dictionaryForm,
  String? reading,
  required int lineIndex,
  required int charStartInLine,
}) {
  return MokuroWord(
    surface: surface,
    dictionaryForm: dictionaryForm,
    reading: reading,
    boundingBox: _tappedWordBox,
    blockIndex: 0,
    lineIndex: lineIndex,
    charStartInLine: charStartInLine,
    charEndInLine: charStartInLine + surface.length,
  );
}

/// Resolver whose identification taps [tokenDefs] at [tappedIndex] and whose
/// compound resolution returns [compoundSurface] at [compoundStartOffset].
MangaWordLookupResolver _compoundResolver({
  required List<(String, String, String)> tokenDefs,
  required int tappedIndex,
  required String compoundSurface,
  required int compoundStartOffset,
  required String sentenceContext,
}) {
  return MangaWordLookupResolver(
    identifyWordWithContext: (text, charOffset) => _buildIdentification(
      tokens: _tokens(tokenDefs),
      tappedIndex: tappedIndex,
      sentenceContext: sentenceContext,
    ),
    resolveCompoundWord: (_) async => CompoundWordResult(
      surfaceForm: compoundSurface,
      dictionaryForm: compoundSurface,
      reading: 'ドウシタノ',
      sentenceContext: sentenceContext,
      tokenStartOffset: compoundStartOffset,
      tokenCount: 3,
    ),
  );
}

void main() {
  group('MangaWordLookupResolver', () {
    test(
      'uses full block text and longest compound match for lookup',
      () async {
        String? capturedText;
        int? capturedOffset;

        final resolver = MangaWordLookupResolver(
          identifyWordWithContext: (text, charOffset) {
            capturedText = text;
            capturedOffset = charOffset;
            return _buildIdentification(
              tokens: _tokens([
                ('どう', 'ドウ', 'どう'),
                ('した', 'シタ', 'する'),
                ('の', 'ノ', 'の'),
              ]),
              tappedIndex: 0,
            );
          },
          resolveCompoundWord: (_) async => const CompoundWordResult(
            surfaceForm: 'どうしたの',
            dictionaryForm: 'どうしたの',
            reading: 'ドウシタノ',
            sentenceContext: 'どうしたの',
            tokenStartOffset: 0,
            tokenCount: 3,
          ),
        );

        final lookup = await resolver.resolve(
          _word(
            surface: 'どう',
            dictionaryForm: 'どう',
            reading: 'ドウ',
            lineIndex: 0,
            charStartInLine: 0,
          ),
          _block(['どうしたの']),
        );

        expect(capturedText, 'どうしたの');
        expect(capturedOffset, 0);
        expect(lookup.result.surfaceForm, 'どうしたの');
        expect(lookup.result.dictionaryForm, 'どうしたの');
        expect(lookup.result.reading, 'ドウシタノ');
        expect(lookup.result.sentenceContext, 'どうしたの');
        // Span [0, 5) covers the whole single 5-char line.
        expect(lookup.highlightRects, [const Rect.fromLTRB(0, 0, 100, 500)]);
      },
    );

    test('calculates char offset across earlier lines in the block', () async {
      int? capturedOffset;

      final resolver = MangaWordLookupResolver(
        identifyWordWithContext: (text, charOffset) {
          expect(text, '先にどうしたの');
          capturedOffset = charOffset;
          return _buildIdentification(
            tokens: _tokens([
              ('先', 'サキ', '先'),
              ('に', 'ニ', 'に'),
              ('どう', 'ドウ', 'どう'),
              ('した', 'シタ', 'する'),
              ('の', 'ノ', 'の'),
            ]),
            tappedIndex: 2,
            sentenceContext: '先にどうしたの',
          );
        },
        resolveCompoundWord: (identification) async {
          expect(identification.tappedTokenIndex, 2);
          return const CompoundWordResult(
            surfaceForm: 'どうしたの',
            dictionaryForm: 'どうしたの',
            reading: 'ドウシタノ',
            sentenceContext: '先にどうしたの',
            tokenStartOffset: 2,
            tokenCount: 3,
          );
        },
      );

      final lookup = await resolver.resolve(
        _word(
          surface: 'どう',
          dictionaryForm: 'どう',
          reading: 'ドウ',
          lineIndex: 1,
          charStartInLine: 0,
        ),
        _block(['先に', 'どうしたの']),
      );

      expect(capturedOffset, 2);
      expect(lookup.result.dictionaryForm, 'どうしたの');
      expect(lookup.result.tokenStartOffset, 2);
      // Span [2, 7) is exactly line 1 (the second 100px column, 5 chars).
      expect(lookup.highlightRects, [const Rect.fromLTRB(100, 0, 200, 500)]);
    });

    test('reports a span that starts before the tapped word', () async {
      final resolver = _compoundResolver(
        tokenDefs: [
          ('先', 'サキ', '先'),
          ('に', 'ニ', 'に'),
          ('どう', 'ドウ', 'どう'),
          ('した', 'シタ', 'する'),
          ('の', 'ノ', 'の'),
        ],
        tappedIndex: 3,
        compoundSurface: 'どうしたの',
        compoundStartOffset: 2,
        sentenceContext: '先にどうしたの',
      );

      final lookup = await resolver.resolve(
        _word(
          surface: 'した',
          dictionaryForm: 'する',
          reading: 'シタ',
          lineIndex: 0,
          charStartInLine: 4,
        ),
        _block(['先にどうしたの']),
      );

      // Span [2, 7) of the 7-char line: the box starts two characters
      // before the tapped token.
      expect(lookup.highlightRects, hasLength(1));
      expect(
        lookup.highlightRects.single,
        rectMoreOrLessEquals(const Rect.fromLTRB(0, 200, 100, 700)),
      );
    });

    test('reports a span that crosses a line break', () async {
      final resolver = _compoundResolver(
        tokenDefs: [
          ('先', 'サキ', '先'),
          ('に', 'ニ', 'に'),
          ('どう', 'ドウ', 'どう'),
          ('した', 'シタ', 'する'),
          ('の', 'ノ', 'の'),
        ],
        tappedIndex: 3,
        compoundSurface: 'どうしたの',
        compoundStartOffset: 2,
        sentenceContext: '先にどうしたの',
      );

      final lookup = await resolver.resolve(
        _word(
          surface: 'した',
          dictionaryForm: 'する',
          reading: 'シタ',
          lineIndex: 1,
          charStartInLine: 0,
        ),
        _block(['先にどう', 'したの']),
      );

      // Span [2, 7): tail of line 0 plus all of line 1 — one rect per line.
      expect(lookup.highlightRects, hasLength(2));
      expect(
        lookup.highlightRects[0],
        rectMoreOrLessEquals(const Rect.fromLTRB(0, 200, 100, 400)),
      );
      expect(
        lookup.highlightRects[1],
        rectMoreOrLessEquals(const Rect.fromLTRB(100, 0, 200, 300)),
      );
    });

    test('drops the span when it does not match the block text', () async {
      // MeCab offsets are in sanitized coordinates: the zero-width space in
      // the block text shifts the real position of the compound by one.
      final resolver = _compoundResolver(
        tokenDefs: [('どう', 'ドウ', 'どう'), ('した', 'シタ', 'する'), ('の', 'ノ', 'の')],
        tappedIndex: 0,
        compoundSurface: 'どうしたの',
        compoundStartOffset: 0,
        sentenceContext: 'どうしたの',
      );

      final lookup = await resolver.resolve(
        _word(
          surface: 'どう',
          dictionaryForm: 'どう',
          reading: 'ドウ',
          lineIndex: 0,
          charStartInLine: 0,
        ),
        _block(['ど​うしたの']),
      );

      expect(lookup.result.surfaceForm, 'どうしたの');
      expect(lookup.highlightRects, [_tappedWordBox]);
    });

    test(
      'falls back to stored OCR word data when lookup cannot be rebuilt',
      () async {
        final resolver = MangaWordLookupResolver(
          identifyWordWithContext: (_, _) => null,
          resolveCompoundWord: (_) async {
            throw StateError('should not resolve compound when identify fails');
          },
        );

        final lookup = await resolver.resolve(
          _word(
            surface: 'どう',
            dictionaryForm: 'どう',
            reading: 'ドウ',
            lineIndex: 0,
            charStartInLine: 0,
          ),
          _block(['どうしたの']),
        );

        expect(lookup.result.surfaceForm, 'どう');
        expect(lookup.result.dictionaryForm, 'どう');
        expect(lookup.result.reading, 'ドウ');
        expect(lookup.result.sentenceContext, 'どうしたの');
        expect(lookup.result.tokenStartOffset, 0);
        expect(lookup.highlightRects, [_tappedWordBox]);
      },
    );
  });
}
