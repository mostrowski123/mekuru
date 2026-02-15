import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mecab_for_flutter/mecab_for_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of identifying a word from tapped text via MeCab.
class WordLookupResult {
  /// The surface form as it appears in the text (e.g., "食べた").
  final String surfaceForm;

  /// The dictionary/base form of the word (e.g., "食べる").
  final String dictionaryForm;

  /// The katakana reading of the word.
  final String reading;

  /// The sentence surrounding the tapped word, for context when saving.
  final String sentenceContext;

  /// The offset of the token's first character within the text passed to
  /// [MecabService.identifyWord]. Used for word highlighting.
  final int tokenStartOffset;

  const WordLookupResult({
    required this.surfaceForm,
    required this.dictionaryForm,
    required this.reading,
    required this.sentenceContext,
    required this.tokenStartOffset,
  });
}

/// Lightweight token info extracted from MeCab, safe to expose publicly.
///
/// Used by [CompoundWordResolver] to combine consecutive tokens and check
/// for longer dictionary matches.
class TokenInfo {
  final String surface;
  final String dictionaryForm;
  final String reading;
  final String pos;
  final int startInText;

  const TokenInfo({
    required this.surface,
    required this.dictionaryForm,
    required this.reading,
    required this.pos,
    required this.startInText,
  });
}

/// Result of [MecabService.identifyWordWithContext]: the single-token result
/// plus the full aligned token list so a compound resolver can try longer
/// matches.
class WordIdentification {
  final WordLookupResult result;
  final List<TokenInfo> alignedTokens;
  final int tappedTokenIndex;

  const WordIdentification({
    required this.result,
    required this.alignedTokens,
    required this.tappedTokenIndex,
  });
}

/// POS sub-categories within 記号 that should be skipped (true punctuation).
/// Other 記号 sub-categories (like 一般) may contain valid content.
const _skipSymbolSubcats = {
  '空白', // whitespace
  '括弧開', // opening bracket
  '括弧閉', // closing bracket
};

/// Common invisible characters found in EPUB content that can confuse MeCab.
final _invisibleCharsPattern = RegExp(
  '[\u200B\u200C\u200D\uFEFF\u00AD\u2060\u200E\u200F\u202A-\u202E]',
);

/// Service wrapping MeCab for Japanese word boundary detection.
///
/// Call [init] once at app startup. Then use [identifyWord] to determine
/// which word a user tapped given the surrounding text and character offset.
class MecabService {
  MecabService._();
  static final MecabService instance = MecabService._();

  final Mecab _tagger = Mecab();
  bool _initialized = false;

  /// Initialize MeCab with IPAdic. Safe to call multiple times.
  ///
  /// The native MeCab C library requires an absolute filesystem path to the
  /// dictionary directory. Flutter assets live in the app bundle and cannot
  /// be accessed via the filesystem directly, so we copy them to the
  /// application-documents directory on first launch.
  Future<void> init() async {
    if (_initialized) return;
    final dictPath = await _getDictDir();
    debugPrint('[MeCab] Initializing with dict path: $dictPath');
    await _tagger.init(null, dictPath, true);
    _initialized = true;
    debugPrint('[MeCab] Initialized successfully');
  }

  /// List of files that make up an IPAdic MeCab dictionary.
  static const _mecabDictFiles = [
    'char.bin',
    'dicrc',
    'left-id.def',
    'matrix.bin',
    'pos-id.def',
    'rewrite.def',
    'right-id.def',
    'sys.dic',
    'unk.dic',
    'mecabrc',
  ];

  /// Copy IPAdic dictionary files from Flutter assets to a filesystem
  /// directory and return the absolute path to that directory.
  ///
  /// Files are only copied once — subsequent calls skip files that already
  /// exist on disk.
  Future<String> _getDictDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final ipaDicDir = Directory(p.join(docsDir.path, 'assets', 'ipadic'));

    if (!ipaDicDir.existsSync()) {
      ipaDicDir.createSync(recursive: true);
    }

    for (final fileName in _mecabDictFiles) {
      final destPath = p.join(ipaDicDir.path, fileName);
      if (FileSystemEntity.typeSync(destPath) ==
          FileSystemEntityType.notFound) {
        debugPrint('[MeCab] Copying asset: assets/ipadic/$fileName');
        final ByteData data = await rootBundle.load('assets/ipadic/$fileName');
        final buffer = data.buffer;
        final bytes =
            buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        File(destPath).writeAsBytesSync(bytes);
      }
    }

    return ipaDicDir.absolute.path;
  }

  /// Whether MeCab has been initialized.
  bool get isInitialized => _initialized;

  /// Identify the word at [charOffset] within [text] using MeCab tokenization.
  ///
  /// Returns `null` if the offset falls on punctuation, whitespace, or if
  /// MeCab cannot identify a meaningful word.
  WordLookupResult? identifyWord(String text, int charOffset) {
    return identifyWordWithContext(text, charOffset)?.result;
  }

  /// Identify the word at [charOffset] and return the single-token result
  /// together with the full list of aligned tokens.
  ///
  /// The caller can pass [WordIdentification] to a [CompoundWordResolver]
  /// to try longer dictionary matches by combining consecutive tokens.
  WordIdentification? identifyWordWithContext(String text, int charOffset) {
    if (!_initialized || text.isEmpty) return null;
    if (charOffset < 0 || charOffset >= text.length) return null;

    // Sanitize: remove invisible characters that EPUB content may contain.
    final sanitized = _sanitizeText(text, charOffset);
    final cleanText = sanitized.text;
    final cleanOffset = sanitized.offset;

    if (cleanText.isEmpty || cleanOffset < 0 || cleanOffset >= cleanText.length) {
      debugPrint('[MeCab] Text empty or offset invalid after sanitization');
      return null;
    }

    final tappedChar = cleanText[cleanOffset];

    debugPrint(
      '[MeCab] identifyWord: offset=$cleanOffset char="$tappedChar" '
      'textLen=${cleanText.length} '
      'text="${cleanText.length <= 80 ? cleanText : '${cleanText.substring(0, 80)}...'}"',
    );

    final allTokens = _tagger.parse(cleanText);
    if (allTokens.isEmpty) {
      debugPrint('[MeCab] parse() returned empty token list');
      return null;
    }

    // Filter out EOS/BOS marker tokens — their surface text ("EOS", "BOS")
    // does NOT correspond to characters in the input and would corrupt offset
    // calculations.
    final tokens = allTokens.where((t) {
      final s = t.surface;
      if (s == 'EOS' || s == 'BOS' || s.isEmpty) return false;
      if (t.features.isNotEmpty && t.features[0] == 'BOS/EOS') return false;
      return true;
    }).toList();

    // Diagnostic: log token surfaces and total length
    final totalSurface = tokens.fold<int>(0, (sum, t) => sum + t.surface.length);
    debugPrint(
      '[MeCab] ${tokens.length} content tokens (${allTokens.length} raw), '
      'total surface len=$totalSurface vs text len=${cleanText.length}',
    );

    // Align tokens to their actual positions in the original text.
    final aligned = _alignTokensToText(tokens, cleanText);

    if (aligned.length <= 20) {
      final surfaceList = aligned
          .map((a) => '"${a.token.surface}"@${a.startInText}')
          .join(', ');
      debugPrint('[MeCab] Aligned tokens: [$surfaceList]');
    }

    // Build the public TokenInfo list from aligned tokens.
    final tokenInfoList = <TokenInfo>[];
    for (final entry in aligned) {
      final t = entry.token;
      final features = t.features;
      tokenInfoList.add(TokenInfo(
        surface: t.surface,
        dictionaryForm: features.length > 6 && features[6] != '*'
            ? features[6]
            : t.surface,
        reading: features.length > 7 && features[7] != '*'
            ? features[7]
            : '',
        pos: features.isNotEmpty ? features[0] : '',
        startInText: entry.startInText,
      ));
    }

    // Find the aligned token whose range covers the tapped offset.
    for (var i = 0; i < aligned.length; i++) {
      final entry = aligned[i];
      final start = entry.startInText;
      if (start < 0) continue;
      final end = start + entry.token.surface.length;

      if (cleanOffset >= start && cleanOffset < end) {
        final result = _buildResult(entry.token, text, charOffset, start);
        if (result == null) {
          debugPrint(
            '[MeCab] Token at offset $cleanOffset is filtered '
            '(surface="${entry.token.surface}", '
            'POS=${entry.token.features.isNotEmpty ? entry.token.features[0] : "?"})',
          );
          return null;
        }
        return WordIdentification(
          result: result,
          alignedTokens: tokenInfoList,
          tappedTokenIndex: i,
        );
      }
    }

    // Fallback: alignment didn't cover the tapped offset.
    debugPrint(
      '[MeCab] Alignment missed offset $cleanOffset (char="$tappedChar"), '
      'trying fallback...',
    );

    final fallbackResult =
        _fallbackIdentify(tokens, text, charOffset, cleanOffset, tappedChar);
    if (fallbackResult == null) return null;

    // For fallback, find the index by matching tokenStartOffset
    var fallbackIndex = 0;
    for (var i = 0; i < tokenInfoList.length; i++) {
      if (tokenInfoList[i].startInText == fallbackResult.tokenStartOffset &&
          tokenInfoList[i].surface == fallbackResult.surfaceForm) {
        fallbackIndex = i;
        break;
      }
    }

    return WordIdentification(
      result: fallbackResult,
      alignedTokens: tokenInfoList,
      tappedTokenIndex: fallbackIndex,
    );
  }

  /// Sanitize text by removing invisible characters and adjusting offset.
  _SanitizedText _sanitizeText(String text, int charOffset) {
    if (!_invisibleCharsPattern.hasMatch(text)) {
      return _SanitizedText(text, charOffset);
    }

    final buf = StringBuffer();
    var newOffset = charOffset;
    var removedBefore = 0;

    for (var i = 0; i < text.length; i++) {
      if (_invisibleCharsPattern.hasMatch(text[i])) {
        if (i < charOffset) removedBefore++;
      } else {
        buf.write(text[i]);
      }
    }

    newOffset = charOffset - removedBefore;
    final cleanText = buf.toString();

    if (removedBefore > 0) {
      debugPrint(
        '[MeCab] Sanitized: removed $removedBefore invisible chars '
        '(offset $charOffset → $newOffset)',
      );
    }

    return _SanitizedText(cleanText, newOffset);
  }

  /// Align MeCab tokens to their actual positions within [text].
  ///
  /// MeCab's token surfaces may not concatenate exactly back to the input
  /// text (e.g. full-width space tokenised differently, character normalisation).
  /// This method greedily searches for each token surface in [text] starting
  /// from a forward-moving cursor so that earlier tokens map to earlier
  /// positions.
  List<_AlignedToken> _alignTokensToText(
    List<TokenNode> tokens,
    String text,
  ) {
    final result = <_AlignedToken>[];
    var cursor = 0;

    for (final token in tokens) {
      final surface = token.surface;
      if (surface.isEmpty) {
        result.add(_AlignedToken(token, -1));
        continue;
      }

      // Greedy forward search from cursor
      final idx = text.indexOf(surface, cursor);
      if (idx >= 0) {
        result.add(_AlignedToken(token, idx));
        cursor = idx + surface.length;
      } else {
        // Surface not found after cursor — record -1 (unaligned)
        result.add(_AlignedToken(token, -1));
      }
    }

    return result;
  }

  /// Fallback token identification when the offset walk fails.
  ///
  /// Searches all tokens for one whose surface contains the tapped character.
  WordLookupResult? _fallbackIdentify(
    List<TokenNode> tokens,
    String originalText,
    int originalOffset,
    int cleanOffset,
    String tappedChar,
  ) {
    // Strategy 1: find tokens whose surface contains the tapped character,
    // then pick the one whose position in the text is closest to cleanOffset.
    TokenNode? bestToken;
    int bestTokenStart = 0;
    int bestDistance = originalText.length;

    var runningOffset = 0;
    for (final token in tokens) {
      final surface = token.surface;
      if (surface.contains(tappedChar)) {
        final tokenCenter = runningOffset + (surface.length ~/ 2);
        final distance = (tokenCenter - cleanOffset).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          bestToken = token;
          bestTokenStart = runningOffset;
        }
      }
      runningOffset += surface.length;
    }

    if (bestToken != null) {
      debugPrint(
        '[MeCab] Fallback found token: surface="${bestToken.surface}" '
        'at offset $bestTokenStart (distance=$bestDistance)',
      );
      return _buildResult(bestToken, originalText, originalOffset, bestTokenStart);
    }

    // Strategy 2: find the token whose surface appears in the original text
    // at a position that covers the tapped character.
    for (final token in tokens) {
      final surface = token.surface;
      if (surface.isEmpty) continue;
      var searchFrom = 0;
      while (true) {
        final idx = originalText.indexOf(surface, searchFrom);
        if (idx == -1) break;
        if (originalOffset >= idx && originalOffset < idx + surface.length) {
          debugPrint(
            '[MeCab] Fallback2 found: surface="$surface" at text pos $idx',
          );
          return _buildResult(token, originalText, originalOffset, idx);
        }
        searchFrom = idx + 1;
      }
    }

    // Dump all token surfaces for debugging
    final allSurfaces = tokens.map((t) => '"${t.surface}"').join(', ');
    debugPrint(
      '[MeCab] All fallbacks failed for char="$tappedChar" offset=$cleanOffset. '
      'Tokens: [$allSurfaces]',
    );
    return null;
  }

  WordLookupResult? _buildResult(
    TokenNode token,
    String fullText,
    int charOffset,
    int tokenStartOffset,
  ) {
    final surface = token.surface;
    final features = token.features;

    // Skip tokens with no features
    if (features.isEmpty) return null;

    // Standard IPAdic feature format (9 fields):
    // 0:POS, 1:subcat1, 2:subcat2, 3:subcat3, 4:conjType, 5:conjForm,
    // 6:baseForm, 7:reading, 8:pronunciation
    final pos = features[0];

    // Skip BOS/EOS markers
    if (pos == 'BOS/EOS') return null;

    // For 記号 (symbol), only skip specific sub-categories that are true
    // punctuation. Allow 記号,一般 through since some kanji can be tagged
    // this way by IPAdic.
    if (pos == '記号') {
      final subcat1 = features.length > 1 ? features[1] : '';
      if (_skipSymbolSubcats.contains(subcat1)) return null;
    }

    // Dictionary form: prefer feature[6] if available, fall back to surface
    String dictionaryForm;
    if (features.length > 6 && features[6] != '*') {
      dictionaryForm = features[6];
    } else {
      dictionaryForm = surface;
    }

    // Reading: prefer feature[7] if available
    String reading = '';
    if (features.length > 7 && features[7] != '*') {
      reading = features[7];
    }

    final sentenceContext = extractSentenceContext(fullText, charOffset);

    return WordLookupResult(
      surfaceForm: surface,
      dictionaryForm: dictionaryForm,
      reading: reading,
      sentenceContext: sentenceContext,
      tokenStartOffset: tokenStartOffset,
    );
  }

  /// Extract the sentence containing [charOffset] from [text].
  ///
  /// Scans for Japanese sentence-ending punctuation (。！？) and newlines
  /// in both directions from the offset.
  static String extractSentenceContext(String text, int charOffset) {
    if (text.isEmpty) return '';

    final clampedOffset = charOffset.clamp(0, text.length - 1);

    // Sentence delimiters
    const delimiters = {'。', '！', '？', '!', '?', '\n'};

    // Scan backward for sentence start
    var start = 0;
    for (var i = clampedOffset - 1; i >= 0; i--) {
      if (delimiters.contains(text[i])) {
        start = i + 1;
        break;
      }
    }

    // Scan forward for sentence end
    var end = text.length;
    for (var i = clampedOffset; i < text.length; i++) {
      if (delimiters.contains(text[i])) {
        end = i + 1; // Include the delimiter
        break;
      }
    }

    return text.substring(start, end).trim();
  }
}

/// Helper class for sanitized text with adjusted offset.
class _SanitizedText {
  final String text;
  final int offset;
  const _SanitizedText(this.text, this.offset);
}

/// A MeCab token aligned to its position in the original text.
class _AlignedToken {
  final TokenNode token;

  /// Character index within the text where this token's surface starts,
  /// or -1 if the token could not be aligned.
  final int startInText;

  const _AlignedToken(this.token, this.startInText);
}
