import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/thread_page.dart';
import 'screenshot_gallery.dart';
import 'sfw_blur.dart';

/// Renders parsed spoiler content: styled text runs, tappable links, and
/// inline images (tap for fullscreen). Selectable so things like magnet
/// hashes can be copied.
class RichSpoilerText extends StatefulWidget {
  final List<RichPiece> pieces;
  final void Function(Uri uri) onOpenLink;

  const RichSpoilerText({super.key, required this.pieces, required this.onOpenLink});

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

    final spans = <InlineSpan>[];
    for (final piece in widget.pieces) {
      if (piece.newline) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      final imageUrl = piece.imageUrl;
      if (imageUrl != null) {
        spans.add(
          WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GestureDetector(
                onTap: () => ScreenshotGallery.show(context, [imageUrl]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SfwBlur(
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) =>
                            Container(width: 120, height: 80, color: const Color(0xFF2A2A2A)),
                        errorWidget: (context, url, error) => Container(
                          width: 120,
                          height: 80,
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.broken_image_outlined, color: Color(0xFF666666), size: 24),
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
