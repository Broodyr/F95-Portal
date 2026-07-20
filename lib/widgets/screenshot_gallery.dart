import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../constants.dart';
import 'remote_image.dart';
import 'sfw_blur.dart';

/// Fullscreen swipeable screenshot viewer with pinch-zoom.
class ScreenshotGallery extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  /// Fetches one image's bytes into the disk cache without decoding it
  /// (swappable so tests don't touch the real cache manager). Decoding all
  /// images up front is what used to freeze the UI for seconds; bytes-only
  /// prefetch keeps swipes fast while only the visible page ever decodes.
  static Future<void> Function(String url) downloadBytes = _downloadToCache;

  static Future<void> _downloadToCache(String url) async {
    await DefaultCacheManager().getSingleFile(url);
  }

  const ScreenshotGallery({super.key, required this.urls, this.initialIndex = 0});

  static void show(BuildContext context, List<String> urls, {int initialIndex = 0}) {
    // Transparent route: the screen behind keeps painting, so the backdrop
    // fade during a dismiss drag actually reveals it.
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => ScreenshotGallery(urls: urls, initialIndex: initialIndex),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ScreenshotGallery> createState() => _ScreenshotGalleryState();
}

class _ScreenshotGalleryState extends State<ScreenshotGallery> with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  final TransformationController _transformation = TransformationController();
  Offset _doubleTapPosition = Offset.zero;
  late int _index;
  int _pointerCount = 0;
  bool _zoomed = false;

  /// PageView's horizontal drag recognizer beats the two-finger scale
  /// recognizer in the gesture arena unless the fingers land perfectly
  /// vertically. Stop the PageView from competing the moment a second
  /// pointer is down, and keep it out of the way while zoomed in so a
  /// one-finger drag pans the image instead of changing pages.
  bool get _pageSwipingDisabled => _pointerCount >= 2 || _zoomed || _dismissDragging;

  /// Swipe-up/down-to-close. The PageView only claims predominantly
  /// horizontal drags and InteractiveViewer's pan is inert until zoomed,
  /// so vertical motion is tracked here on raw pointer events: once a
  /// single-finger drag is clearly vertical it drags the pager off-screen
  /// and a far-enough pull (or fling) pops the route. Never engages while
  /// zoomed — a vertical drag then pans the image.
  bool _dismissDragging = false;
  double _dragOffset = 0;
  double _dragDx = 0, _dragDy = 0;
  VelocityTracker? _velocityTracker;
  late final AnimationController _snapBack;
  static const double _dismissDistance = 120;
  static const double _dismissVelocity = 700;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _snapBack = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() => _dragOffset = _snapBack.value));
    _transformation.addListener(_onTransformationChanged);
    _prefetchBytes();
  }

  /// HD images are only fetched once the viewer opens; start downloading
  /// them all now (nearest to the opened image first) so swiping doesn't
  /// wait on the network. Bytes only — never decode ahead of display.
  /// A few workers drain a shared queue instead of firing every request
  /// at once: bursting the CDN is what got the first images rejected
  /// with an instant broken icon.
  static const int _prefetchConcurrency = 3;

  void _prefetchBytes() {
    final order = List.generate(widget.urls.length, (i) => i)
      ..sort((a, b) {
        final byDistance = (a - widget.initialIndex).abs().compareTo((b - widget.initialIndex).abs());
        // Ties favor the higher index: forward is the likelier swipe.
        return byDistance != 0 ? byDistance : b.compareTo(a);
      });
    final queue = [for (final i in order) widget.urls[i]];
    Future<void> work() async {
      while (queue.isNotEmpty) {
        final url = queue.removeAt(0);
        try {
          await ScreenshotGallery.downloadBytes(url);
        } catch (_) {}
      }
    }

    for (var i = 0; i < _prefetchConcurrency; i++) {
      work();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformation.dispose();
    _snapBack.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final zoomed = _transformation.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _onPointerCountChanged(int delta) {
    setState(() => _pointerCount = (_pointerCount + delta).clamp(0, 10));
    _edgeDragAccum = 0;
    _edgeFlipTriggered = false;
    _dragDx = 0;
    _dragDy = 0;
  }

  void _onPointerDown(PointerDownEvent event) {
    _onPointerCountChanged(1);
    if (_pointerCount == 1) {
      _snapBack.stop();
      _velocityTracker = VelocityTracker.withKind(event.kind);
    } else if (_dismissDragging) {
      // A second finger means a pinch, not a dismiss; ease back into place.
      _cancelDismissDrag();
    }
  }

  void _onPointerUp() {
    _endEdgeFlick();
    _onPointerCountChanged(-1);
    if (_dismissDragging && _pointerCount == 0) {
      _endDismissDrag();
    }
  }

  void _onPointerCancel() {
    _onPointerCountChanged(-1);
    if (_dismissDragging && _pointerCount == 0) {
      _cancelDismissDrag();
    }
  }

  void _onDismissPointerMove(PointerMoveEvent event) {
    if (_zoomed || _pointerCount != 1) return;
    if (!_dismissDragging) {
      _dragDx += event.delta.dx;
      _dragDy += event.delta.dy;
      if (_dragDy.abs() <= kTouchSlop || _dragDy.abs() <= _dragDx.abs()) return;
      setState(() {
        _dismissDragging = true;
        _dragOffset = _dragDy;
      });
      return;
    }
    setState(() => _dragOffset += event.delta.dy);
  }

  void _endDismissDrag() {
    final vy = _velocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0;
    final flung = vy.abs() > _dismissVelocity && vy.sign == _dragOffset.sign;
    if (_dragOffset.abs() > _dismissDistance || flung) {
      Navigator.of(context).pop();
    } else {
      _cancelDismissDrag();
    }
  }

  void _cancelDismissDrag() {
    setState(() => _dismissDragging = false);
    _snapBack.value = _dragOffset;
    _snapBack.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  /// Horizontal drag accumulated while the zoomed image is already pinned
  /// against a side edge; a significant pull past the edge flips the page,
  /// while small pan overshoots stay on the current image.
  double _edgeDragAccum = 0;
  bool _edgeFlipTriggered = false;
  static const double _edgeFlipThreshold = 80;

  /// A quick flick past the edge shouldn't have to travel the full drag
  /// distance — same as how a pager answers a fling.
  static const double _edgeFlickDistance = 24;
  static const double _edgeFlickVelocity = 400;

  /// How far the image may drift back off an edge and still count as pinned.
  /// A swipe with any vertical component wobbles a few pixels sideways per
  /// frame; a one-pixel tolerance let that noise unpin the image and throw
  /// the whole pull away, which is what made diagonal swipes feel dead.
  static const double _edgeSlop = 8;

  void _onPointerMove(PointerMoveEvent event) {
    _onDismissPointerMove(event);
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    if (!_zoomed || _pointerCount != 1 || _edgeFlipTriggered) return;
    final dx = event.delta.dx;
    if (dx == 0) return;

    // Pan bounds for a constrained InteractiveViewer: translation.x runs
    // from 0 (left edge visible) to width * (1 - scale) (right edge).
    final scale = _transformation.value.getMaxScaleOnAxis();
    final tx = _transformation.value.getTranslation().x;
    final width = MediaQuery.of(context).size.width;
    final canFlipBack = tx >= -_edgeSlop && _index > 0;
    final canFlipForward = tx <= width * (1 - scale) + _edgeSlop && _index < widget.urls.length - 1;

    // Away from a usable edge the drag is panning the image, not paging.
    if (!canFlipBack && !canFlipForward) {
      _edgeDragAccum = 0;
      return;
    }

    // Count the *net* pull rather than resetting on every opposing frame,
    // so sideways jitter only gives a little of the pull back.
    _edgeDragAccum += dx;
    if (_edgeDragAccum > 0 && !canFlipBack) _edgeDragAccum = 0;
    if (_edgeDragAccum < 0 && !canFlipForward) _edgeDragAccum = 0;

    if (_edgeDragAccum.abs() > _edgeFlipThreshold) {
      _flipPage();
    }
  }

  /// Releasing mid-pull still flips if the pull was a fast flick.
  void _endEdgeFlick() {
    if (!_zoomed || _pointerCount != 1 || _edgeFlipTriggered) return;
    if (_edgeDragAccum.abs() < _edgeFlickDistance) return;
    final vx = _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0;
    if (vx.abs() < _edgeFlickVelocity || vx.sign != _edgeDragAccum.sign) return;
    _flipPage();
  }

  void _flipPage() {
    _edgeFlipTriggered = true;
    _pageController.animateToPage(
      _index + (_edgeDragAccum > 0 ? -1 : 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Double tap toggles between fit and 2.5x zoom centered on the tap point.
  void _handleDoubleTap() {
    if (_transformation.value != Matrix4.identity()) {
      _transformation.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final position = _doubleTapPosition;
    _transformation.value = Matrix4.identity()
      ..translateByDouble(position.dx, position.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(-position.dx, -position.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    // Dragging toward dismissal fades the black backdrop so the screen
    // behind shows through, previewing the close.
    final backdropAlpha = (1 - _dragOffset.abs() / 500).clamp(0.0, 1.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              key: const ValueKey('gallery-backdrop'),
              color: Colors.black.withValues(alpha: backdropAlpha),
            ),
          ),
          Positioned.fill(child: _buildPager()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.urls.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPager() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _onPointerUp(),
      onPointerCancel: (_) => _onPointerCancel(),
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: PageView.builder(
          controller: _pageController,
          physics: _pageSwipingDisabled ? const NeverScrollableScrollPhysics() : null,
          // Pre-builds the adjacent pages so their images decode while the
          // current one is viewed, instead of during the swipe animation.
          allowImplicitScrolling: true,
          itemCount: widget.urls.length,
          onPageChanged: (index) {
            setState(() => _index = index);
            _transformation.value = Matrix4.identity();
          },
          itemBuilder: (context, index) {
            return GestureDetector(
              onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: index == _index ? _transformation : null,
                maxScale: 5,
                child: Center(
                  child: SfwBlur(
                    child: RemoteImage(
                      url: widget.urls[index],
                      fit: BoxFit.contain,
                      placeholder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white54)),
                      errorWidget: (context) =>
                          const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 64),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
