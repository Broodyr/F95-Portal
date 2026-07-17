import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_query.dart';

/// Overall text size. [scale] feeds the app-wide text scaler (AppTextScale);
/// [anchored] pins the few elements that are already big enough at their
/// base size.
enum FontSizeOption {
  small(1.0),
  medium(1.08),
  large(1.16);

  const FontSizeOption(this.scale);

  /// App-wide text scale multiplier: roughly +1pt of body text and +2pt of
  /// title text per step up. Small is the app's original sizing.
  final double scale;

  /// Pre-scale font size for text that should render at [base] regardless of
  /// the app scale, except 1pt smaller on small (where everything else
  /// shrinks too). Dividing by [scale] cancels the app's own scaler while
  /// leaving the OS accessibility factor intact.
  double anchored(double base) => (this == small ? base - 1 : base) / scale;
}

@immutable
class AppSettings {
  /// Baseline query for the Browse tab: applied at startup and when the
  /// active-filters bar is cleared.
  final SearchQuery defaultQuery;

  /// Blur all covers/screenshots (privacy mode).
  final bool sfwBlur;

  /// Backdrop blur behind pills/sheets; disable on low-end phones.
  final bool glassEffects;

  /// Overall text size; small is the app's original sizing.
  final FontSizeOption fontSize;

  /// Flutter's performance overlay (only effective in debug/profile builds).
  final bool showPerfOverlay;

  /// Most-recently-used include tags, newest first.
  final List<int> recentTags;

  static const int maxRecentTags = 30;

  const AppSettings({
    this.defaultQuery = const SearchQuery(),
    this.sfwBlur = false,
    this.glassEffects = true,
    this.fontSize = FontSizeOption.medium,
    this.showPerfOverlay = false,
    this.recentTags = const [],
  });

  AppSettings copyWith({
    SearchQuery? defaultQuery,
    bool? sfwBlur,
    bool? glassEffects,
    FontSizeOption? fontSize,
    bool? showPerfOverlay,
    List<int>? recentTags,
  }) {
    return AppSettings(
      defaultQuery: defaultQuery ?? this.defaultQuery,
      sfwBlur: sfwBlur ?? this.sfwBlur,
      glassEffects: glassEffects ?? this.glassEffects,
      fontSize: fontSize ?? this.fontSize,
      showPerfOverlay: showPerfOverlay ?? this.showPerfOverlay,
      recentTags: recentTags ?? this.recentTags,
    );
  }

  Map<String, dynamic> toJson() => {
    'defaultQuery': defaultQuery.toJson(),
    'sfwBlur': sfwBlur,
    'glassEffects': glassEffects,
    'fontSize': fontSize.name,
    'showPerfOverlay': showPerfOverlay,
    'recentTags': recentTags,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      defaultQuery: json['defaultQuery'] is Map<String, dynamic>
          ? SearchQuery.fromJson(json['defaultQuery'])
          : const SearchQuery(),
      sfwBlur: json['sfwBlur'] ?? false,
      glassEffects: json['glassEffects'] ?? true,
      fontSize: FontSizeOption.values.asNameMap()[json['fontSize']] ?? FontSizeOption.medium,
      showPerfOverlay: json['showPerfOverlay'] ?? false,
      // A 'suggestionSource' key may linger in persisted JSON from when the
      // suggestion source was a user setting; it is intentionally ignored.
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
