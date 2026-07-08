import 'dart:io';

import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/in_memory_cookie_storage.dart';

PackageInfo _packageInfo() =>
    PackageInfo(appName: 'F95 Portal', packageName: 'com.example.f95portal', version: '1.0.0', buildNumber: '42');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ForumService.clearCache);

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

  test('non-200 responses surface as ApiException', () async {
    final client = MockClient((_) async => http.Response('blocked', 403));

    expect(
      () => ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo()),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('403'))),
    );
  });
}
