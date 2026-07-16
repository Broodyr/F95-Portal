import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Cached network image that decodes AVIF in-process.
///
/// The f95 CDN serves its "png/jpg" attachments as AVIF, which Flutter's
/// Android pipeline hands to a per-image MediaCodec session — allocating and
/// destroying a hardware video codec for every cover was the main source of
/// scroll jank (and the CCodec log spam). flutter_avif decodes with a
/// bundled dav1d instead, entirely in-process.
///
/// Files land in the same flutter_cache_manager disk cache the gallery's
/// byte prefetch fills. On web this falls back to CachedNetworkImage
/// (browsers decode AVIF natively and dart:io file access doesn't apply).
class RemoteImage extends StatefulWidget {
  final String url;
  final BoxFit? fit;

  /// Decode-size caps applied to non-AVIF images. AVIF always decodes at
  /// its native size (dav1d has no subsampled decode), which is still far
  /// cheaper than a MediaCodec round trip.
  final int? decodeWidth;
  final int? decodeHeight;

  /// Shown while the image loads, and on failure when [errorWidget] is null.
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;

  /// Invoked (possibly repeatedly, during build) once a frame is on screen.
  final VoidCallback? onLoaded;

  const RemoteImage({
    super.key,
    required this.url,
    this.fit,
    this.decodeWidth,
    this.decodeHeight,
    this.placeholder,
    this.errorWidget,
    this.onLoaded,
  });

  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  ImageProvider? _provider;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _resolve();
  }

  @override
  void didUpdateWidget(RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.decodeWidth != widget.decodeWidth ||
        oldWidget.decodeHeight != widget.decodeHeight) {
      _provider = null;
      _failed = false;
      if (!kIsWeb) _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url;
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      // The AVIF signature ('ftypavif'/'ftypavis') sits in the first bytes.
      final header = await file.openRead(0, 32).fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      if (!mounted || widget.url != url) return;
      final ImageProvider provider = isAvifFile(Uint8List.fromList(header)) != AvifFileType.unknown
          ? FileAvifImage(file)
          : ResizeImage.resizeIfNeeded(widget.decodeWidth, widget.decodeHeight, FileImage(file));
      setState(() => _provider = provider);
    } catch (_) {
      if (mounted && widget.url == url) setState(() => _failed = true);
    }
  }

  Widget _buildError(BuildContext context) =>
      (widget.errorWidget ?? widget.placeholder)?.call(context) ?? const SizedBox.shrink();

  Widget _buildLoading(BuildContext context) => widget.placeholder?.call(context) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return CachedNetworkImage(
        imageUrl: widget.url,
        fit: widget.fit,
        memCacheWidth: widget.decodeWidth,
        memCacheHeight: widget.decodeHeight,
        imageBuilder: widget.onLoaded == null
            ? null
            : (context, imageProvider) {
                widget.onLoaded!();
                return Image(image: imageProvider, fit: widget.fit);
              },
        placeholder: widget.placeholder == null ? null : (context, _) => widget.placeholder!(context),
        errorWidget: (context, _, error) => _buildError(context),
      );
    }

    if (_failed) return _buildError(context);
    final provider = _provider;
    if (provider == null) return _buildLoading(context);
    return Image(
      image: provider,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _buildError(context),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) return _buildLoading(context);
        widget.onLoaded?.call();
        return child;
      },
    );
  }
}
