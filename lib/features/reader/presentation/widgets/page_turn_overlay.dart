import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

/// Plays page turns over a reader: a picture of the page on screen covers
/// it, the reader jumps to the new page underneath as it always did, and
/// the picture slides or curls away.
class PageTurnController {
  _PageTurnOverlayState? _overlay;
  var _requests = 0;
  var _capturing = false;

  /// Turns one page, with [style]'s animation when it can.
  ///
  /// [capture] takes the picture of the page on screen. Once the picture
  /// covers the page, [turnPage] runs; the animation starts when
  /// [pageShown] completes (at once when null) and the picture is removed
  /// at its end. If [pageShown] has not completed after 700 ms the picture
  /// is removed without animating: nothing new came to show.
  ///
  /// [turnPage] runs exactly once per call, whatever happens. It runs with
  /// no animation when [style] is [PageTurnStyle.none], when no overlay is
  /// on screen, when [capture] fails or returns null, and when another turn
  /// is under way: that one ends at once, so turns never queue up.
  Future<void> run({
    required PageTurnStyle style,
    required bool leavesRight,
    required Future<ui.Image?> Function() capture,
    required VoidCallback turnPage,
    Future<void>? pageShown,
  }) async {
    final overlay = _overlay;
    final request = ++_requests;
    if (overlay == null ||
        style == PageTurnStyle.none ||
        _capturing ||
        overlay._turn != null) {
      overlay?._finish();
      turnPage();
      return;
    }
    _capturing = true;
    ui.Image? picture;
    try {
      picture = await capture();
    } catch (error) {
      debugPrint('[PageTurn] no picture of the page: $error');
    } finally {
      _capturing = false;
    }
    // A newer request, or the reader closing, came while the picture was
    // taken: this turn still owes its page.
    if (picture == null || request != _requests || _overlay != overlay) {
      picture?.dispose();
      turnPage();
      return;
    }
    await overlay._run(_Turn(picture, style, leavesRight, turnPage), pageShown);
  }
}

class _Turn {
  _Turn(this.picture, this.style, this.leavesRight, this._turnPage);

  final ui.Image picture;
  final PageTurnStyle style;
  final bool leavesRight;
  VoidCallback? _turnPage;
  final done = Completer<void>();

  /// Exactly once, however the turn ends.
  void turnPage() {
    final turn = _turnPage;
    _turnPage = null;
    turn?.call();
  }
}

class PageTurnOverlay extends StatefulWidget {
  const PageTurnOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  final PageTurnController controller;
  final Widget child;

  /// Loads the curl shader. Tests replace it to make loading fail.
  @visibleForTesting
  static Future<ui.FragmentProgram> Function() debugLoadCurl = () =>
      ui.FragmentProgram.fromAsset('shaders/page_curl.frag');

  @override
  State<PageTurnOverlay> createState() => _PageTurnOverlayState();
}

class _PageTurnOverlayState extends State<PageTurnOverlay>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this);
  ui.FragmentShader? _curl;
  _Turn? _turn;
  Timer? _pageShownTimeout;

  @override
  void initState() {
    super.initState();
    widget.controller._overlay = this;
    // Until it has loaded, and if it cannot, a curl plays as a slide.
    PageTurnOverlay.debugLoadCurl().then((program) {
      if (mounted) _curl = program.fragmentShader();
    }, onError: (_) {});
  }

  @override
  void didUpdateWidget(PageTurnOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.controller == widget.controller);
  }

  Future<void> _run(_Turn turn, Future<void>? pageShown) {
    _animation
      ..duration = Duration(
        milliseconds: turn.style == PageTurnStyle.curl ? 450 : 250,
      )
      ..value = 0;
    setState(() => _turn = turn);
    // The page may only change once the picture covers it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_turn != turn) return;
      turn.turnPage();
      if (pageShown == null) return _play(turn);
      _pageShownTimeout = Timer(const Duration(milliseconds: 700), _finish);
      pageShown.then((_) {
        if (_turn == turn) _play(turn);
      }, onError: (_) {});
    });
    return turn.done.future;
  }

  void _play(_Turn turn) {
    _pageShownTimeout?.cancel();
    // Completes only when the animation runs to its end.
    _animation.forward().then((_) {
      if (_turn == turn) _finish();
    });
  }

  /// [rebuild] is false only from [dispose], where the tree is going anyway.
  void _finish({bool rebuild = true}) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    _pageShownTimeout?.cancel();
    _animation.stop();
    turn.turnPage();
    if (rebuild) setState(() {});
    turn.picture.dispose();
    turn.done.complete();
  }

  @override
  void dispose() {
    _finish(rebuild: false);
    // A rebuilt overlay's new state attaches before this one is disposed.
    if (widget.controller._overlay == this) widget.controller._overlay = null;
    _animation.dispose();
    _curl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turn = _turn;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (turn != null)
          Positioned.fill(
            // Taps reach the reader: another turn ends this one.
            child: IgnorePointer(
              // Its own layer: each frame repaints the picture only.
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const Key('page-turn-picture'),
                  painter: _TurnPainter(
                    turn,
                    turn.style == PageTurnStyle.curl ? _curl : null,
                    _animation,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TurnPainter extends CustomPainter {
  _TurnPainter(this.turn, this.curl, this.progress) : super(repaint: progress);

  static const _shadowWidth = 24.0;

  final _Turn turn;

  /// Null paints a slide.
  final ui.FragmentShader? curl;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOut.transform(progress.value);
    final picture = turn.picture;
    final curl = this.curl;
    if (curl != null) {
      // Uniform order is the shader's: uSize, uProgress, uRtl.
      curl
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, t)
        ..setFloat(3, turn.leavesRight ? 1 : 0)
        ..setImageSampler(0, picture);
      canvas.drawRect(Offset.zero & size, Paint()..shader = curl);
      return;
    }
    final towards = turn.leavesRight ? 1.0 : -1.0;
    final page = Offset(towards * t * size.width, 0) & size;
    // The leaving page's shadow on the page it uncovers: a strip beside its
    // trailing edge, darkest at the edge.
    final edge = turn.leavesRight ? page.left : page.right;
    final shadow = Rect.fromLTRB(
      edge - (turn.leavesRight ? _shadowWidth : 0),
      0,
      edge + (turn.leavesRight ? 0 : _shadowWidth),
      size.height,
    );
    canvas.drawRect(
      shadow,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(edge, 0),
          Offset(edge - towards * _shadowWidth, 0),
          const [Color(0x4D000000), Color(0x00000000)],
        ),
    );
    canvas.drawImageRect(
      picture,
      Offset.zero & Size(picture.width.toDouble(), picture.height.toDouble()),
      page,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_TurnPainter old) => old.turn != turn || old.curl != curl;
}
