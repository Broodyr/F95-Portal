import 'dart:io';

import 'package:f95_portal/models/f95_metadata.dart';

/// Loads the real bundled metadata from disk (tests run on the Dart VM with
/// the project root as the working directory) and installs it as the
/// process-wide instance so widgets/utilities under test can resolve names.
F95Metadata loadAndInstallMetadata() {
  final raw = File('assets/f95_metadata.json').readAsStringSync();
  final metadata = F95Metadata.fromJsonString(raw);
  F95Metadata.instance = metadata;
  return metadata;
}
