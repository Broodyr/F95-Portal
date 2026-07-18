import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/thread_page.dart';
import '../theme/app_colors.dart';
import 'remote_image.dart';
import 'screenshot_gallery.dart';
import 'sfw_blur.dart';

/// Renders parsed spoiler content: styled text runs, tappable links, and
/// inline images (tap for fullscreen). Selectable so things like magnet
/// hashes can be copied.
class RichSpoilerText extends StatefulWidget {
  final List<RichPiece> pieces;
  final void Function(Uri uri) onOpenLink;

  /// Full-size URLs the fullscreen gallery should page through instead of
  /// just this block's images (e.g. every image of a forum post), with
  /// [galleryIndexOffset] locating this block's first image inside it.
  final List<String>? galleryUrls;
  final int galleryIndexOffset;

  const RichSpoilerText({
    super.key,
    required this.pieces,
    required this.onOpenLink,
    this.galleryUrls,
    this.galleryIndexOffset = 0,
  });

  @override
  State<RichSpoilerText> createState() => _RichSpoilerTextState();
}

class _RichSpoilerTextState extends State<RichSpoilerText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(color: Colors.grey[300], fontSize: 13, height: 1.45);

    // Tapping any image opens the gallery positioned on it with the rest
    // swipeable: the caller-provided set when given, else this block's own
    // full-size URLs.
    final galleryUrls =
        widget.galleryUrls ??
        [
          for (final piece in widget.pieces)
            if (piece.imageUrl != null) piece.fullImageUrl ?? piece.imageUrl!,
        ];
    final indexOffset = widget.galleryUrls != null ? widget.galleryIndexOffset : 0;
    int imageIndex = -1;

    final spans = <InlineSpan>[];
    for (final piece in widget.pieces) {
      if (piece.newline) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      final smilieAsset = piece.smilieAsset;
      if (smilieAsset != null) {
        // Sized off the scaled font so smilies follow the font-size
        // setting; WidgetSpan children don't inherit the text scaler.
        final size = MediaQuery.textScalerOf(context).scale(baseStyle.fontSize! * 1.35);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Image.asset(
              smilieAsset,
              width: size,
              height: size,
              semanticLabel: piece.text,
              errorBuilder: (context, error, stackTrace) => Text(piece.text, style: baseStyle),
            ),
          ),
        );
        continue;
      }

      final imageUrl = piece.imageUrl;
      if (imageUrl != null) {
        // Inline shows the thumbnail; tapping opens the full-resolution
        // source (the same URL when no separate full-size was parsed).
        imageIndex++;
        final int galleryIndex = indexOffset + imageIndex;
        spans.add(
          WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GestureDetector(
                onTap: () => ScreenshotGallery.show(context, galleryUrls, initialIndex: galleryIndex),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SfwBlur(
                      child: RemoteImage(
                        url: imageUrl,
                        fit: BoxFit.contain,
                        // Decode at the 180-logical-px render height, not
                        // source size; some posts inline dozens of images.
                        decodeHeight: (180 * MediaQuery.devicePixelRatioOf(context)).round(),
                        placeholder: (context) =>
                            Container(width: 120, height: 80, color: AppColors.of(context).placeholderSurface),
                        errorWidget: (context) => Container(
                          width: 120,
                          height: 80,
                          color: AppColors.of(context).placeholderSurface,
                          child: Icon(Icons.broken_image_outlined, color: AppColors.of(context).mutedForeground, size: 24),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }

      TapGestureRecognizer? recognizer;
      final url = piece.url;
      if (url != null) {
        recognizer = TapGestureRecognizer()..onTap = () => widget.onOpenLink(Uri.parse(url));
        _recognizers.add(recognizer);
      }

      spans.add(
        TextSpan(
          text: piece.text,
          recognizer: recognizer,
          style: baseStyle.copyWith(
            color: url != null ? colorScheme.primary : null,
            fontWeight: piece.bold ? FontWeight.w600 : null,
            fontStyle: piece.italic ? FontStyle.italic : null,
            decoration: TextDecoration.combine([
              if (piece.underline || url != null) TextDecoration.underline,
              if (piece.strike) TextDecoration.lineThrough,
            ]),
            decorationColor: url != null ? colorScheme.primary : Colors.grey[300],
          ),
        ),
      );
    }

    return SelectionArea(
      child: Text.rich(TextSpan(style: baseStyle, children: spans)),
    );
  }
}
