import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/image_urls.dart';
import 'remote_image.dart';
import 'sfw_blur.dart';

class CoverImage extends StatefulWidget {
  final String? imageUrl;

  /// The card's blurred reflection copy passes false: behind the blur the
  /// HD upgrade is invisible, and skipping it halves the decode work.
  final bool upgradeToHd;

  const CoverImage({super.key, this.imageUrl, this.upgradeToHd = true});

  /// How long a card must stay alive before its HD upgrade starts. Cards
  /// flung past during a fast scroll are disposed sooner than this, so they
  /// never trigger the multi-MB download + decode that froze scrolling.
  static const Duration hdUpgradeDelay = Duration(milliseconds: 250);

  /// HD URLs that finished loading this session: safe to show without the
  /// delay (they come from the image cache or local disk, not the network).
  static final Set<String> _hdLoaded = {};

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  Timer? _hdTimer;
  bool _wantHd = false;

  @override
  void initState() {
    super.initState();
    _scheduleHdUpgrade();
  }

  @override
  void didUpdateWidget(CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.upgradeToHd != widget.upgradeToHd) {
      _hdTimer?.cancel();
      _wantHd = false;
      _scheduleHdUpgrade();
    }
  }

  @override
  void dispose() {
    _hdTimer?.cancel();
    super.dispose();
  }

  String? get _hdUrl {
    final url = widget.imageUrl;
    if (!widget.upgradeToHd || url == null || url.isEmpty) return null;
    // Animated covers keep the preview: HD GIF attachments are multi-MB
    // downloads plus per-frame decode for barely-visible gains, and were
    // the slowest images in scroll profiling.
    if (url.toLowerCase().endsWith('.gif')) return null;
    return toHdImageUrl(url);
  }

  void _scheduleHdUpgrade() {
    final hd = _hdUrl;
    if (hd == null) return;
    if (CoverImage._hdLoaded.contains(hd)) {
      _wantHd = true;
      return;
    }
    _hdTimer = Timer(CoverImage.hdUpgradeDelay, () {
      if (mounted) setState(() => _wantHd = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Decode at the rendered size instead of the source's native size —
    // full-res HD decodes are what janked the Browse scroll.
    final decodeWidth = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();

    final url = widget.imageUrl;
    return AspectRatio(
      aspectRatio: 3.0, // 3:1 aspect ratio
      child: Container(
        decoration: BoxDecoration(color: AppColors.of(context).placeholderSurface),
        child: ClipRRect(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
          child: url != null && url.isNotEmpty ? SfwBlur(child: _buildImage(url, decodeWidth)) : _buildPlaceholder(),
        ),
      ),
    );
  }

  /// The API serves low-quality preview covers. The preview keeps its own
  /// permanent layer — adding the HD overlay later must not disturb its
  /// element (an in-place URL swap restarts loading and the preview loses
  /// the race, leaving bare placeholders during fast scrolls). The HD layer
  /// is transparent until decoded, then fades in on top; if it fails, the
  /// preview simply stays.
  Widget _buildImage(String url, int decodeWidth) {
    final hd = _hdUrl;
    final lowRes = RemoteImage(
      url: url,
      fit: BoxFit.cover,
      decodeWidth: decodeWidth,
      placeholder: (context) => _buildPlaceholder(),
    );
    if (hd == null) return lowRes;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        lowRes,
        if (_wantHd)
          Positioned.fill(
            child: RemoteImage(
              url: hd,
              fit: BoxFit.cover,
              decodeWidth: decodeWidth,
              onLoaded: () => CoverImage._hdLoaded.add(hd),
              errorWidget: (context) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.of(context).placeholderSurface,
      child: Center(child: Icon(Icons.image_outlined, color: AppColors.of(context).mutedForeground, size: 48)),
    );
  }
}
