import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

enum _Stage { idle, loading, ready, failed }

/// An embedded post video. Nothing loads until tapped — posts can carry
/// several, and a player per video would fetch and decode them all — then
/// it plays inline with controls, including fullscreen.
class InlineVideo extends StatefulWidget {
  final String url;

  const InlineVideo({super.key, required this.url});

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  _Stage _stage = _Stage.idle;

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  void _disposePlayer() {
    _chewie?.dispose();
    _chewie = null;
    // A controller whose initialize() failed can rethrow from dispose().
    _video?.dispose().catchError((_) {});
    _video = null;
  }

  Future<void> _load() async {
    _disposePlayer();
    setState(() => _stage = _Stage.loading);
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _video = controller;
    try {
      await controller.initialize();
    } catch (_) {
      if (mounted && controller == _video) setState(() => _stage = _Stage.failed);
      return;
    }
    if (!mounted || controller != _video) return;
    _chewie = ChewieController(
      videoPlayerController: controller,
      autoPlay: true,
      looping: false,
      allowMuting: true,
      aspectRatio: controller.value.aspectRatio,
    );
    setState(() => _stage = _Stage.ready);
  }

  @override
  Widget build(BuildContext context) {
    final chewie = _chewie;
    if (_stage == _Stage.ready && chewie != null) {
      return AspectRatio(
        aspectRatio: chewie.aspectRatio ?? 16 / 9,
        child: Chewie(controller: chewie),
      );
    }

    final colors = AppColors.of(context);
    final Widget badge = switch (_stage) {
      _Stage.loading => const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
      _Stage.failed => Icon(Icons.videocam_off_outlined, color: colors.mutedForeground, size: 32),
      _ => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.45)),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
      ),
    };

    return GestureDetector(
      onTap: _stage == _Stage.loading ? null : _load,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: colors.placeholderSurface,
          child: Center(child: badge),
        ),
      ),
    );
  }
}
