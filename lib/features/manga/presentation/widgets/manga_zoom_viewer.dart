import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/presentation/reader_interaction_logic.dart';

/// Horizontal movement past a page's edge, in logical pixels, before a
/// one-finger drag becomes a page swipe.
const double _swipeSlop = 8;

/// Pinch-zoom for one item of a manga [PageView] whose own drag is off.
///
/// A PageView's drag recognizer races [InteractiveViewer]'s scale
/// recognizer, so a pinch with one finger moving sideways turned the page.
/// Here the InteractiveViewer gets every touch, and the horizontal movement
/// it cannot pan (the page is not zoomed, or is already at that edge) goes
/// to [pageController]: dragged with the finger when [animatePageTurns], or
/// an instant turn on release in e-reader mode.
class MangaZoomViewer extends StatefulWidget {
  /// This item's index in the [PageView].
  final int pageIndex;

  /// The surrounding PageView's controller; null for zoom only (scroll mode).
  final PageController? pageController;

  /// When false (e-reader mode) a swipe past a zoomed page's edge jumps on
  /// release; unzoomed swipes are left to the reader screen.
  final bool animatePageTurns;
  final ValueChanged<bool>? onZoomChanged;
  final Widget child;

  const MangaZoomViewer({
    super.key,
    required this.pageIndex,
    this.pageController,
    this.animatePageTurns = true,
    this.onZoomChanged,
    required this.child,
  });

  @override
  State<MangaZoomViewer> createState() => _MangaZoomViewerState();
}

class _MangaZoomViewerState extends State<MangaZoomViewer> {
  final _transform = TransformationController();
  bool _isZoomed = false;

  // Raw pointer count: once two fingers were down, the finger left after a
  // pinch must not turn the page.
  int _pointers = 0;
  bool _multiTouch = false;

  double _lastTranslationX = 0;
  double _overflowX = 0;
  double _dy = 0;
  bool _swiping = false;
  Drag? _drag;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    widget.pageController?.addListener(_onPageScrolled);
  }

  @override
  void didUpdateWidget(MangaZoomViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController?.removeListener(_onPageScrolled);
      widget.pageController?.addListener(_onPageScrolled);
    }
  }

  @override
  void dispose() {
    widget.pageController?.removeListener(_onPageScrolled);
    _drag?.cancel();
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05; // small tolerance to avoid float jitter
    if (zoomed != _isZoomed) {
      _isZoomed = zoomed;
      widget.onZoomChanged?.call(zoomed);
    }
  }

  /// Once the PageView rests on another page, this one goes back to fit.
  /// Waiting for rest keeps a page that is swiped away from snapping
  /// mid-swipe.
  void _onPageScrolled() {
    final controller = widget.pageController!;
    if (!_isZoomed || !controller.hasClients) return;
    final page = controller.page;
    if (page == null) return;
    final atRest = (page - page.round()).abs() < 0.001;
    if (atRest && page.round() != widget.pageIndex) {
      _transform.value = Matrix4.identity();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers += 1;
    if (_pointers > 1) _multiTouch = true;
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointers > 0) _pointers -= 1;
    if (_pointers == 0) _multiTouch = false;
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _lastTranslationX = _transform.value.getTranslation().x;
    _overflowX = 0;
    _dy = 0;
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final translationX = _transform.value.getTranslation().x;
    final panned = translationX - _lastTranslationX;
    _lastTranslationX = translationX;

    final controller = widget.pageController;
    if (controller == null ||
        _multiTouch ||
        details.pointerCount > 1 ||
        // E-reader mode turns unzoomed pages from the screen's own
        // pointer Listener.
        (!widget.animatePageTurns && !_isZoomed)) {
      return;
    }

    final dx = details.focalPointDelta.dx;
    if (_swiping) {
      _overflowX += dx;
      _updateDrag(dx, details.focalPoint);
      return;
    }

    _overflowX += dx - panned;
    _dy += details.focalPointDelta.dy;
    if (_overflowX.abs() <= _swipeSlop || _overflowX.abs() <= _dy.abs()) {
      return;
    }

    // The rest of the gesture belongs to the page: freeze the image.
    setState(() => _swiping = true);
    if (widget.animatePageTurns && controller.hasClients) {
      _drag = controller.position.drag(
        DragStartDetails(globalPosition: details.focalPoint),
        () => _drag = null,
      );
      _updateDrag(_overflowX, details.focalPoint);
    }
  }

  void _updateDrag(double dx, Offset focalPoint) {
    _drag?.update(
      DragUpdateDetails(
        globalPosition: focalPoint,
        delta: Offset(dx, 0),
        primaryDelta: dx,
      ),
    );
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (!_swiping) return;
    if (widget.animatePageTurns) {
      // A second finger landing ends the swipe: settle, don't fling.
      final velocity = _multiTouch ? 0.0 : details.velocity.pixelsPerSecond.dx;
      _drag?.end(
        DragEndDetails(
          velocity: Velocity(pixelsPerSecond: Offset(velocity, 0)),
          primaryVelocity: velocity,
        ),
      );
      _drag = null;
    } else if (!_multiTouch &&
        _overflowX.abs() > context.size!.width * kSwipeDistanceThreshold) {
      _jumpOnePage(widget.pageController!);
    }
    setState(() => _swiping = false);
  }

  void _jumpOnePage(PageController controller) {
    if (!controller.hasClients) return;
    final position = controller.position;
    // Dragging content left shows the next index, unless the axis is
    // reversed (RTL reading).
    final step =
        (_overflowX < 0) != axisDirectionIsReversed(position.axisDirection)
        ? 1
        : -1;
    final lastPage = (position.maxScrollExtent / position.viewportDimension)
        .round();
    final target = (widget.pageIndex + step).clamp(0, lastPage);
    if (target != widget.pageIndex) controller.jumpToPage(target);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1.0,
        maxScale: 5.0,
        // Off while a swipe owns the gesture, so the image stays put.
        panEnabled: !_swiping,
        onInteractionStart: _onInteractionStart,
        onInteractionUpdate: _onInteractionUpdate,
        onInteractionEnd: _onInteractionEnd,
        child: widget.child,
      ),
    );
  }
}
