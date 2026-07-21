import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';

import 'image_save_result.dart';

/// Writes the image at [url] into the device's photo gallery.
///
/// Goes through the disk cache rather than re-fetching: the viewer has
/// already prefetched every image it shows, so the file is on disk and
/// the save is instant.
///
/// Access is requested here, at the moment of the first save, rather than
/// at startup — the app has no business asking for the photo library
/// until the user reaches for it. On Android 10+ writing to the gallery
/// needs no permission at all, so most devices never see a prompt; the
/// manifest entry is capped at API 29 for the older ones.
Future<ImageSaveResult> saveImageToGallery(String url) async {
  try {
    if (!await Gal.hasAccess()) {
      if (!await Gal.requestAccess()) return ImageSaveResult.denied;
    }
    final file = await DefaultCacheManager().getSingleFile(url);
    final bytes = await file.readAsBytes();

    if (isAvif(bytes)) {
      final decoded = await avifToPng(bytes);
      if (decoded == null) return ImageSaveResult.failed;
      // Bytes rather than a path: the gallery would otherwise take the
      // file's extension at its word. See [isAvif].
      await Gal.putImageBytes(decoded.png, name: saveFileName(url));
      return decoded.animated ? ImageSaveResult.savedAsStill : ImageSaveResult.saved;
    } else {
      // Not AVIF, so the file is what it claims to be — hand over the
      // original rather than re-encoding it. This is the path animated
      // GIFs take (f95 only converts stills to AVIF): the bytes are
      // copied verbatim, so the animation survives. The cache manager
      // named the file from the response's Content-Type, so its
      // extension reflects the real format rather than the URL's claim.
      await Gal.putImage(file.path);
    }
    return ImageSaveResult.saved;
  } on GalException catch (e) {
    return e.type == GalExceptionType.accessDenied ? ImageSaveResult.denied : ImageSaveResult.failed;
  } catch (_) {
    return ImageSaveResult.failed;
  }
}

/// The AVIF marker sits in the opening box; only the head is examined
/// because the check is a subset scan, and running it over a whole
/// multi-megabyte image would both cost more and risk matching pixel
/// data that happens to spell the marker.
AvifFileType _avifType(Uint8List bytes) =>
    isAvifFile(bytes.sublist(0, math.min(32, bytes.length)));

/// Whether these bytes are AVIF, whatever the file is named.
///
/// The f95 CDN re-encodes attachments to AVIF but keeps the original
/// .png/.jpg name, so the extension cannot be trusted — the same reason
/// RemoteImage sniffs before choosing a decoder. It matters more here:
/// the gallery stores a saved file under the MIME type implied by its
/// extension, so AVIF bytes saved as "screenshot.png" become an entry
/// the system decoder can't read — a broken thumbnail, not an error.
bool isAvif(Uint8List bytes) => _avifType(bytes) != AvifFileType.unknown;

/// Re-encodes AVIF to PNG, which every gallery can read. Null if the
/// image can't be decoded.
///
/// PNG because it is what Flutter can encode without a further
/// dependency; it's lossless, so a saved file is bigger than the AVIF it
/// came from, which is the right trade for a deliberate download.
///
/// Only ever takes the first frame, and reports whether there were more
/// so the caller can say the animation didn't survive. Keeping it would
/// mean writing a format Flutter cannot encode — see [ImageSaveResult]'s
/// savedAsStill. The codec is picked the way FileAvifImage picks it,
/// because the single-frame decoder cannot open an image sequence at all.
Future<({Uint8List png, bool animated})?> avifToPng(Uint8List bytes) async {
  final type = _avifType(bytes);
  if (type == AvifFileType.unknown) return null;
  final codec = type == AvifFileType.avif
      ? SingleFrameAvifCodec(bytes: bytes)
      // Keyed randomly, as flutter_avif's own decodeAvif does: the key
      // names the decoder held on the Rust side, so a fixed one would
      // collide with any other decode in flight.
      : MultiFrameAvifCodec(key: math.Random().nextInt(1 << 32), avifBytes: bytes);
  ui.Image? image;
  try {
    await codec.ready();
    // Read after ready(): the multi-frame codec only knows the count
    // once the container has been parsed. Asked rather than inferred
    // from the 'avis' brand, which marks a sequence that may still hold
    // a single frame — nothing is lost there and it shouldn't say so.
    final animated = codec.frameCount > 1;
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return (png: png.buffer.asUint8List(), animated: animated);
  } catch (e) {
    if (kDebugMode) debugPrint('AVIF transcode failed: $e');
    return null;
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

/// Gallery entry name for [url], without an extension — the gallery adds
/// one to match the format it detects. Falls back to gal's own default
/// when the URL carries no usable name.
String saveFileName(String url) {
  final segments = Uri.tryParse(url)?.pathSegments ?? const [];
  final last = segments.isEmpty ? '' : segments.last;
  final base = last.contains('.') ? last.substring(0, last.lastIndexOf('.')) : last;
  // The gallery takes this as a display name and writes a file called it,
  // so anything not safe in a file name is replaced rather than risking a
  // save that fails on a character the user never sees.
  final safe = base.replaceAll(RegExp(r'[^\w\-. ]'), '_').trim();
  // A name made entirely of replacements carries nothing; the generic
  // fallback reads better in the gallery than "___".
  return RegExp(r'[a-zA-Z0-9]').hasMatch(safe) ? safe : 'image';
}
