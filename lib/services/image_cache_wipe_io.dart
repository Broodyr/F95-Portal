import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// See image_cache_wipe.dart for why the folder is deleted wholesale.
/// [tempDir] overrides the platform temp directory for tests.
Future<void> wipeImageCacheDir({Directory? tempDir}) async {
  final base = tempDir ?? await getTemporaryDirectory();
  final dir = Directory(p.join(base.path, DefaultCacheManager.key));
  if (await dir.exists()) await dir.delete(recursive: true);
}

/// The image cache's disk budget; the whole folder is kept under this.
const int imageCacheBudgetBytes = 200 * 1024 * 1024;

/// Deletes oldest-modified cache files until the folder fits [maxBytes].
///
/// This is the app's own eviction, run at startup: the package's age and
/// capacity cleanup shares emptyCache()'s path bug and never deletes a
/// file, so without this the folder grows without bound (files past the
/// 200-entry index cap even become orphans it re-downloads). Stale sqlite
/// rows left behind are fine — retrieveCacheData notices the missing file,
/// drops the row, and re-downloads.
Future<void> trimImageCacheDir({int maxBytes = imageCacheBudgetBytes, Directory? tempDir}) async {
  final base = tempDir ?? await getTemporaryDirectory();
  final dir = Directory(p.join(base.path, DefaultCacheManager.key));
  if (!await dir.exists()) return;

  final files = <(File, FileStat)>[];
  var total = 0;
  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final stat = await entity.stat();
    files.add((entity, stat));
    total += stat.size;
  }
  if (total <= maxBytes) return;

  files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
  for (final (file, stat) in files) {
    if (total <= maxBytes) break;
    try {
      await file.delete();
      total -= stat.size;
    } catch (_) {
      // A file mid-download may refuse deletion; leave it for next launch.
    }
  }
}
