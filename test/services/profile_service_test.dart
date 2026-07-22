import 'dart:io';

import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/profile_service.dart';
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

  late AuthService previous;

  setUp(() {
    previous = AuthService.instance;
    AuthService.instance = AuthService(InMemoryCookieStorage());
  });

  tearDown(() {
    AuthService.instance = previous;
  });

  test('fetchOwnProfile hits /members/<id>/ derived from the session cookie', () async {
    await AuthService.instance.saveCookies({'xf_user': '6726912,token'});
    final fixture = File('test/fixtures/profile_invader_incubus.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    final page = await ProfileService.fetchOwnProfile(client: client, packageInfoLoader: () async => _packageInfo());

    expect(urls, ['https://f95zone.to/members/6726912/']);
    expect(page.username, 'Invader Incubus');
    expect(page.wallPosts, hasLength(4));
  });

  test('fetchOwnProfile without a session throws a sign-in error', () async {
    expect(
      () => ProfileService.fetchOwnProfile(client: MockClient((_) async => http.Response('', 200))),
      throwsA(isA<ApiException>()),
    );
  });

  test('fetchProfile hits the given member URL as-is', () async {
    final fixture = File('test/fixtures/profile_invader_incubus.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    final page = await ProfileService.fetchProfile(
      'https://f95zone.to/members/invader-incubus.6726912/',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(urls, ['https://f95zone.to/members/invader-incubus.6726912/']);
    expect(page.username, 'Invader Incubus');
  });

  test('fetchPostings loads the member-search query and parses its page', () async {
    final fixture = File('test/fixtures/profile_postings_search.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    final page = await ProfileService.fetchPostings(
      'https://f95zone.to/search/member?user_id=801262',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    // The GET follows the redirect to the results page transparently.
    expect(urls, ['https://f95zone.to/search/member?user_id=801262']);
    expect(page.postings, hasLength(20));
    expect(page.currentPage, 1);
    expect(page.totalPages, 20);
    expect(page.searchUrl, 'https://f95zone.to/search/655136415/?c[users]=BaasB&o=date');
  });

  test('fetchPostingsPage appends the page number to the results URL', () async {
    final fixture = File('test/fixtures/profile_postings_search.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    await ProfileService.fetchPostingsPage(
      'https://f95zone.to/search/655136415/?c[users]=BaasB&o=date',
      3,
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(urls.single, contains('&page=3'));
  });

  test('deleteProfilePost posts to the delete action with the CSRF token', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{"status":"ok"}', 200);
    });

    await ProfileService.deleteProfilePost(
      'https://f95zone.to/profile-posts/146954/delete',
      'tok123',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(requests.single.method, 'POST');
    expect(requests.single.url.toString(), 'https://f95zone.to/profile-posts/146954/delete');
    expect(requests.single.body, contains('_xfToken=tok123'));
  });

  test('fetchAbout requests the about tab URL and parses its pane', () async {
    const aboutHtml = '''
<html><body><div class="block-container"><div class="block-body">
  <div class="block-row">
    <dl class="pairs pairs--columns"><dt>Location</dt><dd>Berlin</dd></dl>
  </div>
  <div class="block-row"><h4 class="block-textHeader">About</h4><div class="bbWrapper">A bio.</div></div>
</div></div></body></html>
''';
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response(aboutHtml, 200);
    });

    final about = await ProfileService.fetchAbout(
      'https://f95zone.to/members/gugatron.328002/',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(urls, ['https://f95zone.to/members/gugatron.328002/about']);
    expect(about.location, 'Berlin');
    expect(about.bio, 'A bio.');
  });

  group('non-200 responses', () {
    Future<void> Function() fetchWith(http.Client client) => () => ProfileService.fetchProfile(
      'https://f95zone.to/members/someone.1/',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    http.Client statedAs(String message, int status) => MockClient(
      (_) async => http.Response(
        '<html><body><div class="p-body-pageContent">'
        '<div class="blockMessage">$message</div>'
        '</div></body></html>',
        status,
      ),
    );

    test('a 403 is permanent, and says so in the site\'s words', () async {
      expect(
        fetchWith(statedAs('This member limits who may view their full profile.', 403)),
        throwsA(
          isA<ContentUnavailableException>()
              .having((e) => e.message, 'message', 'This member limits who may view their full profile.')
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('a 404 is permanent too, and carries its own status', () async {
      // Kept apart from the 403 so the screen can say "not found" rather
      // than accusing a deleted member of hiding.
      expect(
        fetchWith(statedAs('The requested member could not be found.', 404)),
        throwsA(
          isA<ContentUnavailableException>()
              .having((e) => e.message, 'message', 'The requested member could not be found.')
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('an unreadable body falls back to the status', () async {
      expect(
        fetchWith(MockClient((_) async => http.Response('nope', 403))),
        throwsA(
          isA<ContentUnavailableException>().having(
            (e) => e.message,
            'message',
            'Failed to load profile page: 403',
          ),
        ),
      );
    });

    test('a 500 stays retryable', () async {
      expect(
        fetchWith(statedAs('Something broke.', 500)),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Something broke.')),
      );
    });
  });
}
