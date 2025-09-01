import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;

/// A stateful widget that generates the noise pattern once, caches it as an
/// image, and then simply draws that cached image on subsequent frames.
class PreRenderedNoisyBackground extends StatefulWidget {
  final Widget child;
  final Color backgroundColor;
  final double noiseOpacity;

  const PreRenderedNoisyBackground({
    super.key,
    required this.child,
    this.backgroundColor = const Color(0xFF121212),
    this.noiseOpacity = 0.03,
  });

  @override
  State<PreRenderedNoisyBackground> createState() =>
      _PreRenderedNoisyBackgroundState();
}

class _PreRenderedNoisyBackgroundState
    extends State<PreRenderedNoisyBackground> {
  ui.Image? _noiseImage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-render the noise if the screen size changes.
    _createNoiseImage();
  }

  void _createNoiseImage() {
    final size = MediaQuery.of(context).size;
    if (size.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final painter = NoisePainter(opacity: widget.noiseOpacity);
    painter.paint(canvas, size);

    final picture = recorder.endRecording();

    picture.toImage(size.width.ceil(), size.height.ceil()).then((image) {
      setState(() {
        _noiseImage = image;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: widget.backgroundColor),

        if (_noiseImage != null)
          CustomPaint(
            size: Size.infinite,
            painter: _CachedImagePainter(image: _noiseImage!),
          ),

        widget.child,
      ],
    );
  }
}

/// A very simple painter that just draws a pre-rendered image onto the canvas.
class _CachedImagePainter extends CustomPainter {
  final ui.Image image;

  _CachedImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(covariant _CachedImagePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

class NoisePainter extends CustomPainter {
  final double opacity;
  NoisePainter({required this.opacity});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: opacity);
    final random = Random(42);
    final dotCount = (size.width * size.height) / 5;
    for (int i = 0; i < dotCount; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant NoisePainter oldDelegate) => false;
}
