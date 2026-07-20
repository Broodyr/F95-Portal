import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/account.dart';
import '../models/forum.dart';
import '../models/thread_page.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'forum_parser.dart';
import 'site_error.dart';
import 'thread_page_service.dart';

/// Fetches and parses forum pages (directory, thread lists, post loops,
/// reaction overlays), with a small URL-keyed cache like ThreadPageService.
class ForumService {
  static const String indexUrl = 'https://f95zone.to/';
  static final Map<String, Object> _cache = {};

  static Future<ForumIndex> fetchIndex({http.Client? client, PackageInfoLoader? packageInfoLoader}) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockForumIndex();
    }
    return _cached(
      indexUrl,
      () async => parseForumIndex(await _fetchHtml(indexUrl, client: client, packageInfoLoader: packageInfoLoader)),
    );
  }

  static Future<ForumPage> fetchForumPage(
    String url, {
    int page = 1,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockForumPage();
    }
    final pageUrl = _withPage(url, page);
    return _cached(
      pageUrl,
      () async => parseForumPage(await _fetchHtml(pageUrl, client: client, packageInfoLoader: packageInfoLoader)),
    );
  }

  static Future<ThreadPostsPage> fetchThreadPosts(
    String url, {
    int page = 1,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockThreadPosts(page: page);
    }
    final pageUrl = _withPage(url, page);
    return _cached(pageUrl, () async {
      final stopwatch = Stopwatch()..start();
      final html = await _fetchHtml(pageUrl, client: client, packageInfoLoader: packageInfoLoader);
      final fetchMs = stopwatch.elapsedMilliseconds;
      stopwatch.reset();
      final parsed = parseThreadPosts(html);
      if (kDebugMode) {
        debugPrint(
          'ForumService thread posts: fetch ${fetchMs}ms, '
          'parse ${stopwatch.elapsedMilliseconds}ms, ${html.length} chars',
        );
      }
      return parsed;
    });
  }

  static Future<ReactionsPage> fetchReactions(
    String url, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockReactionsPage();
    }
    return _cached(
      url,
      () async => parseReactionsPage(await _fetchHtml(url, client: client, packageInfoLoader: packageInfoLoader)),
    );
  }

  // --- Account pages (bookmarks, alerts) ------------------------------------

  static const String bookmarksUrl = 'https://f95zone.to/account/bookmarks';
  static const String alertsUrl = 'https://f95zone.to/account/alerts';
  static const String preferencesUrl = 'https://f95zone.to/account/preferences';

  /// Per-session snapshot of the account's alert preferences; reset when
  /// the session changes.
  static AlertPreferences? _alertPrefs;

  /// Test hook: forget the per-session preference snapshot.
  @visibleForTesting
  static void resetAlertPreferences() => _alertPrefs = null;

  /// The account's alert read-marking preferences, fetched once per
  /// session (they only change through the site's preferences page).
  static Future<AlertPreferences> fetchAlertPreferences({
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) return const AlertPreferences();
    return _alertPrefs ??= parseAlertPreferences(
      await _fetchHtml(preferencesUrl, client: client, packageInfoLoader: packageInfoLoader),
    );
  }

  /// Saves the "Alerts pop-up skips mark read" preference to the account.
  ///
  /// XenForo's preference save treats absent checkboxes as unchecked, so
  /// the whole form is fetched fresh and replayed with just this one field
  /// flipped; a partial POST would silently reset every other preference.
  static Future<void> setAlertsPopupSkipsMarkRead(
    bool value, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      _alertPrefs = AlertPreferences(
        popupSkipsMarkRead: value,
        pageSkipsMarkRead: _alertPrefs?.pageSkipsMarkRead ?? false,
      );
      return;
    }
    final html = await _fetchHtml(preferencesUrl, client: client, packageInfoLoader: packageInfoLoader);
    final form = parsePreferencesForm(html);
    if (form.fields.isEmpty) throw ApiException('Preferences form not found; are you logged in?');

    const fieldName = 'option[sv_alerts_popup_skips_mark_read]';
    await ThreadPageService.postForm(
      preferencesUrl,
      form.csrfToken,
      fields: [
        for (final field in form.fields)
          if (field.$1 != fieldName) field,
        if (value) (fieldName, '1'),
      ],
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
    _alertPrefs = AlertPreferences(
      popupSkipsMarkRead: value,
      pageSkipsMarkRead: parseAlertPreferences(html).pageSkipsMarkRead,
    );
  }

  static Future<BookmarksPage> fetchBookmarks({
    int page = 1,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockBookmarks(page: page);
    }
    final pageUrl = _withQueryPage(bookmarksUrl, page);
    return _cached(
      pageUrl,
      () async => parseBookmarks(await _fetchHtml(pageUrl, client: client, packageInfoLoader: packageInfoLoader)),
    );
  }

  static Future<AlertsPage> fetchAlerts({
    int page = 1,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockAlerts(page: page);
    }
    final pageUrl = _withQueryPage(alertsUrl, page);
    return _cached(
      pageUrl,
      () async => parseAlerts(await _fetchHtml(pageUrl, client: client, packageInfoLoader: packageInfoLoader)),
    );
  }

  /// Acknowledges the alerts feed the way the site's bell does, then
  /// drops cached pages so the badge refresh sees the result.
  ///
  /// Two server calls make "viewed in the app = read" true. The pop-up GET
  /// (XHR header is load-bearing — XenForo redirects plain GETs of that
  /// route to the alerts page, which silently no-ops) clears the site-wide
  /// bell counter but only marks read the handful of alerts the pop-up
  /// itself renders. So the rows the app actually displayed are passed in
  /// [unreadAlertIds] and forced read one by one via /account/alert, which
  /// marks its alert read on view in every addon version — unless the
  /// account's "pop-up skips mark read" preference says alerts should stay
  /// unread until visited.
  static Future<void> acknowledgeAlerts({
    List<int> unreadAlertIds = const [],
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) return;
    try {
      // Per-alert reads go FIRST: the pop-up view flags alerts as viewed,
      // and the addon's status-change guard treats an already-viewed alert
      // as a no-op, which would swallow the read marking.
      if (unreadAlertIds.isNotEmpty) {
        final prefs = await fetchAlertPreferences(client: client, packageInfoLoader: packageInfoLoader);
        if (!prefs.popupSkipsMarkRead) {
          for (final id in unreadAlertIds) {
            await _fetchHtml(
              'https://f95zone.to/account/alert?alert_id=$id',
              client: client,
              packageInfoLoader: packageInfoLoader,
            );
          }
        }
      }

      await _fetchHtml(
        '$alertsUrl-popup',
        client: client,
        packageInfoLoader: packageInfoLoader,
        extraHeaders: const {'X-Requested-With': 'XMLHttpRequest'},
      );
    } finally {
      clearCache();
    }
  }

  /// XenForo page URLs: `<base>/page-N`, page 1 is the base itself.
  static String _withPage(String url, int page) {
    final base = url.endsWith('/') ? url : '$url/';
    return page <= 1 ? base : '${base}page-$page';
  }

  /// Account routes paginate by query string instead of a /page-N suffix.
  static String _withQueryPage(String url, int page) => page <= 1 ? url : '$url?page=$page';

  /// Drops cached account feeds (bookmarks, alerts) so their next fetch is
  /// live; forum and thread pages stay cached. Account feeds change out
  /// from under the app (a bookmark made seconds ago, alerts arriving
  /// server-side), so their screens refresh on open.
  static void invalidateAccountPages() =>
      _cache.removeWhere((key, _) => key.startsWith(bookmarksUrl) || key.startsWith(alertsUrl));

  static Future<T> _cached<T extends Object>(String key, Future<T> Function() load) async {
    final cached = _cache[key];
    if (cached is T) return cached;
    final value = await load();
    if (_cache.length >= AppLimits.pageCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
    return value;
  }

  static Future<String> _fetchHtml(
    String url, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
    Map<String, String> extraHeaders = const {},
  }) async {
    final http.Client httpClient = client ?? http.Client();
    final bool shouldCloseClient = client == null;

    try {
      final headers = {
        'User-Agent': await ApiService.resolveUserAgent(packageInfoLoader),
        'Accept': 'text/html',
        ...extraHeaders,
      };
      final cookies = AuthService.instance.cookieHeader;
      if (cookies != null) headers['Cookie'] = cookies;

      final response = await httpClient.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) {
        // The site states its own reason on a 403 or 404 — "The requested
        // forum could not be found" beats a path and a number for anyone who
        // isn't debugging. Falls through to the path when it says nothing,
        // which keeps multi-request flows (alert acknowledgment) diagnosable
        // from the surfaced message alone.
        final stated = parseSiteErrorMessage(response.body);
        final fallback = 'Failed to load ${Uri.parse(url).path}: ${response.statusCode}';
        if (isPermanentStatus(response.statusCode)) {
          throw ContentUnavailableException(stated ?? fallback, statusCode: response.statusCode);
        }
        throw ApiException(stated ?? fallback);
      }
      return response.body;
    } on ContentUnavailableException {
      // Would otherwise be swallowed by the catch-all below and re-thrown as
      // a retryable ApiException, undoing the distinction.
      rethrow;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load forum page: $e');
    } finally {
      if (shouldCloseClient) httpClient.close();
    }
  }

  // --- Search ---------------------------------------------------------------

  /// Runs a forum search: fetches a CSRF token from the search form page,
  /// POSTs the query, and parses the results page the site redirects to
  /// (dart:io follows the 303 automatically; a manual hop covers clients
  /// that don't). Further pages come from [searchPage].
  static Future<ForumSearchPage> search(
    String keywords, {
    bool titleOnly = false,
    String user = '',
    String order = 'relevance',
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockSearchPage();
    }

    final formHtml = await _fetchHtml(
      'https://f95zone.to/search/',
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
    final csrf = parseCsrfToken(formHtml);

    final http.Client httpClient = client ?? http.Client();
    final bool shouldCloseClient = client == null;
    try {
      final headers = {'User-Agent': await ApiService.resolveUserAgent(packageInfoLoader), 'Accept': 'text/html'};
      final cookies = AuthService.instance.cookieHeader;
      if (cookies != null) headers['Cookie'] = cookies;

      final response = await httpClient.post(
        Uri.parse('https://f95zone.to/search/search'),
        headers: headers,
        body: {
          'keywords': keywords,
          'search_type': 'post',
          'order': order,
          if (titleOnly) 'c[title_only]': '1',
          if (user.trim().isNotEmpty) 'c[users]': user.trim(),
          '_xfToken': csrf,
        },
      );

      final location = response.headers['location'];
      if (response.statusCode >= 300 && response.statusCode < 400 && location != null) {
        return parseSearchResults(await _fetchHtml(location, client: client, packageInfoLoader: packageInfoLoader));
      }
      if (response.statusCode != 200) {
        throw ApiException('Search failed: ${response.statusCode}');
      }
      return parseSearchResults(response.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Search failed: $e');
    } finally {
      if (shouldCloseClient) httpClient.close();
    }
  }

  /// Fetches page N of an earlier search via its GET-able results URL.
  static Future<ForumSearchPage> searchPage(
    String searchUrl,
    int page, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockSearchPage(page: page);
    }
    final separator = searchUrl.contains('?') ? '&' : '?';
    return parseSearchResults(
      await _fetchHtml('$searchUrl${separator}page=$page', client: client, packageInfoLoader: packageInfoLoader),
    );
  }

  // --- Edit -----------------------------------------------------------------

  /// Fetches the BBCode source of an editable post from its edit page.
  static Future<String> fetchEditBbcode(
    String editUrl, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockWrite);
      return 'Mock post body to edit.';
    }
    return parseEditBbcode(await _fetchHtml(editUrl, client: client, packageInfoLoader: packageInfoLoader));
  }

  /// Saves an edited post body back through its edit action.
  static Future<void> saveEdit(
    String editUrl,
    String csrfToken,
    String message, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) {
    if (kIsWeb) return Future.delayed(AppDurations.mockWrite);
    return ThreadPageService.postAction(
      editUrl,
      csrfToken,
      fields: {'message': message},
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  // --- Writes (react, reply, new thread) -----------------------------------
  // All XenForo form POSTs with the page CSRF; ThreadPageService.postAction
  // already speaks that protocol (cookies, _xfToken, error sniffing).

  /// Reacts to a post; posting the same reaction id again removes it.
  static Future<void> react(
    int postId,
    int reactionId,
    String csrfToken, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) {
    if (kIsWeb) return Future.delayed(AppDurations.mockWrite);
    return ThreadPageService.postAction(
      'https://f95zone.to/posts/$postId/react?reaction_id=$reactionId',
      csrfToken,
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  /// Fetches the report overlay for a post or profile post so its reasons and
  /// token can be shown. Uncached: the token is single-use, and a stale one
  /// fails the submit.
  static Future<ReportForm> fetchReportForm(
    String contentUrl, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(AppDurations.mockRead);
      return createMockReportForm();
    }
    return parseReportForm(await _fetchHtml(contentUrl, client: client, packageInfoLoader: packageInfoLoader));
  }

  /// Files a report. [reasonId] is one of the ids [fetchReportForm] returned.
  static Future<void> sendReport(
    String action,
    String csrfToken, {
    required int reasonId,
    required String message,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) {
    if (kIsWeb) return Future.delayed(AppDurations.mockWrite);
    return ThreadPageService.postAction(
      action,
      csrfToken,
      fields: {'reason_id': '$reasonId', 'message': message},
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  /// Posts a BBCode reply to a thread's add-reply action.
  static Future<void> sendReply(
    String replyUrl,
    String csrfToken,
    String message, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) {
    if (kIsWeb) return Future.delayed(AppDurations.mockWrite);
    return ThreadPageService.postAction(
      replyUrl,
      csrfToken,
      fields: {'message': message},
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  /// Creates a thread via a forum's post-thread action.
  static Future<void> postThread(
    String postThreadUrl,
    String csrfToken, {
    required String title,
    required String message,
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) {
    if (kIsWeb) return Future.delayed(AppDurations.mockWrite);
    return ThreadPageService.postAction(
      postThreadUrl,
      csrfToken,
      fields: {'title': title, 'message': message},
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  static void clearCache() => _cache.clear();

  /// Guest renditions differ from member ones (unread markers, visibility);
  /// drop everything when the session changes, including the per-session
  /// preference snapshot.
  static void bindToAuthChanges() {
    AuthService.instance.addListener(() {
      clearCache();
      _alertPrefs = null;
    });
  }

  // --- Mock data (web build + widget tests) --------------------------------

  static ForumIndex createMockForumIndex() {
    return const ForumIndex(
      categories: [
        ForumCategory(
          id: 1,
          title: 'Adult Games',
          forums: [
            ForumNode(
              id: 2,
              title: 'Games',
              url: 'https://example.com/forums/games.2/',
              description: 'Adult games of all engines',
              threads: '54.3K',
              messages: '12.9M',
              unread: true,
              lastPost: ForumLastPost(title: 'Eternum [v0.9]', date: '4 minutes ago', username: 'Caribdis'),
              subforums: [
                ForumNode(id: 114, title: 'Trending Games', url: 'https://example.com/link-forums/114/', isLink: true),
              ],
            ),
            ForumNode(
              id: 7,
              title: 'Mods',
              url: 'https://example.com/forums/mods.7/',
              threads: '12.1K',
              messages: '1.2M',
              lastPost: ForumLastPost(title: 'SummertimeSaga cheat mod', date: '22 minutes ago', username: 'modder'),
            ),
          ],
        ),
        ForumCategory(
          id: 5,
          title: 'Discussion',
          forums: [
            ForumNode(
              id: 9,
              title: 'General Discussions',
              url: 'https://example.com/forums/general-discussions.9/',
              threads: '8.4K',
              messages: '640K',
              unread: true,
              lastPost: ForumLastPost(title: 'Hidden gems thread', date: '1 minute ago', username: 'hexgem'),
            ),
          ],
        ),
      ],
    );
  }

  static ForumPage createMockForumPage() {
    return const ForumPage(
      title: 'General Discussions',
      subforums: [
        ForumNode(
          id: 11,
          title: 'Introduction',
          url: 'https://example.com/forums/introduction.11/',
          description: 'Introduce yourself to the rest of the community',
          threads: '4K',
          messages: '19.6K',
        ),
        ForumNode(id: 106, title: 'Off-Topic', url: 'https://example.com/forums/off-topic.106/', threads: '3.1K'),
      ],
      threads: [
        ForumThreadRow(
          threadId: 17387,
          title: 'Post your signatures here',
          url: 'https://example.com/threads/17387/',
          author: 'TCMS',
          startDate: 'Aug 28, 2018',
          sticky: true,
          unread: true,
          replies: '4K',
          views: '2M',
          lastPostDate: 'Today at 4:32 PM',
          lastPostUser: 'Admirer',
          lastPage: 225,
        ),
        ForumThreadRow(
          threadId: 188349,
          title: 'Hidden gems you almost skipped',
          url: 'https://example.com/threads/188349/',
          prefixes: [ForumThreadPrefix(id: 15, label: 'README')],
          author: 'hexgem',
          startDate: 'Jun 12, 2026',
          unread: true,
          replies: '823',
          views: '104K',
          lastPostDate: '1 minute ago',
          lastPostUser: 'RenLover',
          lastPage: 42,
        ),
        ForumThreadRow(
          threadId: 190001,
          title: 'What made you stop playing a game?',
          url: 'https://example.com/threads/190001/',
          author: 'RenLover',
          startDate: 'Jun 2, 2026',
          replies: '214',
          views: '18K',
          lastPostDate: '18 minutes ago',
          lastPostUser: 'avoxel',
          lastPage: 11,
        ),
      ],
      // A single page: a perpetual load-more spinner would spin forever on
      // the web build (and time out pumpAndSettle in widget tests).
      currentPage: 1,
      totalPages: 1,
      postThreadUrl: 'https://example.com/forums/general-discussions.9/post-thread',
      csrfToken: 'mock-csrf',
    );
  }

  static ThreadPostsPage createMockThreadPosts({int page = 1}) {
    return ThreadPostsPage(
      title: 'Hidden gems you almost skipped',
      posts: [
        ForumPost(
          postId: 9000 + page,
          number: (page - 1) * 2 + 1,
          author: 'DarkVault',
          authorUrl: 'https://example.com/members/darkvault.4242/',
          authorId: 4242,
          memberTitle: 'Well-known member',
          date: 'Jun 28, 2026',
          blocks: const [
            ForumPostBlock(
              kind: PostBlockKind.rich,
              pieces: [
                RichPiece.text('Nobody mentions '),
                RichPiece.text('Wands & Witches', bold: true),
                RichPiece.text(' — the progression system is genuinely one of the best on the site. '),
                RichPiece.smilie(':love:', asset: 'assets/smilies/love.png'),
                RichPiece.smilie(':KEK:', asset: 'assets/smilies/kek.png'),
                RichPiece.smilie(':lepew:'),
              ],
            ),
          ],
          reactions: const PostReactionSummary(
            topReactionIds: [3, 1, 14],
            count: 69,
            url: 'https://example.com/posts/9001/reactions',
          ),
        ),
        ForumPost(
          postId: 9100 + page,
          number: (page - 1) * 2 + 2,
          author: 'mikkoxd',
          authorUrl: 'https://example.com/members/mikkoxd.777/',
          authorId: 777,
          memberTitle: 'Member',
          date: 'Jun 29, 2026',
          blocks: [
            ForumPostBlock(
              kind: PostBlockKind.quote,
              label: 'DarkVault',
              // The post above, so the quote's jump is live on web too.
              sourcePostId: 9000 + page,
              pieces: const [RichPiece.text('Nobody mentions Wands & Witches…')],
            ),
            const ForumPostBlock(
              kind: PostBlockKind.rich,
              pieces: [RichPiece.text('Seconding this. The dev posts monthly progress updates, worth watching.')],
            ),
            const ForumPostBlock(
              kind: PostBlockKind.spoiler,
              label: 'Ending spoiler',
              pieces: [RichPiece.text('The witch did it.')],
            ),
          ],
          reactions: const PostReactionSummary(
            topReactionIds: [1],
            count: 31,
            url: 'https://example.com/posts/9102/reactions',
          ),
        ),
      ],
      currentPage: page,
      totalPages: 42,
      csrfToken: 'mock-csrf',
      replyUrl: 'https://example.com/threads/188349/add-reply',
      watchUrl: 'https://example.com/threads/188349/watch',
      threadUrl: 'https://example.com/threads/188349/',
    );
  }

  static ForumSearchPage createMockSearchPage({int page = 1}) {
    return ForumSearchPage(
      results: [
        ForumSearchResult(
          title: 'Corruption of Champions II [v0.9.0] [Savin]',
          prefixes: const ['Others'],
          url: 'https://example.com/threads/coc2.11371/post-${20920000 + page}',
          snippet: 'No, no, because that might make the player feel powerful…',
          author: 'Dragons Are Romance',
          date: '5 minutes ago',
          forum: 'Games',
        ),
        const ForumSearchResult(
          title: 'Hidden gems you almost skipped',
          url: 'https://example.com/threads/188349/',
          snippet: 'Nobody mentions Wands & Witches…',
          author: 'DarkVault',
          date: 'Jun 28, 2026',
          forum: 'General Discussions',
        ),
      ],
      // Single page, as with the other mocks: a perpetual load-more spinner
      // would never settle in widget tests (or on the web build).
      currentPage: page,
      totalPages: 1,
      searchUrl: 'https://example.com/search/649178657/?q=mock',
    );
  }

  /// The live site's reason list at the time of writing; the web build can't
  /// reach the real form (CORS), so this stands in for it there.
  static ReportForm createMockReportForm() {
    return const ReportForm(
      action: 'https://f95zone.to/posts/1/report',
      csrfToken: 'mock',
      reasons: [
        ReportReason(id: 7, label: 'Game update'),
        ReportReason(id: 8, label: 'Comic / Animation Update'),
        ReportReason(id: 11, label: 'Asset update'),
        ReportReason(id: 9, label: 'Advertising / Spam'),
        ReportReason(id: 10, label: 'Inappropriate Behaviour'),
        ReportReason(id: 0, label: 'Other'),
      ],
    );
  }

  static ReactionsPage createMockReactionsPage() {
    return const ReactionsPage(
      tabs: [
        ReactionTab(id: 0, name: 'All', count: 69),
        ReactionTab(id: 3, name: 'Haha', count: 43),
        ReactionTab(id: 1, name: 'Like', count: 19),
        ReactionTab(id: 14, name: 'Heart', count: 7),
      ],
      members: [
        ReactionMember(
          username: 'iDrought',
          memberTitle: 'Member',
          reactionId: 3,
          date: 'Today at 2:11 PM',
          profileUrl: 'https://example.com/members/idrought.1/',
        ),
        ReactionMember(
          username: 'ThyElyson',
          memberTitle: 'New Member',
          reactionId: 1,
          date: 'Today at 1:40 PM',
          profileUrl: 'https://example.com/members/thyelyson.2/',
        ),
        ReactionMember(
          username: 'OnlyHeStandsThere',
          memberTitle: 'Member',
          reactionId: 3,
          date: 'Yesterday',
          profileUrl: 'https://example.com/members/onlyhestandsthere.3/',
        ),
        ReactionMember(
          username: 'quietfan',
          memberTitle: 'Member',
          reactionId: 14,
          date: 'Yesterday',
          profileUrl: 'https://example.com/members/quietfan.4/',
        ),
      ],
    );
  }

  static BookmarksPage createMockBookmarks({int page = 1}) {
    return BookmarksPage(
      entries: const [
        BookmarkEntry(
          title: 'Mousetrap: Theft & Bondage [v0.1.6p2] [Milkshake++]',
          url: 'https://example.com/threads/mousetrap.254486/',
          snippet: 'Overview: Ratalie found herself working off a debt to the local thieves guild after being framed…',
          author: 'Milkshake++',
          date: 'Jun 21, 2025',
          bookmarkUrl: 'https://example.com/posts/16935508/bookmark',
        ),
        BookmarkEntry(
          title: '[Secret Flasher Manaka] Custom Missions 1.2.1',
          isPost: true,
          url: 'https://example.com/posts/19803972/',
          snippet: 'Manaka - Custom missions',
          author: 'SekiYuri',
          date: 'Apr 8, 2026',
          bookmarkUrl: 'https://example.com/posts/19803972/bookmark',
        ),
      ],
      currentPage: page,
      totalPages: 1,
      csrfToken: 'mock-csrf',
    );
  }

  static AlertsPage createMockAlerts({int page = 1}) {
    return AlertsPage(
      groups: const [
        AlertGroup(
          title: 'Today',
          alerts: [
            AlertEntry(
              alertId: 91,
              username: 'TMakuboss',
              action: 'replied to the thread',
              labels: ['Unity', 'Completed'],
              title: "Mage Kanade's Futanari Dungeon Quest [Final] [Dieselmine]",
              url: 'https://example.com/posts/20969203/',
              time: '13 minutes ago',
              unread: true,
            ),
            AlertEntry(
              alertId: 92,
              username: 'CrisspyFriess',
              action: 'replied to the thread',
              labels: ['Others'],
              title: 'Crisis Point: Extinction [v0.48.1] [Anon42]',
              url: 'https://example.com/posts/20966169/',
              time: 'Today at 12:37 PM',
              unread: true,
            ),
          ],
        ),
        AlertGroup(
          title: 'Yesterday',
          alerts: [
            AlertEntry(
              alertId: 93,
              username: 'Mihawk_80',
              action: 'replied to the thread',
              labels: ['VN', "Ren'Py", 'Abandoned'],
              title: 'One Lewd World [v0.287] [Zelltin]',
              url: 'https://example.com/posts/20964484/',
              time: 'Yesterday at 9:14 PM',
            ),
          ],
        ),
      ],
      currentPage: page,
      totalPages: 1,
      csrfToken: 'mock-csrf',
      badgeCount: 2,
    );
  }
}
