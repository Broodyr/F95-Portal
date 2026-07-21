import 'package:flutter/foundation.dart';

/// Parsed contents of a thread's first post. Game threads have no enforced
/// structure, so every part is optional: the parser emits whatever blocks it
/// recognizes and the UI renders only what exists.
@immutable
class ThreadPage {
  final int threadId;

  /// `<b>Label:</b> value` pairs (Developer, Version, OS, Censored, …).
  final List<MetaField> metaFields;

  /// Text following the `Overview:` label.
  final String overview;

  /// Every spoiler block, in order: known titles (Changelog, Installation)
  /// and one-offs (Developer Notes, Keyboard Operation, …) alike.
  final List<SpoilerSection> spoilers;

  final DownloadsSection? downloads;

  /// XenForo attachments on the first post (torrents, archives, …).
  final List<DownloadLink> attachments;

  /// Like/watch endpoints and current state; null when the page was fetched
  /// without a logged-in session (the links only render for members).
  final ThreadActions? actions;

  const ThreadPage({
    required this.threadId,
    this.metaFields = const [],
    this.overview = '',
    this.spoilers = const [],
    this.downloads,
    this.attachments = const [],
    this.actions,
  });

  String? metaValue(String label) {
    for (final field in metaFields) {
      if (field.label.toLowerCase() == label.toLowerCase()) return field.value;
    }
    return null;
  }
}

/// XenForo CSRF token plus the first post's bookmark endpoint, with the
/// state the page reported.
@immutable
class ThreadActions {
  final String csrfToken;
  final String bookmarkUrl;
  final bool bookmarked;

  const ThreadActions({required this.csrfToken, required this.bookmarkUrl, this.bookmarked = false});
}

@immutable
class MetaField {
  final String label;
  final String value;

  const MetaField({required this.label, required this.value});

  @override
  String toString() => '$label: $value';
}

/// One inline piece of rich spoiler content.
@immutable
class RichPiece {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// Set when the piece is a link.
  final String? url;

  /// Set when the piece is an inline image (text/styles unused). This is
  /// the thumbnail shown inline; [fullImageUrl] is opened when tapped.
  final String? imageUrl;

  /// Full-resolution source for an image piece, when it differs from the
  /// inline thumbnail ([imageUrl] is used when null).
  final String? fullImageUrl;

  /// The image's height at source, when the markup gave one. Lets the view
  /// reserve the right height before the image arrives, so posts don't grow
  /// under a reader who is already looking at them. Null when unstated,
  /// which is most of them.
  final int? imageHeight;

  /// The image's width at source; only set alongside [imageHeight], and only
  /// to shape the space reserved for it. Height is what keeps the layout
  /// still, so it is parsed on its own where the width isn't given.
  final int? imageWidth;

  /// True for explicit line breaks (text/styles unused).
  final bool newline;

  /// Bundled asset for a forum smilie, rendered inline at text size.
  /// [text] holds the shortcode (e.g. `:love:`) so plain-text renderings
  /// and BBCode quotes round-trip; a null asset (unmapped donor emote)
  /// shows the shortcode instead.
  final String? smilieAsset;

  const RichPiece.text(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.url,
  }) : imageUrl = null,
       fullImageUrl = null,
       imageHeight = null,
       imageWidth = null,
       smilieAsset = null,
       newline = false;

  const RichPiece.image(this.imageUrl, {this.fullImageUrl, this.imageHeight, this.imageWidth})
    : text = '',
      bold = false,
      italic = false,
      underline = false,
      strike = false,
      url = null,
      smilieAsset = null,
      newline = false;

  const RichPiece.smilie(this.text, {String? asset})
    : bold = false,
      italic = false,
      underline = false,
      strike = false,
      url = null,
      imageUrl = null,
      fullImageUrl = null,
      imageHeight = null,
      imageWidth = null,
      smilieAsset = asset,
      newline = false;

  const RichPiece.newline()
    : text = '',
      bold = false,
      italic = false,
      underline = false,
      strike = false,
      url = null,
      imageUrl = null,
      fullImageUrl = null,
      imageHeight = null,
      imageWidth = null,
      smilieAsset = null,
      newline = true;
}

@immutable
class SpoilerSection {
  final String title;

  /// Plain-text rendition of the content.
  final String content;

  /// Rich rendition: formatting, links, and inline images.
  final List<RichPiece> rich;

  const SpoilerSection({required this.title, required this.content, this.rich = const []});
}

@immutable
class DownloadsSection {
  /// Download sets in post order. Most threads have one untitled set; some
  /// carry alternates ("Incest Version (v0.15)") as additional titled sets.
  final List<DownloadSet> sets;

  /// Labeled extras (cheats, saves, patches, …).
  final List<DownloadGroup> extras;

  const DownloadsSection({this.sets = const [], this.extras = const []});

  bool get isEmpty => sets.every((s) => s.groups.isEmpty) && extras.isEmpty;
}

@immutable
class DownloadSet {
  /// Null for the main/untitled set.
  final String? title;
  final List<DownloadGroup> groups;

  const DownloadSet({this.title, required this.groups});
}

/// One labeled line of download links (a platform, "Collection:", …).
@immutable
class DownloadGroup {
  final String label;
  final List<DownloadLink> links;

  const DownloadGroup({required this.label, required this.links});
}

@immutable
class DownloadLink {
  /// Host name as written in the post (MEGA, PIXELDRAIN, GOFILE, …).
  final String host;
  final String url;

  const DownloadLink({required this.host, required this.url});
}
