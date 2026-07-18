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

  group('trimImageCacheDir', () {
    late Directory cacheDir;

    File writeFile(String name, DateTime modified, {int size = 400}) {
      final file = File(p.join(cacheDir.path, name))..writeAsBytesSync(List.filled(size, 0));
      file.setLastModifiedSync(modified);
      return file;
    }

    setUp(() {
      cacheDir = Directory(p.join(tempDir.path, 'libCachedImageData'))..createSync();
    });

    test('deletes oldest-modified files first until the folder fits the budget', () async {
      final oldest = writeFile('oldest.avif', DateTime(2026, 1, 1));
      final middle = writeFile('middle.avif', DateTime(2026, 2, 1));
      final newest = writeFile('newest.avif', DateTime(2026, 3, 1));

      await trimImageCacheDir(maxBytes: 800, tempDir: tempDir);

      expect(oldest.existsSync(), isFalse);
      expect(middle.existsSync(), isTrue);
      expect(newest.existsSync(), isTrue);
    });

    test('leaves everything alone while under the budget', () async {
      final a = writeFile('a.avif', DateTime(2026, 1, 1));
      final b = writeFile('b.avif', DateTime(2026, 2, 1));

      await trimImageCacheDir(maxBytes: 1000, tempDir: tempDir);

      expect(a.existsSync(), isTrue);
      expect(b.existsSync(), isTrue);
    });

    test('is a no-op when the folder does not exist', () async {
      cacheDir.deleteSync();

      await trimImageCacheDir(maxBytes: 100, tempDir: tempDir);

      expect(cacheDir.existsSync(), isFalse);
    });
  });
}
