import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'search_category.dart';

/// A single prefix definition from the F95Zone vocabulary
/// (see docs/api_mappings.md and assets/f95_metadata.json).
class F95Prefix {
  final int id;
  final String name;
  final int groupId;
  final String groupName;

  const F95Prefix({required this.id, required this.name, required this.groupId, required this.groupName});

  /// Group 4 holds the Completed/Onhold/Abandoned status prefixes in every category.
  bool get isStatus => groupId == F95Metadata.statusGroupId;
}

/// Parsed prefix/tag vocabulary captured from the site's `latestUpdates`
/// globals. Loaded once at startup from the bundled asset.
class F95Metadata {
  static const int statusGroupId = 4;
  static const String assetPath = 'assets/f95_metadata.json';

  final Map<SearchCategory, List<F95Prefix>> _prefixes;
  final Map<int, String> tagNames;
  Map<String, int>? _tagIdsByName;

  F95Metadata({required Map<SearchCategory, List<F95Prefix>> prefixes, required this.tagNames})
    : _prefixes = prefixes;

  static F95Metadata? _instance;

  /// The process-wide vocabulary; populated by [load] in main() or assigned
  /// directly in tests.
  static F95Metadata get instance {
    final loaded = _instance;
    if (loaded == null) {
      throw StateError('F95Metadata not loaded. Await F95Metadata.load() before runApp().');
    }
    return loaded;
  }

  static set instance(F95Metadata value) => _instance = value;

  static void reset() => _instance = null;

  static Future<F95Metadata> load({AssetBundle? bundle}) async {
    final raw = await (bundle ?? rootBundle).loadString(assetPath);
    return _instance = F95Metadata.fromJsonString(raw);
  }

  factory F95Metadata.fromJsonString(String raw) => F95Metadata.fromJson(json.decode(raw) as Map<String, dynamic>);

  factory F95Metadata.fromJson(Map<String, dynamic> jsonMap) {
    final prefixesJson = jsonMap['prefixes'] as Map<String, dynamic>? ?? const {};
    final prefixes = <SearchCategory, List<F95Prefix>>{};
    for (final category in SearchCategory.values) {
      final groups = prefixesJson[category.apiValue] as List? ?? const [];
      final flattened = <F95Prefix>[];
      for (final group in groups) {
        final int groupId = group['id'] ?? 0;
        final String groupName = group['name'] ?? '';
        for (final prefix in group['prefixes'] as List? ?? const []) {
          flattened.add(
            F95Prefix(id: prefix['id'] ?? 0, name: prefix['name'] ?? '', groupId: groupId, groupName: groupName),
          );
        }
      }
      prefixes[category] = List.unmodifiable(flattened);
    }

    final tagsJson = jsonMap['tags'] as Map<String, dynamic>? ?? const {};
    final tags = <int, String>{
      for (final entry in tagsJson.entries)
        if (int.tryParse(entry.key) != null) int.parse(entry.key): entry.value as String,
    };

    return F95Metadata(prefixes: prefixes, tagNames: Map.unmodifiable(tags));
  }

  List<F95Prefix> prefixesFor(SearchCategory category) => _prefixes[category] ?? const [];

  F95Prefix? prefixById(SearchCategory category, int id) {
    for (final prefix in prefixesFor(category)) {
      if (prefix.id == id) return prefix;
    }
    return null;
  }

  String? tagName(int id) => tagNames[id];

  /// Inverse of [tagNames], built lazily for autocomplete lookups.
  Map<String, int> get tagIdsByName =>
      _tagIdsByName ??= Map.unmodifiable({for (final entry in tagNames.entries) entry.value: entry.key});
}
