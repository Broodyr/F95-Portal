/// Categories the latest-updates API actually serves. `mods` is accepted by
/// the endpoint but always returns zero results, so it is intentionally absent.
enum SearchCategory { games, comics, animations, assets }

extension SearchCategoryX on SearchCategory {
  /// Value expected by the remote API.
  String get apiValue => name;

  /// Human readable label for display.
  String get displayLabel {
    final value = name;
    return value[0].toUpperCase() + value.substring(1);
  }

  /// Whether threads in this category should include version pills
  bool get hasVersions => this != SearchCategory.comics && this != SearchCategory.assets;
}
