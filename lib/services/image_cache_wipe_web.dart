/// Web variant: the cache manager stores nothing on the file system.
Future<void> wipeImageCacheDir() async {}

/// Web variant: no files on disk, nothing to trim.
Future<void> trimImageCacheDir() async {}

/// Web variant: no files on disk, so nothing is being held.
Future<int> imageCacheDirBytes() async => 0;
