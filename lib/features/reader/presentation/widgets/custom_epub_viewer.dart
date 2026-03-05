import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/models/epub_models.dart';
import 'custom_epub_controller.dart';

/// Builds the set of gesture recognizers that allow the iOS UiKitView
/// (and Android AndroidView) to receive all touch event types.
///
/// On iOS, `EagerGestureRecognizer` conflicts with the platform view's
/// `FlutterTouchInterceptingView` forwarding mechanism, causing touch events
/// to never reach WKWebView content. Instead, we register one recognizer per
/// gesture type so the platform view can claim taps, drags, and long-presses
/// through the normal gesture arena.
///
/// The 30 ms long-press duration ensures that near-instant touches (which are
/// common in epub reading) still get forwarded to the native web view.
Set<Factory<OneSequenceGestureRecognizer>> buildEpubGestureRecognizers() {
  return {
    Factory<VerticalDragGestureRecognizer>(
      () => VerticalDragGestureRecognizer(),
    ),
    Factory<HorizontalDragGestureRecognizer>(
      () => HorizontalDragGestureRecognizer(),
    ),
    Factory<LongPressGestureRecognizer>(
      () => LongPressGestureRecognizer(
        duration: const Duration(milliseconds: 30),
      ),
    ),
    Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
  };
}

/// Selection data reported by the JS bridge.
class EpubSelectionData {
  final String cfi;
  final String text;
  final Rect? rect;

  const EpubSelectionData({required this.cfi, required this.text, this.rect});
}

/// Custom EPUB viewer backed by InAppWebView + epub.js.
///
/// All page navigation is driven exclusively by Dart (via
/// [CustomEpubController.next] / [CustomEpubController.prev]).
/// The JS layer does NOT perform swipe-based page turns, which avoids
/// the double-navigation and RTL bugs present in flutter_epub_viewer.
class CustomEpubViewer extends StatefulWidget {
  const CustomEpubViewer({
    super.key,
    required this.controller,
    required this.epubData,
    this.initialCfi,
    this.direction = 'ltr',
    this.fontSize = 16,
    this.foregroundColor,
    this.backgroundColor,
    this.customCss,
    this.horizontalMargin = 28,
    this.verticalMargin = 28,
    this.forceHorizontalAxis = false,
    this.onLoaded,
    this.onChaptersLoaded,
    this.onRelocated,
    this.onSelection,
    this.onSelectionCleared,
    this.onLocationsReady,
    this.onTouchDown,
    this.onTouchUp,
    this.onWordTapped,
    this.onSentenceSelected,
    this.onLoadError,
  });

  final CustomEpubController controller;
  final Uint8List epubData;
  final String? initialCfi;
  final String direction;
  final int fontSize;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final Map<String, dynamic>? customCss;
  final int horizontalMargin;
  final int verticalMargin;
  final bool forceHorizontalAxis;

  final VoidCallback? onLoaded;
  final ValueChanged<List<EpubChapter>>? onChaptersLoaded;
  final ValueChanged<EpubLocation>? onRelocated;
  final ValueChanged<EpubSelectionData>? onSelection;
  final VoidCallback? onSelectionCleared;
  final VoidCallback? onLocationsReady;
  final void Function(double x, double y)? onTouchDown;
  final void Function(double x, double y)? onTouchUp;
  final void Function(
    String surroundingText,
    int charOffset,
    int blockCharOffset,
    String tappedChar,
    double x,
    double y,
  )?
  onWordTapped;
  final ValueChanged<EpubSelectionData>? onSentenceSelected;
  final void Function(String description)? onLoadError;

  @override
  State<CustomEpubViewer> createState() => _CustomEpubViewerState();
}

class _CustomEpubViewerState extends State<CustomEpubViewer> {
  InAppWebViewController? _webViewController;

  final _settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    javaScriptEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    transparentBackground: true,
    supportZoom: false,
    allowsInlineMediaPlayback: true,
    disableLongPressContextMenuOnLinks: false,
    iframeAllowFullscreen: true,
    allowsLinkPreview: false,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableVerticalScroll: true,
  );

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialFile: 'assets/epub_viewer/reader.html',
      initialSettings: _settings,
      preventGestureDelay: true,
      gestureRecognizers: buildEpubGestureRecognizers(),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        widget.controller.attach(controller);
        _registerHandlers(controller);
      },
      onConsoleMessage: (controller, msg) {
        if (kDebugMode) debugPrint('EPUB_JS: ${msg.message}');
      },
      onPermissionRequest: (controller, request) async {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },
      onReceivedError: (controller, request, error) {
        debugPrint(
          'EPUB_WEBVIEW error: ${error.type} ${error.description} '
          'url=${request.url}',
        );
        widget.onLoadError?.call(error.description);
      },
      onReceivedHttpError: (controller, request, response) {
        if (response.statusCode != null && response.statusCode! >= 400) {
          debugPrint(
            'EPUB_WEBVIEW HTTP error: ${response.statusCode} '
            'url=${request.url}',
          );
          widget.onLoadError?.call('HTTP ${response.statusCode}');
        }
      },
      shouldOverrideUrlLoading: (controller, action) async {
        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  void _registerHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'readyToLoad',
      callback: (_) => _loadBook(),
    );

    controller.addJavaScriptHandler(
      handlerName: 'loaded',
      callback: (_) => widget.onLoaded?.call(),
    );

    controller.addJavaScriptHandler(
      handlerName: 'chapters',
      callback: (data) {
        debugPrint('[EPUB_DART] chapters handler received ${data.length} args');
        if (data.isNotEmpty && data[0] is List) {
          final chapters = parseChapterList(data[0]);
          debugPrint(
            '[EPUB_DART] parsed ${chapters.length} chapters from direct data',
          );
          widget.onChaptersLoaded?.call(chapters);
        } else {
          // Fallback: try evaluateJavascript if direct data was empty.
          debugPrint(
            '[EPUB_DART] chapters data empty, trying evaluateJavascript fallback',
          );
          widget.controller
              .getChapters()
              .then((chapters) {
                debugPrint(
                  '[EPUB_DART] fallback got ${chapters.length} chapters',
                );
                widget.onChaptersLoaded?.call(chapters);
              })
              .catchError((e) {
                debugPrint('[EPUB_DART] chapters fallback error: $e');
                widget.onChaptersLoaded?.call([]);
              });
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'relocated',
      callback: (data) {
        if (data.isEmpty) return;
        final map = Map<String, dynamic>.from(data[0] as Map);
        widget.onRelocated?.call(EpubLocation.fromJson(map));
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'locationsReady',
      callback: (_) {
        widget.onLocationsReady?.call();
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'selection',
      callback: (data) {
        if (data.isEmpty) return;
        final map = Map<String, dynamic>.from(data[0] as Map);
        Rect? rect;
        if (map['rect'] != null) {
          final r = Map<String, dynamic>.from(map['rect'] as Map);
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final size = renderBox.size;
            rect = Rect.fromLTWH(
              (r['left'] as num).toDouble() * size.width,
              (r['top'] as num).toDouble() * size.height,
              (r['width'] as num).toDouble() * size.width,
              (r['height'] as num).toDouble() * size.height,
            );
          }
        }
        widget.onSelection?.call(
          EpubSelectionData(
            cfi: map['cfi'] as String? ?? '',
            text: map['text'] as String? ?? '',
            rect: rect,
          ),
        );
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'selectionCleared',
      callback: (_) => widget.onSelectionCleared?.call(),
    );

    controller.addJavaScriptHandler(
      handlerName: 'hapticFeedback',
      callback: (_) => HapticFeedback.heavyImpact(),
    );

    controller.addJavaScriptHandler(
      handlerName: 'currentLocation',
      callback: (data) {
        if (data.isEmpty) return;
        final map = Map<String, dynamic>.from(data[0] as Map);
        widget.controller.completeCurrentLocation(map);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'searchResults',
      callback: (data) {
        final results = data.isNotEmpty && data[0] is List
            ? data[0] as List<dynamic>
            : <dynamic>[];
        widget.controller.completeSearch(results);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'pageText',
      callback: (data) {
        if (data.isEmpty) return;
        final map = Map<String, dynamic>.from(data[0] as Map);
        widget.controller.completePageText(map['text'] as String? ?? '');
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'touchDown',
      callback: (data) {
        if (data.length >= 2) {
          final x = (data[0] as num).toDouble();
          final y = (data[1] as num).toDouble();
          debugPrint(
            '[EPUB_DART] touchDown x=${x.toStringAsFixed(3)} '
            'y=${y.toStringAsFixed(3)}',
          );
          widget.onTouchDown?.call(x, y);
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'touchUp',
      callback: (data) {
        if (data.length >= 2) {
          final x = (data[0] as num).toDouble();
          final y = (data[1] as num).toDouble();
          debugPrint(
            '[EPUB_DART] touchUp x=${x.toStringAsFixed(3)} '
            'y=${y.toStringAsFixed(3)}',
          );
          widget.onTouchUp?.call(x, y);
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'wordTapped',
      callback: (data) {
        if (data.isEmpty) return;
        final map = Map<String, dynamic>.from(data[0] as Map);
        final surroundingText = map['surroundingText'] as String? ?? '';
        final charOffset = (map['charOffset'] as num?)?.toInt() ?? 0;
        final blockCharOffset =
            (map['blockCharOffset'] as num?)?.toInt() ?? charOffset;
        final tappedChar = map['tappedChar'] as String? ?? '';
        final x = (map['x'] as num?)?.toDouble() ?? 0;
        final y = (map['y'] as num?)?.toDouble() ?? 0;
        debugPrint(
          '[EPUB_DART] wordTapped char="$tappedChar" '
          'offset=$charOffset blockOffset=$blockCharOffset '
          'textLen=${surroundingText.length}',
        );
        widget.onWordTapped?.call(
          surroundingText,
          charOffset,
          blockCharOffset,
          tappedChar,
          x,
          y,
        );
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'sentenceSelected',
      callback: (data) {
        if (data.isEmpty) return;
        final map = Map<String, dynamic>.from(data[0] as Map);
        Rect? rect;
        if (map['rect'] != null) {
          final r = Map<String, dynamic>.from(map['rect'] as Map);
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final size = renderBox.size;
            rect = Rect.fromLTWH(
              (r['left'] as num).toDouble() * size.width,
              (r['top'] as num).toDouble() * size.height,
              (r['width'] as num).toDouble() * size.width,
              (r['height'] as num).toDouble() * size.height,
            );
          }
        }
        debugPrint(
          '[EPUB_DART] sentenceSelected text="${(map['text'] as String? ?? '').substring(0, (map['text'] as String? ?? '').length.clamp(0, 40))}"',
        );
        widget.onSentenceSelected?.call(
          EpubSelectionData(
            cfi: map['cfi'] as String? ?? '',
            text: map['text'] as String? ?? '',
            rect: rect,
          ),
        );
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'displayError',
      callback: (_) {
        if (kDebugMode) debugPrint('EPUB display error');
      },
    );
  }

  void _loadBook() {
    final cfiParam = widget.initialCfi != null
        ? '"${widget.initialCfi!.replaceAll('"', '\\"')}"'
        : '""';
    final fgHex = widget.foregroundColor != null
        ? () {
            final fg = widget.foregroundColor!;
            final r = (fg.r * 255.0).round().clamp(0, 255);
            final g = (fg.g * 255.0).round().clamp(0, 255);
            final b = (fg.b * 255.0).round().clamp(0, 255);
            return '"#${r.toRadixString(16).padLeft(2, '0')}'
                '${g.toRadixString(16).padLeft(2, '0')}'
                '${b.toRadixString(16).padLeft(2, '0')}"';
          }()
        : '""';

    String cssParam;
    if (widget.customCss != null) {
      cssParam = _jsEncodeCss(widget.customCss!);
    } else {
      cssParam = 'null';
    }

    _webViewController?.evaluateJavascript(
      source:
          'loadBook('
          '[${widget.epubData.join(',')}], '
          '$cfiParam, '
          '"${widget.direction}", '
          '"paginated", '
          'false, '
          '"${widget.fontSize}", '
          '$fgHex, '
          '$cssParam, '
          '${widget.horizontalMargin}, '
          '${widget.verticalMargin}, '
          '${widget.forceHorizontalAxis}'
          ')',
    );

    // Set the outer HTML background to match the color mode immediately
    // on load to avoid a white flash when using sepia mode.
    if (widget.backgroundColor != null) {
      final bg = widget.backgroundColor!;
      final r = (bg.r * 255.0).round().clamp(0, 255);
      final g = (bg.g * 255.0).round().clamp(0, 255);
      final b = (bg.b * 255.0).round().clamp(0, 255);
      final bgHex =
          '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
      _webViewController?.evaluateJavascript(
        source: 'setBodyBackground("$bgHex")',
      );
    }
  }

  String _jsEncodeCss(Map<String, dynamic> css) {
    // Build a JS object literal from the CSS map.
    final buffer = StringBuffer('{');
    var first = true;
    for (final entry in css.entries) {
      if (!first) buffer.write(', ');
      first = false;
      buffer.write('"${entry.key}": ');
      if (entry.value is Map) {
        buffer.write(
          _jsEncodeCss(Map<String, dynamic>.from(entry.value as Map)),
        );
      } else {
        buffer.write('"${entry.value}"');
      }
    }
    buffer.write('}');
    return buffer.toString();
  }
}
