import 'dart:convert';

import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/in_memory_cookie_storage.dart';

PackageInfo _packageInfo() =>
    PackageInfo(appName: 'F95 Portal', packageName: 'com.example.f95portal', version: '1.0.0', buildNumber: '42');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiService.clearUserAgentCache();
  });

  group('ApiService.createMockData', () {
    test('returns expected structure', () {
      final response = ApiService.createMockData();

      expect(response.status, 'ok');
      expect(response.data.threads, isNotEmpty);
      expect(response.data.pagination.page, 1);
      expect(response.data.count, greaterThan(0));
    });

    test('mock threads use real engine prefixes, not personal tag filters', () {
      final response = ApiService.createMockData();

      for (final thread in response.data.threads) {
        expect(thread.prefixes, isNotEmpty, reason: '${thread.title} has no prefixes');
      }
      // Tag 191 (futa/trans) was a leftover personal filter baked into every
      // mock thread; the fixtures should no longer all carry it.
      expect(response.data.threads.every((t) => t.tags.contains(191)), isFalse);
    });
  });

  group('ApiService.filterMockData', () {
    test('filters by title search, case-insensitively', () {
      final all = ApiService.createMockData();
      final result = ApiService.filterMockData(all, const SearchQuery(search: 'sinis'));

      expect(result.data.threads, hasLength(1));
      expect(result.data.threads.single.title, 'SiNiSistar 2');
      expect(result.data.count, 1);
    });

    test('tag filters AND together; notags exclude', () {
      final all = ApiService.createMockData();

      final withTag = ApiService.filterMockData(all, const SearchQuery(tags: [107]));
      expect(withTag.data.threads, isNotEmpty);
      expect(withTag.data.threads.every((t) => t.tags.contains(107)), isTrue);

      final excluded = ApiService.filterMockData(all, const SearchQuery(notags: [107]));
      expect(excluded.data.threads.every((t) => !t.tags.contains(107)), isTrue);
    });

    test('anyTags switches tag matching to OR', () {
      final all = ApiService.createMockData();
      // 2214 (2d game) and 179 (fantasy) never co-occur in the fixtures.
      const both = SearchQuery(tags: [2214, 179]);

      expect(ApiService.filterMockData(all, both).data.threads, isEmpty);

      final any = ApiService.filterMockData(all, both.copyWith(anyTags: true));
      expect(any.data.threads, isNotEmpty);
      expect(any.data.threads.every((t) => t.tags.contains(2214) || t.tags.contains(179)), isTrue);
    });

    test('prefix filters OR together', () {
      final all = ApiService.createMockData();
      final result = ApiService.filterMockData(all, const SearchQuery(prefixes: [7, 116]));

      expect(result.data.threads, isNotEmpty);
      expect(result.data.threads.every((t) => t.prefixes.contains(7) || t.prefixes.contains(116)), isTrue);
    });

    test('sorts by likes descending', () {
      final all = ApiService.createMockData();
      final result = ApiService.filterMockData(all, const SearchQuery(sort: SortOrder.likes));

      final likes = result.data.threads.map((t) => t.likes).toList();
      final sorted = [...likes]..sort((a, b) => b.compareTo(a));
      expect(likes, sorted);
    });
  });

  group('ApiService.fetchThreads', () {
    test('sends query parameters from the SearchQuery', () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        final body = jsonEncode({
          'status': 'ok',
          'msg': {
            'data': [
              {'thread_id': 1, 'title': 'From API'},
            ],
            'pagination': {'page': 2, 'total': 5},
            'count': 100,
          },
        });
        return http.Response(body, 200, headers: {'content-type': 'application/json'});
      });

      final response = await ApiService.fetchThreads(
        query: const SearchQuery(
          category: SearchCategory.comics,
          search: 'goblin',
          creator: 'Dev',
          tags: [225],
          noprefixes: [22],
          sort: SortOrder.views,
        ),
        page: 2,
        rows: 30,
        client: client,
        packageInfoLoader: () async => _packageInfo(),
      );

      expect(response.data.threads.single.title, 'From API');
      expect(requested.queryParameters['cmd'], 'list');
      expect(requested.queryParameters['cat'], 'comics');
      expect(requested.queryParameters['page'], '2');
      expect(requested.queryParameters['rows'], '30');
      expect(requested.queryParameters['sort'], 'views');
      expect(requested.queryParameters['search'], 'goblin');
      expect(requested.queryParameters['creator'], 'Dev');
      expect(requested.queryParameters['tags[0]'], '225');
      expect(requested.queryParameters['noprefixes[0]'], '22');
      expect(requested.queryParameters.keys.where((k) => k.startsWith('notags')), isEmpty);
    });

    test('defaults send no filter parameters', () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'msg': {
              'data': [],
              'pagination': {'page': 1, 'total': 0},
              'count': 0,
            },
          }),
          200,
        );
      });

      await ApiService.fetchThreads(client: client, packageInfoLoader: () async => _packageInfo());

      expect(requested.queryParameters['cat'], 'games');
      expect(requested.queryParameters.keys.where((k) => k.contains('tags') || k.contains('prefixes')), isEmpty);
      expect(requested.queryParameters.containsKey('search'), isFalse);
    });

    test('sets versioned user agent and caches it', () async {
      int loaderCalls = 0;
      loader() async {
        loaderCalls++;
        return _packageInfo();
      }

      final client = MockClient((request) async {
        expect(request.headers['User-Agent'], 'F95Portal/1.0.0 (42)');
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'msg': {
              'data': [],
              'pagination': {'page': 1, 'total': 0},
              'count': 0,
            },
          }),
          200,
        );
      });

      await ApiService.fetchThreads(client: client, packageInfoLoader: loader);
      await ApiService.fetchThreads(client: client, packageInfoLoader: loader);

      expect(loaderCalls, 1);
    });

    test('returns mock data when fallback enabled', () async {
      final client = MockClient((_) async => http.Response('error', 500));

      final response = await ApiService.fetchThreads(
        client: client,
        fallbackToMockOnError: true,
        packageInfoLoader: () async => _packageInfo(),
      );

      expect(response.status, 'ok');
      expect(response.data.threads, isNotEmpty);
    });

    test('throws ApiException when fallback disabled', () async {
      final client = MockClient((_) async => http.Response('error', 500));

      expect(
        () => ApiService.fetchThreads(client: client, packageInfoLoader: () async => _packageInfo()),
        throwsA(isA<ApiException>()),
      );
    });

    test('attaches session cookies when logged in, none when logged out', () async {
      final previous = AuthService.instance;
      addTearDown(() => AuthService.instance = previous);

      final requestCookies = <String?>[];
      final client = MockClient((request) async {
        requestCookies.add(request.headers['Cookie']);
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'msg': {
              'data': [],
              'pagination': {'page': 1, 'total': 0},
              'count': 0,
            },
          }),
          200,
        );
      });

      AuthService.instance = AuthService(InMemoryCookieStorage());
      await ApiService.fetchThreads(client: client, packageInfoLoader: () async => _packageInfo());

      await AuthService.instance.saveCookies({'xf_user': 'tok', 'xf_session': 's'});
      await ApiService.fetchThreads(client: client, packageInfoLoader: () async => _packageInfo());

      expect(requestCookies, [null, 'xf_user=tok; xf_session=s']);
    });

    test('surfaces the server error message from non-200 JSON bodies', () {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'status': 'error', 'msg': 'Anonymous users have a limited amount of requests per hour'}),
          429,
        ),
      );

      expect(
        () => ApiService.fetchThreads(client: client, packageInfoLoader: () async => _packageInfo()),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', contains('Anonymous users')),
        ),
      );
    });

    test('wraps unexpected exceptions in ApiException', () async {
      final client = MockClient((_) async => throw StateError('boom'));

      expect(
        () => ApiService.fetchThreads(client: client, packageInfoLoader: () async => _packageInfo()),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });

  group('ApiService.fetchPopularTags', () {
    test('parses tag ids and counts', () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'msg': {
              'data': [
                {'tag_id': 2214, 'count': 6268},
                {'tag_id': 1507, 'count': 13619},
              ],
            },
          }),
          200,
        );
      });

      final tags = await ApiService.fetchPopularTags(
        category: SearchCategory.comics,
        client: client,
        packageInfoLoader: () async => _packageInfo(),
      );

      expect(requested.queryParameters['cmd'], 'tags');
      expect(requested.queryParameters['cat'], 'comics');
      expect(tags, hasLength(2));
      // Sorted by usage count, most popular first.
      expect(tags.first.tagId, 1507);
      expect(tags.first.count, 13619);
      expect(tags.last.tagId, 2214);
    });

    test('throws ApiException on HTTP failure', () async {
      final client = MockClient((_) async => http.Response('nope', 500));

      expect(
        () => ApiService.fetchPopularTags(client: client, packageInfoLoader: () async => _packageInfo()),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
