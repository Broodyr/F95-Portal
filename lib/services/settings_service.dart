import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_query.dart';

/// What the search modal suggests while the field is empty.
enum SuggestionSource { popular, recent }

@immutable
class AppSettings {
  /// Baseline query for the Browse tab: applied at startup and when the
  /// active-filters bar is cleared.
  final SearchQuery defaultQuery;

  /// Blur all covers/screenshots (privacy mode).
  final bool sfwBlur;

  final SuggestionSource suggestionSource;

  /// Most-recently-used include tags, newest first.
  final List<int> recentTags;

  static const int maxRecentTags = 30;

  const AppSettings({
    this.defaultQuery = const SearchQuery(),
    this.sfwBlur = false,
    this.suggestionSource = SuggestionSource.popular,
    this.recentTags = const [],
  });

  AppSettings copyWith({
    SearchQuery? defaultQuery,
    bool? sfwBlur,
    SuggestionSource? suggestionSource,
    List<int>? recentTags,
  }) {
    return AppSettings(
      defaultQuery: defaultQuery ?? this.defaultQuery,
      sfwBlur: sfwBlur ?? this.sfwBlur,
      suggestionSource: suggestionSource ?? this.suggestionSource,
      recentTags: recentTags ?? this.recentTags,
    );
  }

  Map<String, dynamic> toJson() => {
    'defaultQuery': defaultQuery.toJson(),
    'sfwBlur': sfwBlur,
    'suggestionSource': suggestionSource.name,
    'recentTags': recentTags,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      defaultQuery: json['defaultQuery'] is Map<String, dynamic>
          ? SearchQuery.fromJson(json['defaultQuery'])
          : const SearchQuery(),
      sfwBlur: json['sfwBlur'] ?? false,
      suggestionSource: SuggestionSource.values.asNameMap()[json['suggestionSource']] ?? SuggestionSource.popular,
      recentTags: [
        for (final tag in json['recentTags'] as List? ?? const [])
          if (tag is num) tag.toInt(),
      ],
    );
  }
}

/// Persistence backend; shared_preferences in the app, in-memory in tests.
abstract class SettingsStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPrefsSettingsStorage implements SettingsStorage {
  static const String _key = 'app_settings';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async => (await SharedPreferences.getInstance()).setString(_key, value);
}

class SettingsService extends ChangeNotifier {
  static SettingsService instance = SettingsService(SharedPrefsSettingsStorage());

  final SettingsStorage _storage;
  AppSettings _settings = const AppSettings();

  SettingsService(this._storage);

  AppSettings get settings => _settings;

  Future<void> load() async {
    try {
      final raw = await _storage.read();
      if (raw == null) return;
      _settings = AppSettings.fromJson(json.decode(raw) as Map<String, dynamic>);
      notifyListeners();
    } catch (e) {
      debugPrint('SettingsService.load failed: $e');
      _settings = const AppSettings();
    }
  }

  Future<void> update(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _storage.write(json.encode(settings.toJson()));
  }

  /// Moves [tags] to the front of the recently-used list.
  Future<void> recordTagUse(List<int> tags) async {
    if (tags.isEmpty) return;
    final updated = [
      ...tags,
      for (final tag in _settings.recentTags)
        if (!tags.contains(tag)) tag,
    ].take(AppSettings.maxRecentTags).toList();
    await update(_settings.copyWith(recentTags: updated));
  }
}
