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
