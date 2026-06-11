import 'package:flutter/foundation.dart';

import 'search_category.dart';

/// Sort orders accepted by the latest-updates API (docs/api_mappings.md);
/// unknown values silently fall back to date server-side, so stick to these.
enum SortOrder { date, likes, views, title, rating }

extension SortOrderX on SortOrder {
  String get apiValue => name;

  String get displayLabel => name[0].toUpperCase() + name.substring(1);
}

/// Immutable description of one feed/search request. Tag filters are ANDed
/// by the server while prefix filters are ORed; the `no*` lists exclude
/// threads matching any entry.
@immutable
class SearchQuery {
  final SearchCategory category;

  /// Title search (`search=` parameter).
  final String search;

  /// Developer/creator search (`creator=` parameter).
  final String creator;

  final List<int> tags;
  final List<int> notags;
  final List<int> prefixes;
  final List<int> noprefixes;
  final SortOrder sort;

  /// Only show threads updated within this many days (`date=` parameter);
  /// null means no limit. The API accepts arbitrary day counts.
  final int? dateDays;

  /// When true, include-tags match ANY instead of ALL (`tagtype=or`).
  /// Has no effect on exclusions, which are always any-match.
  final bool anyTags;

  /// The API silently discards ALL tag filters when more than 10 are sent,
  /// so the UI must cap include and exclude tags at this many each.
  static const int maxTagsPerDirection = 10;

  const SearchQuery({
    this.category = SearchCategory.games,
    this.search = '',
    this.creator = '',
    this.tags = const [],
    this.notags = const [],
    this.prefixes = const [],
    this.noprefixes = const [],
    this.sort = SortOrder.date,
    this.dateDays,
    this.anyTags = false,
  });

  bool get hasActiveFilters =>
      search.trim().isNotEmpty ||
      creator.trim().isNotEmpty ||
      tags.isNotEmpty ||
      notags.isNotEmpty ||
      prefixes.isNotEmpty ||
      noprefixes.isNotEmpty ||
      sort != SortOrder.date ||
      dateDays != null;

  Map<String, String> toQueryParameters({required int page, required int rows}) {
    final params = <String, String>{
      'cat': category.apiValue,
      'page': page.toString(),
      'sort': sort.apiValue,
      'rows': rows.toString(),
    };

    final trimmedSearch = search.trim();
    if (trimmedSearch.isNotEmpty) params['search'] = trimmedSearch;
    final trimmedCreator = creator.trim();
    if (trimmedCreator.isNotEmpty) params['creator'] = trimmedCreator;
    if (dateDays != null) params['date'] = dateDays.toString();
    if (anyTags && tags.isNotEmpty) params['tagtype'] = 'or';

    void addArray(String name, List<int> values) {
      for (int i = 0; i < values.length; i++) {
        params['$name[$i]'] = values[i].toString();
      }
    }

    addArray('tags', tags);
    addArray('notags', notags);
    addArray('prefixes', prefixes);
    addArray('noprefixes', noprefixes);

    return params;
  }

  /// Adds [tagId] as an include tag (removing it from the exclusions if
  /// present). Returns this instance unchanged when the tag is already
  /// included or the include list is at the API cap.
  SearchQuery withTagAdded(int tagId) {
    if (tags.contains(tagId) || tags.length >= maxTagsPerDirection) return this;
    return copyWith(
      tags: [...tags, tagId],
      notags: [for (final t in notags) if (t != tagId) t],
    );
  }

  /// A fresh search for [tagId] only, keeping just the category.
  SearchQuery replacedWithTag(int tagId) => SearchQuery(category: category, tags: [tagId]);

  static const Object _unset = Object();

  SearchQuery copyWith({
    SearchCategory? category,
    String? search,
    String? creator,
    List<int>? tags,
    List<int>? notags,
    List<int>? prefixes,
    List<int>? noprefixes,
    SortOrder? sort,
    Object? dateDays = _unset,
    bool? anyTags,
  }) {
    return SearchQuery(
      category: category ?? this.category,
      search: search ?? this.search,
      creator: creator ?? this.creator,
      tags: tags ?? this.tags,
      notags: notags ?? this.notags,
      prefixes: prefixes ?? this.prefixes,
      noprefixes: noprefixes ?? this.noprefixes,
      sort: sort ?? this.sort,
      dateDays: identical(dateDays, _unset) ? this.dateDays : dateDays as int?,
      anyTags: anyTags ?? this.anyTags,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SearchQuery &&
        other.category == category &&
        other.search == search &&
        other.creator == creator &&
        listEquals(other.tags, tags) &&
        listEquals(other.notags, notags) &&
        listEquals(other.prefixes, prefixes) &&
        listEquals(other.noprefixes, noprefixes) &&
        other.sort == sort &&
        other.dateDays == dateDays &&
        other.anyTags == anyTags;
  }

  @override
  int get hashCode => Object.hash(
    category,
    search,
    creator,
    Object.hashAll(tags),
    Object.hashAll(notags),
    Object.hashAll(prefixes),
    Object.hashAll(noprefixes),
    sort,
    dateDays,
    anyTags,
  );
}
