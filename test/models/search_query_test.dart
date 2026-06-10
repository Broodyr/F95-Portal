import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchQuery.toQueryParameters', () {
    test('defaults produce an unfiltered list request', () {
      final params = const SearchQuery().toQueryParameters(page: 1, rows: 90);

      expect(params['cat'], 'games');
      expect(params['page'], '1');
      expect(params['rows'], '90');
      expect(params['sort'], 'date');
      expect(params.containsKey('search'), isFalse);
      expect(params.containsKey('creator'), isFalse);
      expect(params.keys.where((k) => k.startsWith('tags')), isEmpty);
      expect(params.keys.where((k) => k.startsWith('notags')), isEmpty);
      expect(params.keys.where((k) => k.startsWith('prefixes')), isEmpty);
      expect(params.keys.where((k) => k.startsWith('noprefixes')), isEmpty);
    });

    test('maps every filter to indexed array parameters', () {
      final query = const SearchQuery(
        category: SearchCategory.comics,
        search: 'goblin',
        creator: 'SomeDev',
        tags: [225, 103],
        notags: [258],
        prefixes: [7, 3],
        noprefixes: [22],
        sort: SortOrder.likes,
      );

      final params = query.toQueryParameters(page: 2, rows: 30);

      expect(params['cat'], 'comics');
      expect(params['page'], '2');
      expect(params['rows'], '30');
      expect(params['sort'], 'likes');
      expect(params['search'], 'goblin');
      expect(params['creator'], 'SomeDev');
      expect(params['tags[0]'], '225');
      expect(params['tags[1]'], '103');
      expect(params['notags[0]'], '258');
      expect(params['prefixes[0]'], '7');
      expect(params['prefixes[1]'], '3');
      expect(params['noprefixes[0]'], '22');
    });

    test('trims and omits whitespace-only search terms', () {
      final params = const SearchQuery(search: '   ', creator: ' dev ').toQueryParameters(page: 1, rows: 90);

      expect(params.containsKey('search'), isFalse);
      expect(params['creator'], 'dev');
    });
  });

  group('SearchQuery equality', () {
    test('value equality covers lists', () {
      const a = SearchQuery(tags: [1, 2], sort: SortOrder.views);
      const b = SearchQuery(tags: [1, 2], sort: SortOrder.views);
      const c = SearchQuery(tags: [2, 1], sort: SortOrder.views);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only the given fields', () {
      const original = SearchQuery(search: 'a', tags: [1]);
      final copy = original.copyWith(search: 'b');

      expect(copy.search, 'b');
      expect(copy.tags, [1]);
      expect(copy.category, SearchCategory.games);
    });
  });

  group('SearchQuery.hasActiveFilters', () {
    test('false for defaults, true with any filter', () {
      expect(const SearchQuery().hasActiveFilters, isFalse);
      expect(const SearchQuery(search: 'x').hasActiveFilters, isTrue);
      expect(const SearchQuery(notags: [1]).hasActiveFilters, isTrue);
      expect(const SearchQuery(sort: SortOrder.rating).hasActiveFilters, isTrue);
    });
  });

  group('SortOrder', () {
    test('apiValue and displayLabel', () {
      expect(SortOrder.date.apiValue, 'date');
      expect(SortOrder.likes.displayLabel, 'Likes');
      expect(SortOrder.values, hasLength(5));
    });
  });
}
