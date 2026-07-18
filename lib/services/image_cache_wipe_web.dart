/// Web variant: the cache manager stores nothing on the file system.
Future<void> wipeImageCacheDir() async {}

/// Web variant: no files on disk, nothing to trim.
Future<void> trimImageCacheDir() async {}
