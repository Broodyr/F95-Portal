import 'dart:io';

import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:f95_portal/services/site_error.dart';
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
    ForumService.clearCache();
    ForumService.resetAlertPreferences();
  });

  test('fetches, parses, and caches the forum index', () async {
    final fixture = File('test/fixtures/forum_home.htm').readAsStringSync();
    int requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.toString(), ForumService.indexUrl);
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    final index = await ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo());
    expect(index.categories.first.title, 'Announcements');

    final again = await ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo());
    expect(identical(index, again), isTrue);
    expect(requests, 1);
  });

  test('requests page-N URLs and caches per page', () async {
    final fixture = File('test/fixtures/forum_gd.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    const base = 'https://f95zone.to/forums/general-discussions.9/';
    await ForumService.fetchForumPage(base, client: client, packageInfoLoader: () async => _packageInfo());
    await ForumService.fetchForumPage(base, page: 3, client: client, packageInfoLoader: () async => _packageInfo());
    await ForumService.fetchForumPage(base, page: 3, client: client, packageInfoLoader: () async => _packageInfo());

    expect(urls, [base, '${base}page-3']);
  });

  test('thread posts and reactions parse through the service', () async {
    final posts = File('test/fixtures/thread_renpy_bubbles_page2.htm').readAsStringSync();
    final reactions = File('test/fixtures/reactions_being_a_dik.htm').readAsStringSync();
    final client = MockClient((request) async {
      final body = request.url.path.contains('reactions') ? reactions : posts;
      return http.Response.bytes(body.codeUnits, 200);
    });

    final page = await ForumService.fetchThreadPosts(
      'https://f95zone.to/threads/207754/',
      page: 2,
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );
    expect(page.posts.first.author, 'Lerd0');

    final overlay = await ForumService.fetchReactions(
      'https://f95zone.to/posts/1565686/reactions',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );
    expect(overlay.tabs.first.count, 12837);
  });

  test('acknowledging alerts fires the pop-up as XHR and forces displayed rows read', () async {
    // Without the XHR header XenForo redirects the pop-up route to the
    // alerts PAGE, whose skip-mark-read preference silently no-ops the
    // whole acknowledgment. The pop-up also only marks read what it
    // renders itself, so the displayed unread rows are forced via the
    // per-alert route — gated on the account's pop-up preference, which is
    // fetched once per session.
    final alertsFixture = File('test/fixtures/account_alerts.htm').readAsStringSync();
    final urls = <String>[];
    String? xhrHeader;
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      if (request.url.path.endsWith('alerts-popup')) {
        xhrHeader = request.headers['X-Requested-With'];
        return http.Response('<div>popup</div>', 200);
      }
      if (request.url.path.endsWith('preferences')) {
        return http.Response('<input type="checkbox" name="option[sv_alerts_popup_skips_mark_read]" />', 200);
      }
      if (request.url.queryParameters.containsKey('alert_id')) return http.Response('ok', 200);
      return http.Response.bytes(alertsFixture.codeUnits, 200);
    });
    Future<void> acknowledge(List<int> ids) => ForumService.acknowledgeAlerts(
      unreadAlertIds: ids,
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    await ForumService.fetchAlerts(client: client, packageInfoLoader: () async => _packageInfo());
    await acknowledge([91, 92]);
    // The cache was dropped, so the next fetch hits the network again;
    // the preference snapshot survives (second acknowledge skips it).
    await ForumService.fetchAlerts(client: client, packageInfoLoader: () async => _packageInfo());
    await acknowledge([93]);

    // Per-alert reads run BEFORE the pop-up: the pop-up flags alerts as
    // viewed, and the addon skips status changes on already-viewed alerts.
    expect(urls, [
      'https://f95zone.to/account/alerts',
      'https://f95zone.to/account/preferences',
      'https://f95zone.to/account/alert?alert_id=91',
      'https://f95zone.to/account/alert?alert_id=92',
      'https://f95zone.to/account/alerts-popup',
      'https://f95zone.to/account/alerts',
      'https://f95zone.to/account/alert?alert_id=93',
      'https://f95zone.to/account/alerts-popup',
    ]);
    expect(xhrHeader, 'XMLHttpRequest');
  });

  test('a checked pop-up-skips-mark-read preference blocks the per-alert marking', () async {
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      if (request.url.path.endsWith('preferences')) {
        return http.Response(
          '<input type="checkbox" name="option[sv_alerts_popup_skips_mark_read]" checked="checked" />',
          200,
        );
      }
      return http.Response('ok', 200);
    });

    await ForumService.acknowledgeAlerts(
      unreadAlertIds: [91, 92],
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    // Preference read, pop-up fired, but no per-alert forcing: the user
    // asked for alerts to stay unread until visited.
    expect(urls, ['https://f95zone.to/account/preferences', 'https://f95zone.to/account/alerts-popup']);
  });

  test('saving the pop-up preference replays the whole form with the flag flipped', () async {
    const formHtml = '''
      <html data-csrf="page-token"><body>
      <form action="/account/preferences" method="post">
        <select name="user[style_id]"><option value="0">a</option><option value="31" selected="selected">b</option></select>
        <input type="checkbox" name="option[prefixess_ignored_prefix_ids][]" value="7" checked="checked">
        <input type="checkbox" name="option[prefixess_ignored_prefix_ids][]" value="9" checked="checked">
        <input type="checkbox" name="option[sv_alerts_page_skips_mark_read]" value="1" checked="checked">
        <input type="checkbox" name="option[sv_alerts_popup_skips_mark_read]" value="1">
        <input type="hidden" name="_xfToken" value="form-token">
      </form></body></html>
    ''';
    final gets = <String>[];
    http.Request? post;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        post = request;
        return http.Response('{"status":"ok"}', 200);
      }
      gets.add(request.url.toString());
      return http.Response(formHtml, 200);
    });

    await ForumService.setAlertsPopupSkipsMarkRead(true, client: client, packageInfoLoader: () async => _packageInfo());

    expect(gets, [ForumService.preferencesUrl]);
    expect(post!.url.toString(), ForumService.preferencesUrl);
    expect(post!.headers['Content-Type'], startsWith('application/x-www-form-urlencoded'));

    final body = Uri(query: post!.body).queryParametersAll;
    expect(body['_xfToken'], ['form-token']);
    // The untouched fields are replayed — a partial POST would reset them.
    expect(body['user[style_id]'], ['31']);
    expect(body['option[prefixess_ignored_prefix_ids][]'], ['7', '9']);
    expect(body['option[sv_alerts_page_skips_mark_read]'], ['1']);
    expect(body['option[sv_alerts_popup_skips_mark_read]'], ['1']);

    // The per-session snapshot reflects the save without another fetch.
    final prefs = await ForumService.fetchAlertPreferences(
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );
    expect(prefs.popupSkipsMarkRead, isTrue);
    expect(prefs.pageSkipsMarkRead, isTrue);
    expect(gets, hasLength(1));
  });

  test('turning the pop-up preference off drops the checkbox from the POST', () async {
    const formHtml = '''
      <html><body>
      <form action="/account/preferences" method="post">
        <input type="checkbox" name="option[sv_alerts_popup_skips_mark_read]" value="1" checked="checked">
        <input type="hidden" name="_xfToken" value="form-token">
      </form></body></html>
    ''';
    http.Request? post;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        post = request;
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response(formHtml, 200);
    });

    await ForumService.setAlertsPopupSkipsMarkRead(
      false,
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    final body = Uri(query: post!.body).queryParametersAll;
    expect(body.containsKey('option[sv_alerts_popup_skips_mark_read]'), isFalse);
    expect((await ForumService.fetchAlertPreferences(client: client)).popupSkipsMarkRead, isFalse);
  });

  test('saving the pop-up preference without a form (logged out) throws', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response('<html><body><p>login required</p></body></html>', 200);
    });

    await expectLater(
      ForumService.setAlertsPopupSkipsMarkRead(true, client: client, packageInfoLoader: () async => _packageInfo()),
      throwsA(isA<ApiException>()),
    );
  });

  test('invalidateAccountPages drops account feeds but keeps forum pages cached', () async {
    final index = File('test/fixtures/forum_home.htm').readAsStringSync();
    final bookmarks = File('test/fixtures/account_bookmarks.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      final body = request.url.path.contains('bookmarks') ? bookmarks : index;
      return http.Response.bytes(body.codeUnits, 200);
    });
    Future<void> fetchBoth() async {
      await ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo());
      await ForumService.fetchBookmarks(client: client, packageInfoLoader: () async => _packageInfo());
    }

    await fetchBoth();
    ForumService.invalidateAccountPages();
    await fetchBoth();

    // The index stayed cached; only the bookmarks feed refetched.
    expect(urls, [ForumService.indexUrl, ForumService.bookmarksUrl, ForumService.bookmarksUrl]);
  });

  test('signing in clears the cache', () async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());
    ForumService.bindToAuthChanges();

    final fixture = File('test/fixtures/forum_home.htm').readAsStringSync();
    int requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    await ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo());
    await ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo());
    expect(requests, 1);

    await AuthService.instance.saveCookies({'xf_user': 'tok'});

    await ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo());
    expect(requests, 2);
  });

  test('search fetches a csrf, posts the query, and parses results', () async {
    final results = File('test/fixtures/search_results.htm').readAsStringSync();
    final log = <String>[];
    late Map<String, String> posted;
    final client = MockClient((request) async {
      log.add('${request.method} ${request.url}');
      if (request.method == 'GET') return http.Response('<html data-csrf="tok,en"></html>', 200);
      posted = request.bodyFields;
      return http.Response.bytes(results.codeUnits, 200);
    });

    final page = await ForumService.search(
      'futanari',
      titleOnly: true,
      user: 'SomeDev',
      order: 'date',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(log, ['GET https://f95zone.to/search/', 'POST https://f95zone.to/search/search']);
    expect(posted['keywords'], 'futanari');
    expect(posted['search_type'], 'post');
    expect(posted['order'], 'date');
    expect(posted['c[title_only]'], '1');
    expect(posted['c[users]'], 'SomeDev');
    expect(posted['_xfToken'], 'tok,en');
    expect(page.results, hasLength(20));
    expect(page.totalPages, 50);
  });

  test('search follows a 303 location when the client does not', () async {
    final results = File('test/fixtures/search_results.htm').readAsStringSync();
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/search/') {
        return http.Response('<html data-csrf="t"></html>', 200);
      }
      if (request.method == 'POST') {
        return http.Response('', 303, headers: {'location': 'https://f95zone.to/search/649178657/?q=futanari'});
      }
      expect(request.url.toString(), 'https://f95zone.to/search/649178657/?q=futanari');
      return http.Response.bytes(results.codeUnits, 200);
    });

    final page = await ForumService.search('futanari', client: client, packageInfoLoader: () async => _packageInfo());
    expect(page.results, hasLength(20));
  });

  test('searchPage appends the page parameter to the results URL', () async {
    final results = File('test/fixtures/search_results.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response.bytes(results.codeUnits, 200);
    });

    await ForumService.searchPage(
      'https://f95zone.to/search/649178657/?q=futanari',
      2,
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );
    expect(urls, ['https://f95zone.to/search/649178657/?q=futanari&page=2']);
  });

  test('fetchEditBbcode reads the edit form; saveEdit posts the message', () async {
    final log = <String>[];
    final client = MockClient((request) async {
      log.add('${request.method} ${request.url}');
      if (request.method == 'GET') {
        return http.Response('<form><textarea name="message">Old [b]body[/b]</textarea></form>', 200);
      }
      expect(request.bodyFields['message'], 'New body');
      expect(request.bodyFields['_xfToken'], 'tok');
      return http.Response('{"status":"ok"}', 200);
    });

    final bbcode = await ForumService.fetchEditBbcode(
      'https://f95zone.to/posts/7/edit',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );
    expect(bbcode, 'Old [b]body[/b]');

    await ForumService.saveEdit(
      'https://f95zone.to/posts/7/edit',
      'tok',
      'New body',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );
    expect(log, ['GET https://f95zone.to/posts/7/edit', 'POST https://f95zone.to/posts/7/edit']);
  });

  test('react posts to the reaction endpoint with the csrf token', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response('{"status":"ok"}', 200);
    });

    await ForumService.react(13720617, 14, 'tok,en', client: client, packageInfoLoader: () async => _packageInfo());

    expect(seen.url.toString(), 'https://f95zone.to/posts/13720617/react?reaction_id=14');
    expect(seen.bodyFields['_xfToken'], 'tok,en');
  });

  test('sendReply posts the message to the add-reply action', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response('{"status":"ok"}', 200);
    });

    await ForumService.sendReply(
      'https://f95zone.to/threads/some-thread.42/add-reply',
      'tok,en',
      'Nice [b]post[/b]!',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(seen.url.toString(), 'https://f95zone.to/threads/some-thread.42/add-reply');
    expect(seen.bodyFields['message'], 'Nice [b]post[/b]!');
    expect(seen.bodyFields['_xfToken'], 'tok,en');
  });

  test('postThread posts title and message to the post-thread action', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response('{"status":"ok"}', 200);
    });

    await ForumService.postThread(
      'https://f95zone.to/forums/general-discussions.9/post-thread',
      'tok,en',
      title: 'Hello',
      message: 'First!',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(seen.url.toString(), 'https://f95zone.to/forums/general-discussions.9/post-thread');
    expect(seen.bodyFields['title'], 'Hello');
    expect(seen.bodyFields['message'], 'First!');
    expect(seen.bodyFields['_xfToken'], 'tok,en');
  });

  test('write failures surface as ApiException', () {
    final client = MockClient((_) async => http.Response('{"errors":["nope"]}', 200));

    expect(
      () => ForumService.sendReply(
        'https://f95zone.to/threads/1/add-reply',
        't',
        'x',
        client: client,
        packageInfoLoader: () async => _packageInfo(),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  group('non-200 responses', () {
    Future<void> Function() fetchWith(http.Client client) =>
        () => ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo());

    test('a 404 is permanent and carries the site wording', () async {
      final client = MockClient(
        (_) async => http.Response(
          '<html><body><div class="p-body-pageContent">'
          '<div class="blockMessage">The requested forum could not be found.</div>'
          '</div></body></html>',
          404,
        ),
      );

      expect(
        fetchWith(client),
        throwsA(
          isA<ContentUnavailableException>().having(
            (e) => e.message,
            'message',
            'The requested forum could not be found.',
          ),
        ),
      );
    });

    test('a 403 with nothing to say still falls back to the path and status', () async {
      final client = MockClient((_) async => http.Response('blocked', 403));

      expect(
        fetchWith(client),
        throwsA(isA<ContentUnavailableException>().having((e) => e.message, 'm', contains('403'))),
      );
    });

    // A server error says nothing about whether the next request works, so it
    // stays an ordinary retryable failure.
    test('a server error stays retryable', () async {
      final client = MockClient((_) async => http.Response('boom', 500));

      expect(fetchWith(client), throwsA(isA<ApiException>().having((e) => e.message, 'm', contains('500'))));
    });
  });
}
