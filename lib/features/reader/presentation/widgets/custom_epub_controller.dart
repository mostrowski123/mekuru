import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/models/epub_models.dart';

/// Dart-side controller for the custom epub.js bridge.
///
/// Wraps [InAppWebViewController] and exposes typed methods for every
/// JS function in reader_bridge.js.
class CustomEpubController {
  InAppWebViewController? _webView;

  void attach(InAppWebViewController controller) {
    _webView = controller;
  }

  void detach([InAppWebViewController? controller]) {
    if (controller != null && !identical(_webView, controller)) {
      return;
    }
    _webView = null;
    _failPendingRequests(StateError('EPUB web view is no longer attached'));
  }

  // ── Navigation ──────────────────────────────────────────────────────

  void next() => _eval('next()');
  void prev() => _eval('previous()');

  void display({required String cfi}) {
    final escaped = cfi.replaceAll('"', '\\"');
    _eval('toCfi("$escaped")');
  }

  void toProgressPercentage(double progress) {
    assert(progress >= 0.0 && progress <= 1.0);
    _eval('toProgress($progress)');
  }

  // ── Current location ────────────────────────────────────────────────

  Completer<EpubLocation>? _locationCompleter;

  Future<EpubLocation> getCurrentLocation() {
    _locationCompleter = Completer<EpubLocation>();
    unawaited(_requestCurrentLocation());
    return _locationCompleter!.future;
  }

  void completeCurrentLocation(Map<String, dynamic> data) {
    if (_locationCompleter != null && !_locationCompleter!.isCompleted) {
      _locationCompleter!.complete(EpubLocation.fromJson(data));
    }
    _locationCompleter = null;
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

  void setMargins(int horizontal, int vertical) {
    _eval('setMargins($horizontal, $vertical)');
  }

  void setBodyBackground(Color color) {
    final hex = _colorToHex(color);
    _eval('setBodyBackground("$hex")');
  }

  void setDisableLinks(bool disabled) {
    _eval('setDisableLinks($disabled)');
  }

  // ── Search ──────────────────────────────────────────────────────────

  Completer<List<Map<String, dynamic>>>? _searchCompleter;

  Future<List<Map<String, dynamic>>> search(String query) {
    _searchCompleter = Completer<List<Map<String, dynamic>>>();
    final escaped = query.replaceAll('"', '\\"');
    unawaited(_requestSearch(escaped));
    return _searchCompleter!.future;
  }

  void completeSearch(List<dynamic> results) {
    if (_searchCompleter != null && !_searchCompleter!.isCompleted) {
      _searchCompleter!.complete(
        results.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
    }
    _searchCompleter = null;
  }

  // ── Annotations ─────────────────────────────────────────────────────

  void addHighlight({
    required String cfi,
    Color color = Colors.yellow,
    double opacity = 0.3,
  }) {
    final hex = _colorToHex(color);
    _eval('addHighlight("$cfi", "$hex", "$opacity")');
  }

  void removeHighlight(String cfi) => _eval('removeHighlight("$cfi")');

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

  // ── Text extraction ─────────────────────────────────────────────────

  Completer<String>? _pageTextCompleter;

  Future<String> getCurrentPageText() {
    _pageTextCompleter = Completer<String>();
    unawaited(_requestCurrentPageText());
    return _pageTextCompleter!.future;
  }

  void completePageText(String text) {
    if (_pageTextCompleter != null && !_pageTextCompleter!.isCompleted) {
      _pageTextCompleter!.complete(text);
    }
    _pageTextCompleter = null;
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  void _eval(String source) {
    unawaited(_safeEval(source));
  }

  Future<void> _requestCurrentLocation() async {
    try {
      await _evaluateJavascript('getCurrentLocation()');
    } catch (error, stackTrace) {
      final completer = _locationCompleter;
      _locationCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  Future<void> _requestSearch(String escapedQuery) async {
    try {
      await _evaluateJavascript('searchInBook("$escapedQuery")');
    } catch (error, stackTrace) {
      final completer = _searchCompleter;
      _searchCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  Future<void> _requestCurrentPageText() async {
    try {
      await _evaluateJavascript('getCurrentPageText()');
    } catch (error, stackTrace) {
      final completer = _pageTextCompleter;
      _pageTextCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  Future<dynamic> _evaluateJavascript(String source) async {
    final webView = _webView;
    if (webView == null) {
      throw StateError('EPUB web view is not attached');
    }

    try {
      return await webView.evaluateJavascript(source: source);
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('[EPUB_DART] JS bridge unavailable: $error');
      if (identical(_webView, webView)) {
        _webView = null;
      }
      _failPendingRequests(
        StateError('EPUB web view is no longer attached'),
        stackTrace,
      );
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

  void _failPendingRequests(Object error, [StackTrace? stackTrace]) {
    final locationCompleter = _locationCompleter;
    _locationCompleter = null;
    if (locationCompleter != null && !locationCompleter.isCompleted) {
      locationCompleter.completeError(error, stackTrace);
    }

    final searchCompleter = _searchCompleter;
    _searchCompleter = null;
    if (searchCompleter != null && !searchCompleter.isCompleted) {
      searchCompleter.completeError(error, stackTrace);
    }

    final pageTextCompleter = _pageTextCompleter;
    _pageTextCompleter = null;
    if (pageTextCompleter != null && !pageTextCompleter.isCompleted) {
      pageTextCompleter.completeError(error, stackTrace);
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
