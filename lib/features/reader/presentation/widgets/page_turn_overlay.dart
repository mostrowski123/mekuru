import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';

/// Plays page turns over a reader: a picture of the page on screen covers
/// it, the reader jumps to the new page underneath as it always did, and
/// the picture slides away, by itself ([run]) or under the finger ([drag]).
class PageTurnController {
  /// How long a turn waits for the picture of the page.
  static const _captureWait = Duration(milliseconds: 500);

  _PageTurnOverlayState? _overlay;
  var _requests = 0;
  var _capturing = false;

  /// Turns one page, with [style]'s animation when it can.
  ///
  /// [capture] takes the picture of the page on screen. Once the picture
  /// covers the page, [turnPage] runs; the animation starts when
  /// [pageShown] completes with true (at once when null) and the picture is
  /// removed at its end. The picture is removed without animating when
  /// [pageShown] completes with false (there was no page to turn to) or has
  /// not completed after 700 ms.
  ///
  /// [turnPage] runs exactly once per call, whatever happens. It runs with
  /// no animation when [style] is [PageTurnStyle.none], when no overlay is
  /// on screen, when [capture] fails, returns null or takes over half a
  /// second, and when another turn is under way: that one ends at once, so
  /// turns never queue up.
  Future<void> run({
    required PageTurnStyle style,
    required bool leavesRight,
    required Future<ui.Image?> Function() capture,
    required VoidCallback turnPage,
    Future<bool>? pageShown,
  }) async {
    final overlay = _overlayForNewTurn(style);
    final picture = overlay == null ? null : await _take(overlay, capture);
    if (overlay == null || picture == null) {
      turnPage();
      return;
    }
    await overlay._run(_Turn(picture, leavesRight, turnPage), pageShown);
  }

  /// Starts a turn that follows the finger: feed it [PageTurnDrag.update]
  /// and let it go with [PageTurnDrag.end].
  ///
  /// The picture covers the page and [turnPage] runs as in [run]; from then
  /// on the picture moves with the finger. Let go to finish and it plays to
  /// its end. Let go to give up and it goes back, then [turnBack] puts the
  /// old page back underneath: it returns a future when that takes time,
  /// completing as [pageShown] does.
  ///
  /// When the turn cannot be animated (see [run]) nothing moves, and
  /// [turnPage] runs when the finger lets go to finish, as a swipe.
  PageTurnDrag drag({
    required PageTurnStyle style,
    required bool leavesRight,
    required Future<ui.Image?> Function() capture,
    required VoidCallback turnPage,
    Future<bool>? pageShown,
    required Future<bool>? Function() turnBack,
  }) {
    final drag = PageTurnDrag._(leavesRight, turnPage, turnBack);
    final overlay = _overlayForNewTurn(style);
    if (overlay == null) return drag;
    drag._waitsForPicture = true;
    unawaited(() async {
      final picture = await _take(overlay, capture);
      drag._waitsForPicture = false;
      if (picture == null) {
        if (drag._finishes ?? false) turnPage();
      } else if (drag._finishes == false) {
        // Given up before there was anything to move.
        picture.dispose();
      } else {
        final turn = _Turn(picture, leavesRight, turnPage)..drag = drag;
        drag._follow = () => overlay._follow(turn);
        await overlay._run(turn, pageShown);
      }
    }());
    return drag;
  }

  /// Ends the turn on screen now: its picture goes, its page stays turned
  /// (or goes back, when the turn had been given up).
  void finish() => _overlay?._finish();

  /// How far the turn on screen has gone, from 0 to 1; null without one.
  @visibleForTesting
  double? get debugProgress =>
      _overlay?._turn == null ? null : _overlay!._animation.value;

  /// The overlay, when a new turn can be animated on it. When it cannot (no
  /// animation, no overlay on screen, another turn under way) that other
  /// turn ends at once.
  _PageTurnOverlayState? _overlayForNewTurn(PageTurnStyle style) {
    final overlay = _overlay;
    _requests++;
    if (overlay == null ||
        style == PageTurnStyle.none ||
        _capturing ||
        overlay._turn != null) {
      overlay?._finish();
      return null;
    }
    return overlay;
  }

  /// The picture of the page on screen. Null when there is none to use:
  /// [capture] failed or took too long, or a newer request, or the reader
  /// closing, came first.
  Future<ui.Image?> _take(
    _PageTurnOverlayState overlay,
    Future<ui.Image?> Function() capture,
  ) async {
    final request = _requests;
    _capturing = true;
    ui.Image? picture;
    try {
      picture = await _inTime(capture());
    } catch (error) {
      debugPrint('[PageTurn] no picture of the page: $error');
    } finally {
      _capturing = false;
    }
    if (picture != null && (request != _requests || _overlay != overlay)) {
      picture.dispose();
      return null;
    }
    return picture;
  }

  /// [pending]'s picture, or null once [_captureWait] has passed: a tap must
  /// not wait on a web view that does not answer. A picture that comes after
  /// that is thrown away. (Not `Future.timeout`: its `onTimeout` must return
  /// the future's own run-time type, and a `Future<Image>` cannot give null.)
  static Future<ui.Image?> _inTime(Future<ui.Image?> pending) {
    final result = Completer<ui.Image?>();
    final timer = Timer(_captureWait, () {
      if (!result.isCompleted) result.complete(null);
    });
    pending.then(
      (picture) {
        timer.cancel();
        result.isCompleted ? picture?.dispose() : result.complete(picture);
      },
      onError: (Object error, StackTrace stack) {
        timer.cancel();
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }
}

/// A turn under the finger, from [PageTurnController.drag].
class PageTurnDrag {
  PageTurnDrag._(this._leavesRight, this._turnPage, this._turnBack);

  final bool _leavesRight;
  final VoidCallback _turnPage;
  final Future<bool>? Function() _turnBack;
  var _waitsForPicture = false;

  /// Moves the picture; set once the picture covers the page.
  VoidCallback? _follow;

  var _fraction = 0.0;

  // Null while the finger is down.
  bool? _finishes;

  /// How far the finger has gone since it came down, as a fraction of the
  /// page's width: positive to the right. Only the way the page leaves
  /// moves it.
  void update(double across) {
    if (_finishes != null) return;
    _fraction = (_leavesRight ? across : -across).clamp(0.0, 1.0);
    _follow?.call();
  }

  /// The finger lifted: play the turn to its end, or put the page back.
  void end({required bool complete}) {
    if (_finishes != null) return;
    _finishes = complete;
    final follow = _follow;
    if (follow != null) {
      follow();
    } else if (complete && !_waitsForPicture) {
      // Never animated: the page turns now, as a swipe does.
      _turnPage();
    }
  }
}

class _Turn {
  _Turn(this.picture, this.leavesRight, this._turnPage);

  final ui.Image picture;
  final bool leavesRight;
  VoidCallback? _turnPage;
  final done = Completer<void>();

  /// Set for a turn under the finger.
  PageTurnDrag? drag;

  /// The new page is on screen underneath: the picture may move.
  var shown = false;

  /// A turn given up has asked for the old page back.
  var wentBack = false;

  bool get givenUp => drag?._finishes == false;

  /// Exactly once, however the turn ends.
  void turnPage() {
    final turn = _turnPage;
    _turnPage = null;
    turn?.call();
  }

  /// The old page back underneath a turn given up, once.
  Future<bool>? turnBack() {
    wentBack = true;
    return drag!._turnBack();
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

  @override
  State<PageTurnOverlay> createState() => _PageTurnOverlayState();
}

class _PageTurnOverlayState extends State<PageTurnOverlay>
    with SingleTickerProviderStateMixin {
  /// How long a turn waits for its page before giving the picture up.
  static const _pageWait = Duration(milliseconds: 700);

  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  _Turn? _turn;
  Timer? _pageTimeout;

  @override
  void initState() {
    super.initState();
    widget.controller._overlay = this;
  }

  @override
  void didUpdateWidget(PageTurnOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.controller == widget.controller);
  }

  Future<void> _run(_Turn turn, Future<bool>? pageShown) {
    _animation.value = 0;
    setState(() => _turn = turn);
    // The page may only change once the picture covers it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_turn != turn) return;
      turn.turnPage();
      if (pageShown == null) return _shown(turn);
      _pageTimeout = Timer(_pageWait, _finish);
      pageShown.then((came) {
        if (_turn != turn) return;
        came ? _shown(turn) : _finish();
      }, onError: (_) {});
    });
    return turn.done.future;
  }

  /// The new page is underneath: the picture may go.
  void _shown(_Turn turn) {
    _pageTimeout?.cancel();
    turn.shown = true;
    if (turn.drag != null) return _follow(turn);
    // Completes only when the animation runs to its end.
    _animation.forward().then((_) {
      if (_turn == turn) _finish();
    });
  }

  /// Puts a turn under the finger where the finger is or, once the finger
  /// has lifted, runs it on to its end or back to its start.
  void _follow(_Turn turn) {
    if (_turn != turn || !turn.shown) return;
    final finishes = turn.drag!._finishes;
    if (finishes == null) {
      _animation.value = turn.drag!._fraction;
      return;
    }
    final target = finishes ? 1.0 : 0.0;
    _animation
        .animateTo(
          target,
          duration: _animation.duration! * (target - _animation.value).abs(),
          curve: Curves.easeOut,
        )
        .then((_) {
          if (_turn != turn) return;
          finishes ? _finish() : _putBack(turn);
        });
  }

  /// A turn given up: the page it left goes back underneath, then the
  /// picture, which looks just like it, comes off.
  void _putBack(_Turn turn) {
    void done([Object? _]) {
      if (_turn == turn) _finish();
    }

    final back = turn.turnBack();
    if (back == null) {
      // One frame for the page to be drawn again.
      WidgetsBinding.instance
        ..addPostFrameCallback(done)
        ..ensureVisualUpdate();
      return;
    }
    _pageTimeout = Timer(_pageWait, done);
    back.then(done, onError: done);
  }

  /// [rebuild] is false only from [dispose], where the tree is going anyway.
  void _finish({bool rebuild = true}) {
    final turn = _turn;
    if (turn == null) return;
    _turn = null;
    _pageTimeout?.cancel();
    _animation.stop();
    if (!turn.givenUp) {
      turn.turnPage();
    } else if (turn.shown && !turn.wentBack) {
      // Cut short on its way back: the old page is still owed.
      turn.turnBack()?.ignore();
    }
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
            // Touches reach the reader: another turn ends this one.
            child: IgnorePointer(
              // Its own layer: each frame repaints the picture only.
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const Key('page-turn-picture'),
                  painter: _TurnPainter(turn, _animation),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TurnPainter extends CustomPainter {
  _TurnPainter(this.turn, this.progress) : super(repaint: progress);

  static const _shadowWidth = 24.0;

  final _Turn turn;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Under the finger the picture moves as the finger does; by itself it
    // eases in and out.
    final t = turn.drag == null
        ? Curves.easeInOut.transform(progress.value)
        : progress.value;
    final picture = turn.picture;
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
  bool shouldRepaint(_TurnPainter old) => old.turn != turn;
}
