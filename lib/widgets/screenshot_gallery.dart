import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScreenshotGallery(urls: urls, initialIndex: initialIndex),
      ),
    );
  }

  @override
  State<ScreenshotGallery> createState() => _ScreenshotGalleryState();
}

class _ScreenshotGalleryState extends State<ScreenshotGallery> {
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
  bool get _pageSwipingDisabled => _pointerCount >= 2 || _zoomed;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformation.addListener(_onTransformationChanged);
    _prefetchBytes();
  }

  /// HD images are only fetched once the viewer opens; start downloading
  /// them all now (nearest to the opened image first) so swiping doesn't
  /// wait on the network. Bytes only — never decode ahead of display.
  void _prefetchBytes() {
    final order = List.generate(widget.urls.length, (i) => i)
      ..sort((a, b) {
        final byDistance = (a - widget.initialIndex).abs().compareTo((b - widget.initialIndex).abs());
        // Ties favor the higher index: forward is the likelier swipe.
        return byDistance != 0 ? byDistance : b.compareTo(a);
      });
    for (final i in order) {
      ScreenshotGallery.downloadBytes(widget.urls[i]).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformation.dispose();
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
  }

  /// Horizontal drag accumulated while the zoomed image is already pinned
  /// against a side edge; a significant pull past the edge flips the page,
  /// while small pan overshoots stay on the current image.
  double _edgeDragAccum = 0;
  bool _edgeFlipTriggered = false;
  static const double _edgeFlipThreshold = 110;

  void _onPointerMove(PointerMoveEvent event) {
    if (!_zoomed || _pointerCount != 1 || _edgeFlipTriggered) return;
    final dx = event.delta.dx;
    if (dx == 0) return;

    // Pan bounds for a constrained InteractiveViewer: translation.x runs
    // from 0 (left edge visible) to width * (1 - scale) (right edge).
    final scale = _transformation.value.getMaxScaleOnAxis();
    final tx = _transformation.value.getTranslation().x;
    final width = MediaQuery.of(context).size.width;
    const slop = 1.0;
    final atLeftEdge = tx >= -slop;
    final atRightEdge = tx <= width * (1 - scale) + slop;

    if (dx > 0 && atLeftEdge && _index > 0) {
      _edgeDragAccum = (_edgeDragAccum > 0 ? _edgeDragAccum : 0) + dx;
    } else if (dx < 0 && atRightEdge && _index < widget.urls.length - 1) {
      _edgeDragAccum = (_edgeDragAccum < 0 ? _edgeDragAccum : 0) + dx;
    } else {
      _edgeDragAccum = 0;
      return;
    }

    if (_edgeDragAccum.abs() > _edgeFlipThreshold) {
      _edgeFlipTriggered = true;
      _pageController.animateToPage(
        _index + (_edgeDragAccum > 0 ? -1 : 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
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
                  borderRadius: BorderRadius.circular(999),
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
                    borderRadius: BorderRadius.circular(999),
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
        onPointerDown: (_) => _onPointerCountChanged(1),
        onPointerMove: _onPointerMove,
      onPointerUp: (_) => _onPointerCountChanged(-1),
        onPointerCancel: (_) => _onPointerCountChanged(-1),
        child: PageView.builder(
          controller: _pageController,
          physics: _pageSwipingDisabled ? const NeverScrollableScrollPhysics() : null,
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
                    child: CachedNetworkImage(
                      imageUrl: widget.urls[index],
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator(color: Colors.white54)),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 64),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    );
  }
}
