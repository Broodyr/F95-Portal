import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/thread_page.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'thread_page_parser.dart';

/// Fetches and parses thread first posts, with a small in-memory cache so
/// reopening a details modal is instant.
class ThreadPageService {
  static const int _cacheLimit = 20;
  static final Map<int, ThreadPage> _cache = {};

  static Future<ThreadPage> fetch(
    int threadId, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    final cached = _cache[threadId];
    if (cached != null) return cached;

    if (kIsWeb) {
      // CORS blocks the real page on web; serve a representative mock.
      await Future.delayed(const Duration(milliseconds: 500));
      return createMockThreadPage(threadId);
    }

    final http.Client httpClient = client ?? http.Client();
    final bool shouldCloseClient = client == null;

    try {
      final headers = {
        'User-Agent': await ApiService.resolveUserAgent(packageInfoLoader),
        'Accept': 'text/html',
      };
      final cookies = AuthService.instance.cookieHeader;
      if (cookies != null) headers['Cookie'] = cookies;

      final uri = Uri.parse('https://f95zone.to/threads/$threadId/');
      final response = await httpClient.get(uri, headers: headers);

      if (response.statusCode != 200) {
        throw ApiException('Failed to load thread page: ${response.statusCode}');
      }

      final page = parseThreadPage(response.body, threadId: threadId);
      _store(threadId, page);
      return page;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load thread page: $e');
    } finally {
      if (shouldCloseClient) httpClient.close();
    }
  }

  static void _store(int threadId, ThreadPage page) {
    if (_cache.length >= _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    _cache[threadId] = page;
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// Representative page for the web build and tests.
  static ThreadPage createMockThreadPage(int threadId) {
    return ThreadPage(
      threadId: threadId,
      metaFields: const [
        MetaField(label: 'Developer', value: 'MockDev'),
        MetaField(label: 'Version', value: '0.9.1'),
        MetaField(label: 'OS', value: 'Windows, Linux'),
        MetaField(label: 'Censored', value: 'No'),
        MetaField(label: 'Language', value: 'English'),
      ],
      overview: 'A representative mock thread page used on the web build, '
          'where CORS blocks fetching the real forum page.',
      spoilers: const [
        SpoilerSection(title: 'Changelog', content: 'v0.9.1\n- Fixed things\n- Added other things'),
        SpoilerSection(title: 'Developer Notes', content: 'Thanks for playing!'),
      ],
      downloads: const DownloadsSection(
        platforms: [
          DownloadGroup(
            label: 'Win',
            links: [
              DownloadLink(host: 'MEGA', url: 'https://example.com/win-mega'),
              DownloadLink(host: 'PIXELDRAIN', url: 'https://example.com/win-pd'),
            ],
          ),
          DownloadGroup(
            label: 'Linux',
            links: [DownloadLink(host: 'MEGA', url: 'https://example.com/linux-mega')],
          ),
        ],
        extras: [
          DownloadGroup(
            label: 'Extras',
            links: [DownloadLink(host: 'Full save', url: 'https://example.com/save')],
          ),
        ],
      ),
    );
  }
}
