import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'sfw_blur.dart';

class CoverImage extends StatelessWidget {
  final String? imageUrl;

  const CoverImage({super.key, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3.0, // 3:1 aspect ratio
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF2A2A2A)),
        child: ClipRRect(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? SfwBlur(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _buildPlaceholder(),
                    errorWidget: (context, url, error) => _buildPlaceholder(),
                  ),
                )
              : _buildPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF3A3A3A),
      child: const Center(child: Icon(Icons.image_outlined, color: Color(0xFF666666), size: 48)),
    );
  }
}
