/// Deletes the flutter_cache_manager image store from disk.
///
/// flutter_cache_manager 3.4.1's emptyCache() removes its database rows but
/// resolves each file's relative path against the process working directory
/// instead of the cache folder (cache_store.dart, _removeCachedFile), so no
/// file is ever deleted — every cached image becomes an unreachable orphan.
/// Its age/capacity eviction shares the bug, so the folder only ever grows.
/// The reliable cleanup is deleting the folder itself; the manager recreates
/// it on the next download. Web keeps no files on disk, so its variant is a
/// no-op (and dart:io wouldn't compile there).
library;

export 'image_cache_wipe_web.dart' if (dart.library.io) 'image_cache_wipe_io.dart';
