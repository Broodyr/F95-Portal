/// f95zone serves each attachment image at three quality levels sharing one
/// path: `attachments.f95zone.to/...` (full HD), the same path with a
/// `/thumb/` segment (grid thumbnail), and `preview.f95zone.to/...`
/// (downscaled preview, what the latest-updates API returns for covers and
/// screenshots).
library;

const String _previewHost = 'preview.f95zone.to';
const String _attachmentsHost = 'attachments.f95zone.to';

/// The full-quality variant of [url], or null when none is known (already
/// HD, or not an f95 image host).
String? toHdImageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isScheme('https') && !uri.isScheme('http')) return null;
  if (uri.host == _previewHost) {
    return uri.replace(host: _attachmentsHost).toString();
  }
  if (uri.host == _attachmentsHost && url.contains('/thumb/')) {
    return url.replaceFirst('/thumb/', '/');
  }
  return null;
}

/// The low-quality preview variant of [url], or null when none is known
/// (already low quality, or not an f95 image host).
String? toPreviewImageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != _attachmentsHost || url.contains('/thumb/')) return null;
  return uri.replace(host: _previewHost).toString();
}
