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

MokuroTextBlock _block(List<String> lines) {
  return MokuroTextBlock(
    box: const [0, 0, 100, 100],
    vertical: true,
    fontSize: 16,
    linesCoords: const [],
    lines: lines,
  );
}

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
    boundingBox: Rect.zero,
    blockIndex: 0,
    lineIndex: lineIndex,
    charStartInLine: charStartInLine,
    charEndInLine: charStartInLine + surface.length,
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

        final result = await resolver.resolve(
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
        expect(result.surfaceForm, 'どうしたの');
        expect(result.dictionaryForm, 'どうしたの');
        expect(result.reading, 'ドウシタノ');
        expect(result.sentenceContext, 'どうしたの');
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

      final result = await resolver.resolve(
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
      expect(result.dictionaryForm, 'どうしたの');
      expect(result.tokenStartOffset, 2);
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

        final result = await resolver.resolve(
          _word(
            surface: 'どう',
            dictionaryForm: 'どう',
            reading: 'ドウ',
            lineIndex: 0,
            charStartInLine: 0,
          ),
          _block(['どうしたの']),
        );

        expect(result.surfaceForm, 'どう');
        expect(result.dictionaryForm, 'どう');
        expect(result.reading, 'ドウ');
        expect(result.sentenceContext, 'どうしたの');
        expect(result.tokenStartOffset, 0);
      },
    );
  });
}
