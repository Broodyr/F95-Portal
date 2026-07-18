import 'dart:io';

import 'package:f95_portal/services/image_cache_wipe_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('image_cache_wipe_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('deletes the cache manager folder and everything in it', () async {
    final cacheDir = Directory(p.join(tempDir.path, 'libCachedImageData'))..createSync();
    File(p.join(cacheDir.path, 'aaaa.avif')).writeAsBytesSync([1, 2, 3]);
    File(p.join(cacheDir.path, 'bbbb.file')).writeAsBytesSync([4, 5, 6]);

    await wipeImageCacheDir(tempDir: tempDir);

    expect(cacheDir.existsSync(), isFalse);
  });

  test('is a no-op when the folder does not exist', () async {
    await wipeImageCacheDir(tempDir: tempDir);

    expect(tempDir.existsSync(), isTrue);
  });
}
