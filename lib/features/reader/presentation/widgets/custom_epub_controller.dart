import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/models/epub_models.dart';
import 'bridge_transfer.dart';

/// Dart-side controller for the custom epub.js bridge.
///
/// Wraps [InAppWebViewController] and exposes typed methods for every
/// JS function in reader_bridge.js.
class CustomEpubController {
  InAppWebViewController? _webView;

  void attach(InAppWebViewController controller) {
    _webView = controller;
  }

  /// Evaluates raw JavaScript in the reader WebView and returns the result.
  /// Test-only escape hatch for integration tests that need to inspect
  /// epub.js internals (e.g. detected writing mode and pagination axis).
  @visibleForTesting
  Future<dynamic> debugEvaluateJavascript(String source) =>
      _evaluateJavascript(source);

  /// Test-only: crashes the WebView's renderer, standing in for Android
  /// killing it for memory. Android only: WKWebView has no such page.
  @visibleForTesting
  Future<void> debugCrashRenderer() async =>
      _webView?.loadUrl(urlRequest: URLRequest(url: WebUri('chrome://crash')));

  void detach([InAppWebViewController? controller]) {
    if (controller != null && !identical(_webView, controller)) {
      return;
    }
    _webView = null;
  }

  // ── Navigation ──────────────────────────────────────────────────────

  void next() => _eval('next()');
  void prev() => _eval('previous()');

  // The page turn animation's turn: its id, and what the bridge's answer
  // (`pageTurned`) completes.
  var _turnId = 0;
  Completer<bool>? _turnShown;

  /// [next] or [prev] for the page turn animation. The future completes
  /// with true once the page the turn went to is on screen, and with false
  /// when there was no page to turn to (the first or last page of the
  /// book). It never completes when a newer turn replaces this one.
  ///
  /// A [quiet] turn does not count its page as read: the page is only
  /// peeked at under a finger still dragging it ([countTurnedPage] counts
  /// it once the turn is finished), or is the way back from such a peek.
  Future<bool> turnPage({required bool forward, bool quiet = false}) {
    final shown = _turnShown = Completer<bool>();
    _eval(
      '${forward ? 'next' : 'previous'}(${++_turnId}${quiet ? ', true' : ''})',
    );
    return shown.future;
  }

  /// Counts the page a quiet [turnPage] went to as read after all.
  void countTurnedPage() => _eval('countTurnedPage()');

  /// The bridge's answer to [turnPage]. An older turn's answer can arrive
  /// after a newer turn has started: the id tells them apart.
  void completePageTurn(int id, {required bool turned}) {
    if (id != _turnId) return;
    _turnShown?.complete(turned);
    _turnShown = null;
  }

  /// A picture of the page on screen, for the page turn animation (Flutter
  /// cannot snapshot a platform view itself). Null without a web view.
  Future<ui.Image?> takePagePicture() async {
    final bytes = await _webView?.takeScreenshot(
      // PNG is the faster format on iOS, JPEG on Android.
      screenshotConfiguration: defaultTargetPlatform == TargetPlatform.iOS
          ? null
          : ScreenshotConfiguration(
              compressFormat: CompressFormat.JPEG,
              quality: 90,
            ),
    );
    return bytes == null ? null : decodeImageFromList(bytes);
  }

  void display({required String cfi}) {
    final escaped = cfi.replaceAll('"', '\\"');
    _eval('toCfi("$escaped")');
  }

  void toProgressPercentage(double progress) {
    assert(progress >= 0.0 && progress <= 1.0);
    _eval('toProgress($progress)');
  }

  // ── Chapters ────────────────────────────────────────────────────────

  Future<List<EpubChapter>> getChapters() async {
    final result = await _evaluateJavascript('getChapters()');
    return parseChapterList(result);
  }

  // ── Display settings ────────────────────────────────────────────────

  void setFontSize(double fontSize) {
    _eval('setFontSize("${fontSize.round()}")');
  }

  void updateTheme({Color? foregroundColor, Map<String, dynamic>? customCss}) {
    final fgHex = foregroundColor != null ? _colorToHex(foregroundColor) : '';
    final cssJson = customCss != null ? jsonEncode(customCss) : 'null';
    _eval('updateTheme("$fgHex", $cssJson)');
  }

  /// Sends [file] to the open book as CSS family [family] and registers it
  /// in the chapters on screen. False when the web view is gone or the
  /// file cannot be read.
  Future<bool> applyUserFont(File file, String family) async {
    Future<bool> run(String source) async {
      try {
        await _evaluateJavascript(source);
        return true;
      } on StateError {
        return false;
      }
    }

    try {
      if (!await sendUserFont(file, family, run)) return false;
    } on IOException {
      return false;
    }
    return run('applyUserFont()');
  }

  /// Drops the added font from the bridge (a built-in font was chosen).
  void clearUserFont() => _eval('clearUserFont()');

  void setMargins(int horizontal, int vertical) {
    _eval('setMargins($horizontal, $vertical)');
  }

  /// Two pages side by side wherever the page area is at least [minWidth]
  /// wide, or one page always (null), laid out again at the place on screen
  /// if that changes what shows. The page can still show one: a fixed-layout
  /// book, or vertical text in a web view that cannot page it sideways.
  void setTwoPage(double? minWidth) => _eval('setTwoPage($minWidth)');

  void setBodyBackground(Color color) {
    final hex = _colorToHex(color);
    _eval('setBodyBackground("$hex")');
  }

  void setDisableLinks(bool disabled) {
    _eval('setDisableLinks($disabled)');
  }

  void setFuriganaMode(String mode) {
    _eval('setFuriganaMode(${jsonEncode(mode)})');
  }

  // ── Search ──────────────────────────────────────────────────────────

  /// Starts `searchBook` in the bridge (see there), whose results come back
  /// through `CustomEpubViewer.onSearchProgress` tagged with [id].
  void searchBook(int id, String query) {
    _eval('searchBook($id, ${jsonEncode(query)})');
  }

  /// Jumps to a search hit's range [cfi] and marks it for a moment. [text]
  /// is the matched text, which picks the range's reading while generated
  /// furigana is on the page (as for [addHighlight]).
  void showSearchHit(String cfi, String text) {
    _eval('showSearchHit(${jsonEncode(cfi)}, ${jsonEncode(text)})');
  }

  // ── Annotations ─────────────────────────────────────────────────────

  /// [text] is the highlight's saved text. While generated furigana is on
  /// the page it picks between the two ways a CFI may have been saved (see
  /// `EpubCFI.textRange()` in epub.js).
  void addHighlight({
    required String cfi,
    Color color = Colors.yellow,
    double opacity = 0.3,
    String text = '',
  }) {
    final hex = _colorToHex(color);
    _eval('addHighlight("$cfi", "$hex", "$opacity", ${jsonEncode(text)})');
  }

  void removeHighlight(String cfi) => _eval('removeHighlight("$cfi")');

  /// Each of [cfis] as the reader writes a CFI now, or null where it is not
  /// in the displayed section (see `normalizeCfis` in reader_bridge.js).
  Future<List<String?>> normalizeCfis(List<String> cfis) async {
    final raw = await _evaluateJavascript('normalizeCfis(${jsonEncode(cfis)})');
    final list = raw is String ? jsonDecode(raw) : raw;
    return [for (final cfi in list as List) cfi as String?];
  }

  /// The title of the chapter [cfi], a position in the displayed section,
  /// falls under (see [pickChapterTitle]); '' when there is none or the web
  /// view cannot tell.
  Future<String> chapterTitleAt(String cfi) async {
    try {
      return chapterTitleFromPlacement(
        await _evaluateJavascript('tocPlacement(${jsonEncode(cfi)})'),
      );
    } catch (error) {
      debugPrint('[EPUB_DART] chapterTitleAt failed: $error');
      return '';
    }
  }

  void addUnderline(String cfi) => _eval('addUnderline("$cfi")');

  void removeUnderline(String cfi) => _eval('removeUnderline("$cfi")');

  // ── Word highlighting ───────────────────────────────────────────────

  /// Highlight a word in the EPUB at the given block character offset.
  void highlightWord(int blockCharStart, int wordLength) {
    _eval('highlightWordInBlock($blockCharStart, $wordLength)');
  }

  /// Clear the current word highlight.
  void clearWordHighlight() => _eval('clearWordHighlight()');

  // ── Selection ───────────────────────────────────────────────────────

  void clearSelection() => _eval('clearSelection()');

  /// Expand the current word selection to the full sentence.
  void expandToSentence() => _eval('expandToSentence()');

  // ── Helpers ─────────────────────────────────────────────────────────

  void _eval(String source) {
    unawaited(_safeEval(source));
  }

  Future<dynamic> _evaluateJavascript(String source) async {
    final webView = _webView;
    if (webView == null) {
      throw StateError('EPUB web view is not attached');
    }

    try {
      return await webView.evaluateJavascript(source: source);
    } on MissingPluginException catch (error) {
      debugPrint('[EPUB_DART] JS bridge unavailable: $error');
      if (identical(_webView, webView)) {
        _webView = null;
      }
      throw StateError('EPUB web view is no longer attached');
    }
  }

  Future<void> _safeEval(String source) async {
    try {
      await _evaluateJavascript(source);
    } catch (error) {
      debugPrint('[EPUB_DART] JS call ignored: $error');
    }
  }

  String _colorToHex(Color c) {
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
}
