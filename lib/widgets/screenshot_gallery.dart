import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'sfw_blur.dart';

/// Fullscreen swipeable screenshot viewer with pinch-zoom.
class ScreenshotGallery extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

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
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.urls.length}', style: const TextStyle(fontSize: 16)),
      ),
      body: Listener(
        onPointerDown: (_) => _onPointerCountChanged(1),
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
      ),
    );
  }
}
