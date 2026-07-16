import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../models/search_category.dart';
import '../models/search_query.dart';
import '../models/thread_summary.dart';
import 'auth_service.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();

/// A tag id with its usage count, as returned by `cmd=tags`.
class PopularTag {
  final int tagId;
  final int count;

  const PopularTag({required this.tagId, required this.count});

  factory PopularTag.fromJson(Map<String, dynamic> json) {
    return PopularTag(tagId: (json['tag_id'] as num? ?? 0).toInt(), count: (json['count'] as num? ?? 0).toInt());
  }
}

class ApiService {
  static const String baseUrl = 'https://f95zone.to/sam/latest_alpha/latest_data.php';
  static String? _cachedUserAgent;

  /// Fetches threads from the f95zone latest-updates API.
  /// Endpoint behavior is documented in docs/api_mappings.md.
  ///
  /// Note: Web platforms use (query-filtered) mock data due to CORS
  /// restrictions. Mobile/desktop platforms make real API calls.
  static Future<ApiResponse> fetchThreads({
    SearchQuery query = const SearchQuery(),
    int page = 1,
    int rows = 90,
    bool fallbackToMockOnError = false,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    // On web, the F95Zone API blocks CORS requests, so use mock data
    if (kIsWeb) {
      // Simulate network delay for realistic behavior
      await Future.delayed(const Duration(milliseconds: 800));
      return filterMockData(createMockData(), query);
    }

    final queryParams = <String, String>{
      'cmd': 'list',
      ...query.toQueryParameters(page: page, rows: rows),
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final response = await _getJson(
      queryParams,
      parse: ApiResponse.fromJson,
      onError: fallbackToMockOnError ? () => filterMockData(createMockData(), query) : null,
      client: client,
      packageInfoLoader: packageInfoLoader,
    );

    if (response.data.count > 0) return response;

    // The server has custom fulltext stopwords we cannot enumerate ('sex'
    // is confirmed): any such token zeroes out a multi-word title search.
    // Retry with one token dropped at a time, shortest first.
    final searchTerm = queryParams['search'];
    final tokens = searchTerm?.split(' ').where((t) => t.isNotEmpty).toList() ?? const [];
    if (tokens.length >= 2 && tokens.length <= 4) {
      final dropOrder = List<int>.generate(tokens.length, (i) => i)
        ..sort((a, b) => tokens[a].length.compareTo(tokens[b].length));
      for (final dropIndex in dropOrder) {
        final reduced = [
          for (int i = 0; i < tokens.length; i++)
            if (i != dropIndex) tokens[i],
        ].join(' ');
        try {
          final retry = await _getJson(
            {...queryParams, 'search': reduced},
            parse: ApiResponse.fromJson,
            onError: null,
            client: client,
            packageInfoLoader: packageInfoLoader,
          );
          if (retry.data.count > 0) return retry;
        } on ApiException {
          break; // Network trouble; settle for the zero-result response.
        }
      }
    }

    return response;
  }

  /// Fetches the most-used tags for a category (`cmd=tags`), used to seed
  /// search suggestions before the user types anything.
  static Future<List<PopularTag>> fetchPopularTags({
    SearchCategory category = SearchCategory.games,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
      return _mockPopularTags();
    }

    return _getJson(
      {'cmd': 'tags', 'cat': category.apiValue},
      parse: (jsonData) {
        final items = (jsonData['msg']?['data'] as List? ?? const []);
        final tags = items.map((item) => PopularTag.fromJson(item as Map<String, dynamic>)).toList();
        tags.sort((a, b) => b.count.compareTo(a.count));
        return tags;
      },
      onError: null,
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  static Future<T> _getJson<T>(
    Map<String, String> queryParams, {
    required T Function(Map<String, dynamic>) parse,
    required T Function()? onError,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    final http.Client httpClient = client ?? http.Client();
    final PackageInfoLoader loader = packageInfoLoader ?? PackageInfo.fromPlatform;
    final bool shouldCloseClient = client == null;

    try {
      final userAgent = await _resolveUserAgent(loader);
      final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);

      final headers = {'User-Agent': userAgent, 'Accept': 'application/json'};
      // Session cookies lift the anonymous hourly rate limit and unlock
      // user-specific fields (watched/ignored) in responses.
      final cookies = AuthService.instance.cookieHeader;
      if (cookies != null) headers['Cookie'] = cookies;

      final stopwatch = Stopwatch()..start();
      final response = await httpClient.get(uri, headers: headers);
      final networkMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        stopwatch.reset();
        final parsed = parse(json.decode(response.body));
        if (kDebugMode) {
          debugPrint(
            'ApiService ${queryParams['cmd']}: network ${networkMs}ms, '
            'parse ${stopwatch.elapsedMilliseconds}ms, ${response.body.length} bytes',
          );
        }
        return parsed;
      }

      // Error bodies carry a human-readable msg (e.g. the anonymous
      // hourly rate limit) — surface it instead of just the status code.
      String detail = '${response.statusCode}';
      try {
        final body = json.decode(response.body);
        if (body is Map && body['msg'] is String) {
          detail = '${body['msg']} (HTTP ${response.statusCode})';
        }
      } catch (_) {}
      throw ApiException('Failed to load threads: $detail');
    } on ApiException catch (e) {
      if (onError != null) {
        debugPrint('ApiService recovered from ApiException: ${e.message}');
        return onError();
      }
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('ApiService error: $e\n$stackTrace');
      if (onError != null) {
        return onError();
      }
      throw ApiException('Failed to load threads: ${e.toString()}');
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  /// Versioned User-Agent shared by all f95zone requests (also used by
  /// ThreadPageService).
  static Future<String> resolveUserAgent([PackageInfoLoader? packageInfoLoader]) =>
      _resolveUserAgent(packageInfoLoader ?? PackageInfo.fromPlatform);

  static Future<String> _resolveUserAgent(PackageInfoLoader loader) async {
    if (_cachedUserAgent != null) {
      return _cachedUserAgent!;
    }

    try {
      final info = await loader();
      _cachedUserAgent = 'F95Portal/${info.version} (${info.buildNumber})';
    } catch (e) {
      debugPrint('PackageInfo fetch failed: $e');
      _cachedUserAgent = 'F95Portal/unknown';
    }

    return _cachedUserAgent!;
  }

  @visibleForTesting
  static void clearUserAgentCache() {
    _cachedUserAgent = null;
  }

  /// Applies a [SearchQuery] to mock data client-side so the web build
  /// behaves like the real API: tags AND, prefixes OR, `no*` lists exclude.
  @visibleForTesting
  static ApiResponse filterMockData(ApiResponse response, SearchQuery query) {
    final search = query.search.trim().toLowerCase();
    final creator = query.creator.trim().toLowerCase();

    final threads = response.data.threads.where((thread) {
      if (search.isNotEmpty && !thread.title.toLowerCase().contains(search)) return false;
      if (creator.isNotEmpty && !thread.creator.toLowerCase().contains(creator)) return false;
      if (query.tags.isNotEmpty) {
        final matchesTags = query.anyTags
            ? query.tags.any((tag) => thread.tags.contains(tag))
            : query.tags.every((tag) => thread.tags.contains(tag));
        if (!matchesTags) return false;
      }
      if (query.notags.any((tag) => thread.tags.contains(tag))) return false;
      if (query.prefixes.isNotEmpty && !query.prefixes.any((p) => thread.prefixes.contains(p))) return false;
      if (query.noprefixes.any((p) => thread.prefixes.contains(p))) return false;
      return true;
    }).toList();

    switch (query.sort) {
      case SortOrder.date:
        threads.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      case SortOrder.likes:
        threads.sort((a, b) => b.likes.compareTo(a.likes));
      case SortOrder.views:
        threads.sort((a, b) => b.views.compareTo(a.views));
      case SortOrder.title:
        threads.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SortOrder.rating:
        threads.sort((a, b) => b.rating.compareTo(a.rating));
    }

    return ApiResponse(
      status: response.status,
      data: ApiResponseData(threads: threads, pagination: Pagination(page: 1, total: 1), count: threads.length),
    );
  }

  static List<PopularTag> _mockPopularTags() {
    final counts = <int, int>{};
    for (final thread in createMockData().data.threads) {
      for (final tag in thread.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.entries.map((e) => PopularTag(tagId: e.key, count: e.value)).toList();
    tags.sort((a, b) => b.count.compareTo(a.count));
    return tags;
  }

  /// Creates mock data for the web build and tests. Prefix/tag IDs follow the
  /// verified vocabulary in assets/f95_metadata.json (3=Unity, 7=Ren'Py,
  /// 2=RPGM, 13=VN, 116=Godot; 18/20/22 = Completed/Onhold/Abandoned).
  static ApiResponse createMockData() {
    final mockThreads = [
      ThreadSummary(
        threadId: 35192,
        title: "SiNiSistar 2",
        creator: "HenryTaiwan",
        version: "v1.0.6",
        views: 3200000,
        likes: 528,
        prefixes: [3, 18], // Unity, Completed
        tags: [2214, 783, 392, 776], // 2d game, animated, female protagonist, side-scroller
        rating: 4.9,
        cover: "https://attachments.f95zone.to/2021/09/1418241_cover.png",
        screens: [],
        date: "3 weeks",
        watched: false,
        ignored: false,
        isNew: false,
        timestamp: 1747104420,
      ),
      ThreadSummary(
        threadId: 35193,
        title: "Hard Stuck",
        creator: "DevStudio",
        version: "v0.4 EA 4",
        views: 1000000,
        likes: 342,
        prefixes: [116], // Godot
        tags: [2214, 783, 75], // 2d game, animated, milf
        rating: 4.7,
        cover: "https://attachments.f95zone.to/2022/05/1822341_cover.png",
        screens: [],
        date: "4 days",
        watched: false,
        ignored: false,
        isNew: true,
        timestamp: 1747104420,
      ),
      ThreadSummary(
        threadId: 35194,
        title: "The Night Driver",
        creator: "NightDev",
        version: "v1.4",
        views: 3400000,
        likes: 1290,
        prefixes: [3, 20], // Unity, Onhold
        tags: [107, 173, 448], // 3dcg, male protagonist, simulator
        rating: 4.6,
        cover: "https://attachments.f95zone.to/2023/01/2341232_cover.png",
        screens: [],
        date: "2 months",
        watched: false,
        ignored: false,
        isNew: false,
        timestamp: 1747104420,
      ),
      ThreadSummary(
        threadId: 35195,
        title: "Fantasy Adventure",
        creator: "FantasyDev",
        version: "v2.1",
        views: 850000,
        likes: 425,
        prefixes: [2, 18], // RPGM, Completed
        tags: [107, 179, 162], // 3dcg, fantasy, adventure
        rating: 4.8,
        cover: "https://attachments.f95zone.to/2023/06/2756341_cover.png",
        screens: [],
        date: "1 week",
        watched: false,
        ignored: false,
        isNew: false,
        timestamp: 1747104420,
      ),
      ThreadSummary(
        threadId: 35196,
        title: "College Dreams",
        creator: "EduDev",
        version: "v0.8.2",
        views: 2100000,
        likes: 789,
        prefixes: [7], // Ren'Py
        tags: [107, 173, 254, 547], // 3dcg, male protagonist, harem, school setting
        rating: 4.5,
        cover: "https://attachments.f95zone.to/2023/08/2891234_cover.png",
        screens: [],
        date: "5 days",
        watched: false,
        ignored: false,
        isNew: true,
        timestamp: 1747104420,
      ),
      ThreadSummary(
        threadId: 35197,
        title: "Cyber City",
        creator: "CyberStudio",
        version: "v1.2 Final",
        views: 4500000,
        likes: 1456,
        prefixes: [13, 7, 18], // VN, Ren'Py, Completed
        tags: [107, 141, 392], // 3dcg, sci-fi, female protagonist
        rating: 4.7,
        cover: "https://attachments.f95zone.to/2023/09/2934567_cover.png",
        screens: [],
        date: "6 weeks",
        watched: false,
        ignored: false,
        isNew: false,
        timestamp: 1747104420,
      ),
      ThreadSummary(
        threadId: 35198,
        title: "Summer Memories",
        creator: "SummerDev",
        version: "v1.0",
        views: 1800000,
        likes: 634,
        prefixes: [2, 22], // RPGM, Abandoned
        tags: [107, 330, 225], // 3dcg, romance, pregnancy
        rating: 4.4,
        cover: "https://attachments.f95zone.to/2023/10/3045678_cover.png",
        screens: [],
        date: "3 months",
        watched: false,
        ignored: false,
        isNew: false,
        timestamp: 1747104420,
      ),
    ];

    return ApiResponse(
      status: "ok",
      data: ApiResponseData(
        threads: mockThreads,
        // total is the page count; the 7 fixtures are a single page.
        pagination: Pagination(page: 1, total: 1),
        count: mockThreads.length,
      ),
    );
  }
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
