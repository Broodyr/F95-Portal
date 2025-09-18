enum SearchCategory { games, comics, animations, assets, mods }

extension SearchCategoryX on SearchCategory {
  /// Value expected by the remote API.
  String get apiValue => name;

  /// Human readable label for display.
  String get displayLabel {
    final value = name;
    return value[0].toUpperCase() + value.substring(1);
  }
}
