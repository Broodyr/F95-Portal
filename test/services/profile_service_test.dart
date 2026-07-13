import 'dart:io';

import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/profile_service.dart';
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

  test('fetchPostings requests the recent-content tab URL', () async {
    final fixture = File('test/fixtures/profile_gugatron.htm').readAsStringSync();
    final urls = <String>[];
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    final postings = await ProfileService.fetchPostings(
      'https://f95zone.to/members/gugatron.328002/',
      client: client,
      packageInfoLoader: () async => _packageInfo(),
    );

    expect(urls, ['https://f95zone.to/members/gugatron.328002/recent-content']);
    expect(postings, hasLength(15));
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
}
