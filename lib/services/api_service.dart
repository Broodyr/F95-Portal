import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../models/thread_summary.dart';
import '../models/search_category.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();

class ApiService {
  static const String baseUrl = 'https://f95zone.to/sam/latest_alpha/latest_data.php';
  static String? _cachedUserAgent;

  /// Fetches threads from the f95zone API
  /// Parameters match the sample endpoint from notes.txt
  ///
  /// Note: Web platforms will use mock data due to CORS restrictions.
  /// Mobile/desktop platforms will attempt real API calls.
  static Future<ApiResponse> fetchThreads({
    String cmd = 'list',
    SearchCategory category = SearchCategory.games,
    int page = 1,
    List<int> noprefixes = const [2, 7, 13],
    List<int> tags = const [191],
    List<int> notags = const [173, 174, 324, 522],
    String sort = 'date',
    int rows = 90,
    bool fallbackToMockOnError = false,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    // On web, F95Zone API blocks CORS requests, so use mock data
    if (kIsWeb) {
      // Simulate network delay for realistic behavior
      await Future.delayed(const Duration(milliseconds: 800));
      return createMockData();
    }

    final http.Client httpClient = client ?? http.Client();
    final PackageInfoLoader loader = packageInfoLoader ?? PackageInfo.fromPlatform;
    final bool shouldCloseClient = client == null;

    try {
      final userAgent = await _resolveUserAgent(loader);

      // Build query parameters
      final Map<String, String> queryParams = {
        'cmd': cmd,
        'cat': category.apiValue,
        'page': page.toString(),
        'sort': sort,
        'rows': rows.toString(),
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      };

      // Add array parameters
      for (int i = 0; i < noprefixes.length; i++) {
        queryParams['noprefixes[$i]'] = noprefixes[i].toString();
      }
      for (int i = 0; i < tags.length; i++) {
        queryParams['tags[$i]'] = tags[i].toString();
      }
      for (int i = 0; i < notags.length; i++) {
        queryParams['notags[$i]'] = notags[i].toString();
      }

      final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);

      final response = await httpClient.get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ApiResponse.fromJson(jsonData);
      }

      throw ApiException('Failed to load threads: ${response.statusCode}');
    } on ApiException catch (e) {
      if (fallbackToMockOnError) {
        debugPrint('ApiService.fetchThreads recovered from ApiException: ${e.message}');
        return createMockData();
      }
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('ApiService.fetchThreads error: $e\n$stackTrace');
      if (fallbackToMockOnError) {
        return createMockData();
      }
      throw ApiException('Failed to load threads: ${e.toString()}');
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

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

  /// Creates mock data for testing UI before API integration
  /// Enhanced with diverse threads showing different engines and features
  static ApiResponse createMockData() {
    final mockThreads = [
      ThreadSummary(
        threadId: 35192,
        title: "SiNiSistar 2",
        creator: "HenryTaiwan",
        version: "v1.0.6",
        views: 3200000,
        likes: 528,
        prefixes: [3, 18], // includes 18 for completion flag
        tags: [107, 130, 191],
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
        prefixes: [3], // Ren'Py thread, no completion flag
        tags: [130, 191],
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
        prefixes: [8], // Unity thread
        tags: [107, 191],
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
        prefixes: [7, 18], // RPGM thread with completion flag
        tags: [107, 191],
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
        prefixes: [3], // Ren'Py thread
        tags: [130, 191],
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
        prefixes: [8, 18], // Unity thread with completion flag
        tags: [107, 191],
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
        prefixes: [7, 18], // RPGM thread with completion flag
        tags: [107, 130, 191],
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
        pagination: Pagination(page: 1, total: 7),
        count: 1247, // More realistic total count
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
