import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mecab_for_flutter/mecab_for_flutter.dart';
import 'package:mekuru/core/utils/atomic_file.dart';
import 'package:mekuru/features/settings/data/services/enhanced_furigana_dict_download_service.dart';
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

/// Maps MeCab feature columns to logical fields (dictionary form, reading).
///
/// IPADIC and UniDic place these fields at different column indexes and
/// encode loanwords differently, so callers pass the matching layout to
/// [MecabService.init].
class MecabFeatureLayout {
  final int _dictionaryFormIndex;
  final int _readingIndex;
  final bool _stripLoanwordGloss;
  final String label;

  const MecabFeatureLayout._({
    required int dictionaryFormIndex,
    required int readingIndex,
    required bool stripLoanwordGloss,
    required this.label,
  }) : _dictionaryFormIndex = dictionaryFormIndex,
       _readingIndex = readingIndex,
       _stripLoanwordGloss = stripLoanwordGloss;

  /// IPADIC: `features[6]` is the lemma (dictionary form) and `features[7]`
  /// is the surface reading in katakana.
  static const ipadic = MecabFeatureLayout._(
    dictionaryFormIndex: 6,
    readingIndex: 7,
    stripLoanwordGloss: false,
    label: 'IPADIC',
  );

  /// UniDic (unidic-lite 2.1.2): `features[7]` is the lemma and
  /// `features[17]` is the surface kana form without long-vowel `ー`
  /// marks. Loanword lemmas include an `-english_gloss` suffix that must
  /// be stripped to recover the dictionary key.
  static const unidicLite = MecabFeatureLayout._(
    dictionaryFormIndex: 7,
    readingIndex: 17,
    stripLoanwordGloss: true,
    label: 'UniDic',
  );

  /// Returns `null` when the column is missing, `*`, or strips to empty.
  String? dictionaryForm(List<String> features) {
    if (features.length <= _dictionaryFormIndex) return null;
    final raw = features[_dictionaryFormIndex];
    if (raw.isEmpty || raw == '*') return null;
    if (!_stripLoanwordGloss) return raw;
    final dashIdx = raw.indexOf('-');
    if (dashIdx < 0) return raw;
    final stripped = raw.substring(0, dashIdx);
    return stripped.isEmpty ? null : stripped;
  }

  /// Returns `''` when the column is missing or `*`.
  String reading(List<String> features) {
    if (features.length <= _readingIndex) return '';
    final raw = features[_readingIndex];
    return (raw.isEmpty || raw == '*') ? '' : raw;
  }
}

/// Service wrapping MeCab for Japanese word boundary detection.
///
/// Call [init] once at app startup. Then use [identifyWord] to determine
/// which word a user tapped given the surrounding text and character offset.
class MecabService {
  MecabService._();
  static final MecabService instance = MecabService._();

  Mecab? _tagger;
  bool _initialized = false;
  Future<void>? _initFuture;
  // Non-final: assigned on every (re-)initialization attempt, including
  // retries after a failed init.
  late MecabFeatureLayout _layout;

  /// The active feature-column layout, set by [init].
  MecabFeatureLayout get layout => _layout;

  /// Initialize MeCab. Safe to call multiple times, including concurrently:
  /// overlapping callers share the single in-flight initialization, and a
  /// failed attempt can be retried by calling again.
  ///
  /// Chooses between the bundled IPADIC + gikun user-dictionary (default)
  /// and the optional downloaded UniDic-lite (when the user has opted in
  /// and the files are present). On UniDic-lite initialization failure,
  /// falls back to IPADIC so the reader stays usable.
  Future<void> init() {
    return _initFuture ??= _doInit().onError((Object error, StackTrace st) {
      _initFuture = null; // allow a later retry
      Error.throwWithStackTrace(error, st);
    });
  }

  Future<void> _doInit() async {
    if (_initialized) return;

    if (await EnhancedFuriganaDictDownloadService.shouldUse()) {
      try {
        final dictPath =
            await EnhancedFuriganaDictDownloadService.getStorageDir();
        debugPrint(
          '[MeCab] Initializing (UniDic-lite) with dict path: $dictPath',
        );
        _tagger = await Mecab.create(dictDir: dictPath);
        _layout = MecabFeatureLayout.unidicLite;
        _initialized = true;
        return;
      } catch (e) {
        debugPrint(
          '[MeCab] UniDic-lite init failed, falling back to IPADIC: $e',
        );
      }
    }

    final dictPath = await _getDictDir();
    final userDictPath = await _getUserDictPath();
    _layout = MecabFeatureLayout.ipadic;
    debugPrint(
      '[MeCab] Initializing (IPADIC) with dict path: $dictPath, '
      'user dict: $userDictPath',
    );
    _tagger = await Mecab.create(
      dictDir: dictPath,
      options: '-u "$userDictPath"',
    );
    _initialized = true;
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
  /// Files are installed once and verified complete; subsequent calls are a
  /// cheap stat-only check (see [copyAssetsToDir]).
  Future<String> _getDictDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final ipaDicDir = Directory(p.join(docsDir.path, 'assets', 'ipadic'));
    await copyAssetsToDir(
      assetPrefix: 'assets/ipadic',
      fileNames: _mecabDictFiles,
      destDir: ipaDicDir,
    );
    return ipaDicDir.absolute.path;
  }

  /// Marker file written once an install has been verified complete. While
  /// present, startup only stat-checks the files instead of re-reading the
  /// bundled assets to verify their sizes.
  static const _installMarkerName = '.install_ok';

  /// Install bundled assets into [destDir], atomically and self-healing.
  ///
  /// When the [_installMarkerName] marker is missing (fresh install,
  /// interrupted install, or first launch after an update), every file is
  /// verified against the bundled asset's byte length and re-copied on
  /// mismatch — this heals truncated files left behind by a kill mid-copy.
  /// Writes go through [writeBytesAtomic] so an interrupted copy never
  /// leaves a truncated file at the destination path.
  @visibleForTesting
  static Future<void> copyAssetsToDir({
    required String assetPrefix,
    required List<String> fileNames,
    required Directory destDir,
    Future<ByteData> Function(String key)? loadAsset,
  }) async {
    final load = loadAsset ?? rootBundle.load;
    if (!destDir.existsSync()) {
      destDir.createSync(recursive: true);
    }

    final marker = File(p.join(destDir.path, _installMarkerName));
    if (marker.existsSync() &&
        fileNames.every((f) => File(p.join(destDir.path, f)).existsSync())) {
      return;
    }

    // Clear orphaned temp files from a previously interrupted install.
    for (final entity in destDir.listSync()) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        try {
          entity.deleteSync();
        } catch (_) {
          // Non-fatal; the atomic write below overwrites stale temp files.
        }
      }
    }

    for (final fileName in fileNames) {
      final destFile = File(p.join(destDir.path, fileName));
      final ByteData data = await load('$assetPrefix/$fileName');
      final upToDate =
          destFile.existsSync() && destFile.lengthSync() == data.lengthInBytes;
      if (!upToDate) {
        debugPrint('[MeCab] Installing asset: $assetPrefix/$fileName');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await writeBytesAtomic(destFile, bytes);
      }
      if (loadAsset == null) {
        // rootBundle caches loaded assets; sys.dic alone is ~47 MB.
        rootBundle.evict('$assetPrefix/$fileName');
      }
    }

    marker.writeAsStringSync('');
  }

  /// Copy the bundled user-dictionary (gikun / 熟字訓 overrides on top of
  /// IPADIC) to disk and return the absolute path to `user.dic`.
  Future<String> _getUserDictPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final userDictDir = Directory(p.join(docsDir.path, 'assets', 'user_dict'));
    await copyAssetsToDir(
      assetPrefix: 'assets/user_dict',
      fileNames: const ['user.dic'],
      destDir: userDictDir,
    );
    return p.join(userDictDir.absolute.path, 'user.dic');
  }

  /// Whether MeCab has been initialized.
  bool get isInitialized => _initialized;

  /// Tokenize [text] into a list of surface forms.
  ///
  /// Returns the surface text of each meaningful token (excludes BOS/EOS
  /// markers and whitespace symbols). Used for segmenting definition text
  /// into individual tappable words.
  ///
  /// Falls back to returning [text] as a single-element list if MeCab is
  /// not initialized or the text is empty.
  List<String> tokenize(String text) {
    if (!_initialized || text.isEmpty) return [text];

    final allTokens = _tagger!.parse(text);
    final surfaces = allTokens
        .where((t) {
          final s = t.surface;
          if (s.isEmpty || s == 'EOS' || s == 'BOS') return false;
          if (t.features.isNotEmpty && t.features[0] == 'BOS/EOS') return false;
          return true;
        })
        .map((t) => t.surface)
        .toList();

    return surfaces.isEmpty ? [text] : surfaces;
  }

  /// Tokenize [text] for furigana generation.
  ///
  /// Returns aligned tokens with `surface`, `reading` (katakana), and
  /// `startInText` set to the offset within the original input. Unlike
  /// [identifyWordWithContext], this does NOT sanitize the input, so the
  /// returned surfaces and offsets line up exactly with the characters in
  /// [text] — important for callers that need to splice the tokens back into
  /// the source string (e.g. inserting `<ruby>` tags into a DOM text node).
  List<TokenInfo> tokenizeForFurigana(String text) {
    if (!_initialized || text.isEmpty) return const <TokenInfo>[];

    final allTokens = _tagger!.parse(text);
    if (allTokens.isEmpty) return const <TokenInfo>[];

    final tokens = allTokens.where((t) {
      final s = t.surface;
      if (s.isEmpty || s == 'EOS' || s == 'BOS') return false;
      if (t.features.isNotEmpty && t.features[0] == 'BOS/EOS') return false;
      return true;
    }).toList();

    final aligned = _alignTokensToText(tokens, text);
    final result = <TokenInfo>[];
    for (final entry in aligned) {
      if (entry.startInText < 0) continue;
      result.add(_tokenInfoFromAligned(entry));
    }
    return result;
  }

  TokenInfo _tokenInfoFromAligned(_AlignedToken entry) {
    final t = entry.token;
    final features = t.features;
    return TokenInfo(
      surface: t.surface,
      dictionaryForm: _layout.dictionaryForm(features) ?? t.surface,
      reading: _layout.reading(features),
      pos: features.isNotEmpty ? features[0] : '',
      startInText: entry.startInText,
    );
  }

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

    if (cleanText.isEmpty ||
        cleanOffset < 0 ||
        cleanOffset >= cleanText.length) {
      debugPrint('[MeCab] Text empty or offset invalid after sanitization');
      return null;
    }

    final tappedChar = cleanText[cleanOffset];

    final allTokens = _tagger!.parse(cleanText);
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

    // Align tokens to their actual positions in the original text.
    final aligned = _alignTokensToText(tokens, cleanText);

    // Build the public TokenInfo list from aligned tokens.
    final tokenInfoList = aligned.map(_tokenInfoFromAligned).toList();

    // Find the aligned token whose range covers the tapped offset.
    for (var i = 0; i < aligned.length; i++) {
      final entry = aligned[i];
      final start = entry.startInText;
      if (start < 0) continue;
      final end = start + entry.token.surface.length;

      if (cleanOffset >= start && cleanOffset < end) {
        final result = _buildResult(entry.token, text, charOffset, start);
        if (result == null) return null;
        return WordIdentification(
          result: result,
          alignedTokens: tokenInfoList,
          tappedTokenIndex: i,
        );
      }
    }

    final fallbackResult = _fallbackIdentify(
      tokens,
      text,
      charOffset,
      cleanOffset,
      tappedChar,
    );
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

    return _SanitizedText(cleanText, newOffset);
  }

  /// Align MeCab tokens to their actual positions within [text].
  ///
  /// MeCab's token surfaces may not concatenate exactly back to the input
  /// text (e.g. full-width space tokenised differently, character normalisation).
  /// This method greedily searches for each token surface in [text] starting
  /// from a forward-moving cursor so that earlier tokens map to earlier
  /// positions.
  List<_AlignedToken> _alignTokensToText(List<TokenNode> tokens, String text) {
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
      return _buildResult(
        bestToken,
        originalText,
        originalOffset,
        bestTokenStart,
      );
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
          return _buildResult(token, originalText, originalOffset, idx);
        }
        searchFrom = idx + 1;
      }
    }

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

    if (features.isEmpty) return null;

    final pos = features[0];

    if (pos == 'BOS/EOS') return null;

    // For 記号 (symbol), only skip specific sub-categories that are true
    // punctuation. Allow 記号,一般 through since some kanji can be tagged
    // this way by IPAdic.
    if (pos == '記号') {
      final subcat1 = features.length > 1 ? features[1] : '';
      if (_skipSymbolSubcats.contains(subcat1)) return null;
    }

    final dictionaryForm = _layout.dictionaryForm(features) ?? surface;
    final reading = _layout.reading(features);
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
