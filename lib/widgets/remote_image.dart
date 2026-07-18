import 'dart:async';

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
/// byte prefetch fills. URLs resolved once are remembered, so rebuilding a
/// widget for a known image shows it synchronously instead of repeating the
/// cache-manager round trip. On web this falls back to CachedNetworkImage
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
  /// When null, the image occupies no visual space until ready and then
  /// fades in — the transparent-overlay mode CoverImage layers HD with.
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

  /// Providers by url + decode caps. A hit skips the async cache-manager
  /// lookup entirely, so rebuilt widgets (scrolling back, HD layered over a
  /// just-shown preview) paint from the image cache without a placeholder
  /// flash. Entries are just file paths; the pixel memory itself stays
  /// under the global imageCache's control.
  static final Map<String, ImageProvider> _resolved = {};

  /// In-flight resolves by the same key, so widgets showing the same image
  /// concurrently (a card's cover and its reflection) share one fetch.
  static final Map<String, Future<ImageProvider>> _inflight = {};

  /// Drops every url→provider memo. Call after wiping the disk cache so
  /// rebuilt widgets re-fetch instead of erroring on deleted files.
  static void forgetResolved() => _resolved.clear();

  static Future<ImageProvider> _sharedResolve(String key, Future<ImageProvider> Function() create) {
    // Block body on purpose: an arrow would return the removed future to
    // whenComplete, which then waits on it — a future awaiting itself.
    return _inflight[key] ??= create().whenComplete(() {
      _inflight.remove(key);
    });
  }

  /// Fetches and sniffs one URL into a provider; swappable so tests can
  /// exercise the loading pipeline without the real cache manager.
  static Future<ImageProvider> Function(String url, int? decodeWidth, int? decodeHeight) loadProvider =
      _defaultLoadProvider;

  static Future<ImageProvider> _defaultLoadProvider(String url, int? decodeWidth, int? decodeHeight) async {
    final stopwatch = Stopwatch()..start();
    final file = await DefaultCacheManager().getSingleFile(url);
    // The AVIF signature ('ftypavif'/'ftypavis') sits in the first bytes.
    final header = await file.openRead(0, 32).fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
    if (kDebugMode && stopwatch.elapsedMilliseconds > 500) {
      debugPrint('RemoteImage slow resolve: ${stopwatch.elapsedMilliseconds}ms $url');
    }
    return isAvifFile(Uint8List.fromList(header)) != AvifFileType.unknown
        ? FileAvifImage(file)
        : ResizeImage.resizeIfNeeded(decodeWidth, decodeHeight, FileImage(file));
  }

  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  ImageProvider? _provider;
  bool _failed = false;

  /// One retry after an error from a remembered provider, in case the
  /// cache manager evicted the file behind it.
  bool _retried = false;

  /// Delays before re-attempting a failed download. A rate-limited CDN
  /// rejects a burst of requests in milliseconds, so without these the
  /// error widget appears "instantly" and sticks for this state's whole
  /// lifetime; the placeholder stays up while retries remain.
  static const List<Duration> _retryDelays = [Duration(seconds: 2), Duration(seconds: 6)];
  int _failedAttempts = 0;
  Timer? _retryTimer;

  String get _cacheKey => '${widget.url}|${widget.decodeWidth}|${widget.decodeHeight}';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _initProvider();
  }

  @override
  void didUpdateWidget(RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.decodeWidth != widget.decodeWidth ||
        oldWidget.decodeHeight != widget.decodeHeight) {
      _provider = null;
      _failed = false;
      _retried = false;
      _failedAttempts = 0;
      _retryTimer?.cancel();
      if (!kIsWeb) _initProvider();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _initProvider() {
    _provider = RemoteImage._resolved[_cacheKey];
    if (_provider == null) _resolve();
  }

  Future<void> _resolve() async {
    final key = _cacheKey;
    final url = widget.url;
    final decodeWidth = widget.decodeWidth;
    final decodeHeight = widget.decodeHeight;
    try {
      final provider = await RemoteImage._sharedResolve(
        key,
        () => RemoteImage.loadProvider(url, decodeWidth, decodeHeight),
      );
      RemoteImage._resolved[key] = provider;
      if (!mounted || key != _cacheKey) return;
      setState(() => _provider = provider);
    } catch (_) {
      if (!mounted || key != _cacheKey) return;
      if (_failedAttempts < _retryDelays.length) {
        _retryTimer = Timer(_retryDelays[_failedAttempts++], () {
          if (mounted && key == _cacheKey) _resolve();
        });
      } else {
        setState(() => _failed = true);
      }
    }
  }

  /// The file behind a remembered provider may have been evicted from the
  /// disk cache; drop the memo and re-fetch once before giving up.
  void _onImageError() {
    if (_retried) return;
    _retried = true;
    RemoteImage._resolved.remove(_cacheKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _provider = null);
      _resolve();
    });
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
      errorBuilder: (context, error, stackTrace) {
        _onImageError();
        return _buildError(context);
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) {
          widget.onLoaded?.call();
          return child;
        }
        if (frame == null && widget.placeholder != null) return _buildLoading(context);
        if (frame != null) widget.onLoaded?.call();
        // Without a placeholder the image is a transparent overlay until its
        // first frame, then fades in over whatever sits beneath it.
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}
