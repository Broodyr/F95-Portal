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

  const ThreadPage({
    required this.threadId,
    this.metaFields = const [],
    this.overview = '',
    this.spoilers = const [],
    this.downloads,
  });

  String? metaValue(String label) {
    for (final field in metaFields) {
      if (field.label.toLowerCase() == label.toLowerCase()) return field.value;
    }
    return null;
  }
}

@immutable
class MetaField {
  final String label;
  final String value;

  const MetaField({required this.label, required this.value});

  @override
  String toString() => '$label: $value';
}

@immutable
class SpoilerSection {
  final String title;
  final String content;

  const SpoilerSection({required this.title, required this.content});
}

@immutable
class DownloadsSection {
  /// One group per platform line (WIN, MAC, LINUX, ANDROID, …).
  final List<DownloadGroup> platforms;

  /// Labeled non-platform downloads (cheats, saves, patches, …).
  final List<DownloadGroup> extras;

  const DownloadsSection({this.platforms = const [], this.extras = const []});

  bool get isEmpty => platforms.isEmpty && extras.isEmpty;
}

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
