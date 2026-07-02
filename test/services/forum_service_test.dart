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

  test('non-200 responses surface as ApiException', () async {
    final client = MockClient((_) async => http.Response('blocked', 403));

    expect(
      () => ForumService.fetchIndex(client: client, packageInfoLoader: () async => _packageInfo()),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('403'))),
    );
  });
}
