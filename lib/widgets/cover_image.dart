import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../utils/image_urls.dart';
import 'sfw_blur.dart';

class CoverImage extends StatelessWidget {
  final String? imageUrl;

  /// The card's blurred reflection copy passes false: behind the blur the
  /// HD upgrade is invisible, and skipping it halves the decode work.
  final bool upgradeToHd;

  const CoverImage({super.key, this.imageUrl, this.upgradeToHd = true});

  @override
  Widget build(BuildContext context) {
    // Decode at the rendered size instead of the source's native size —
    // full-res HD decodes are what janked the Browse scroll.
    final decodeWidth = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();

    return AspectRatio(
      aspectRatio: 3.0, // 3:1 aspect ratio
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF2A2A2A)),
        child: ClipRRect(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? SfwBlur(child: _buildImage(imageUrl!, decodeWidth))
              : _buildPlaceholder(),
        ),
      ),
    );
  }

  /// The API serves low-quality preview covers; load the HD variant with the
  /// preview standing in while it downloads (and staying if HD fails).
  Widget _buildImage(String url, int decodeWidth) {
    final hd = upgradeToHd ? toHdImageUrl(url) : null;
    if (hd == null) {
      return _lowResImage(url, decodeWidth);
    }
    return CachedNetworkImage(
      imageUrl: hd,
      fit: BoxFit.cover,
      memCacheWidth: decodeWidth,
      placeholder: (context, _) => _lowResImage(url, decodeWidth),
      errorWidget: (context, _, error) => _lowResImage(url, decodeWidth),
    );
  }

  Widget _lowResImage(String url, int decodeWidth) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: decodeWidth,
      placeholder: (context, _) => _buildPlaceholder(),
      errorWidget: (context, _, error) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF3A3A3A),
      child: const Center(child: Icon(Icons.image_outlined, color: Color(0xFF666666), size: 48)),
    );
  }
}
