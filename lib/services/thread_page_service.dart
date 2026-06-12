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

  static Future<ThreadPage> fetch(int threadId, {http.Client? client, PackageInfoLoader? packageInfoLoader}) async {
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
      final headers = {'User-Agent': await ApiService.resolveUserAgent(packageInfoLoader), 'Accept': 'text/html'};
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

  /// Drops a cached page (e.g. after a like/watch toggle changed its state).
  static void invalidate(int threadId) => _cache.remove(threadId);

  static void clearCache() => _cache.clear();

  /// Pages fetched while logged out cache the guest rendition (spoilers
  /// locked, download links hidden); drop everything when the session
  /// changes so the next open refetches member content.
  static void bindToAuthChanges() {
    AuthService.instance.addListener(clearCache);
  }

  /// POSTs a XenForo action (react, watch) with the session cookies and the
  /// page's CSRF token. XenForo reports errors inside 200 responses too.
  static Future<void> postAction(
    String url,
    String csrfToken, {
    Map<String, String> fields = const {},
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    final http.Client httpClient = client ?? http.Client();
    final bool shouldCloseClient = client == null;

    try {
      final headers = {
        'User-Agent': await ApiService.resolveUserAgent(packageInfoLoader),
        'Accept': 'application/json',
      };
      final cookies = AuthService.instance.cookieHeader;
      if (cookies != null) headers['Cookie'] = cookies;

      final response = await httpClient.post(
        Uri.parse(url),
        headers: headers,
        body: {'_xfToken': csrfToken, '_xfResponseType': 'json', ...fields},
      );

      if (response.statusCode != 200 ||
          response.body.contains('"status":"error"') ||
          response.body.contains('"errors"')) {
        throw ApiException('Action failed (HTTP ${response.statusCode})');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Action failed: $e');
    } finally {
      if (shouldCloseClient) httpClient.close();
    }
  }

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
      overview:
          'A representative mock thread page used on the web build, '
          'where CORS blocks fetching the real forum page.',
      spoilers: const [
        SpoilerSection(
          title: 'Changelog',
          content: 'v0.9.1\n- Fixed things\n- Added other things',
          rich: [
            RichPiece.text('v0.9.1', bold: true),
            RichPiece.newline(),
            RichPiece.text('- Fixed things'),
            RichPiece.newline(),
            RichPiece.text('- Added other things'),
          ],
        ),
        SpoilerSection(
          title: 'Developer Notes',
          content: 'Thanks for playing! Join the discord',
          rich: [
            RichPiece.text('Thanks for '),
            RichPiece.text('playing!', italic: true),
            RichPiece.text(' Join the '),
            RichPiece.text('discord', url: 'https://example.com/discord'),
          ],
        ),
      ],
      downloads: const DownloadsSection(
        sets: [
          DownloadSet(
            title: null,
            groups: [
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
          ),
          DownloadSet(
            title: 'Alternate Version (v0.8)',
            groups: [
              DownloadGroup(
                label: 'Win',
                links: [DownloadLink(host: 'GOFILE', url: 'https://example.com/alt-win')],
              ),
            ],
          ),
        ],
        extras: [
          DownloadGroup(
            label: 'Extras',
            links: [DownloadLink(host: 'Full save', url: 'https://example.com/save')],
          ),
        ],
      ),
      attachments: const [DownloadLink(host: 'mock-2026.torrent', url: 'https://attachments.f95zone.to/mock.torrent')],
      actions: const ThreadActions(
        csrfToken: 'mock-csrf',
        reactUrl: 'https://example.com/posts/1/react?reaction_id=1',
        watchUrl: 'https://example.com/threads/1/watch',
      ),
    );
  }
}
