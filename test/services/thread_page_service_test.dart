import 'dart:io';

import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/thread_page_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo _packageInfo() =>
    PackageInfo(appName: 'F95 Portal', packageName: 'com.example.f95portal', version: '1.0.0', buildNumber: '42');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ThreadPageService.clearCache);

  test('fetches, parses, and caches the thread page', () async {
    final fixture = File('test/fixtures/thread_unity_in_heat.htm').readAsStringSync();
    int requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.toString(), 'https://f95zone.to/threads/12345/');
      return http.Response.bytes(fixture.codeUnits, 200);
    });

    final page = await ThreadPageService.fetch(12345, client: client, packageInfoLoader: () async => _packageInfo());
    expect(page.metaValue('Developer'), 'MonsterBox');

    final again = await ThreadPageService.fetch(12345, client: client, packageInfoLoader: () async => _packageInfo());
    expect(identical(page, again), isTrue);
    expect(requests, 1);
  });

  test('non-200 responses surface as ApiException', () async {
    final client = MockClient((_) async => http.Response('blocked', 403));

    expect(
      () => ThreadPageService.fetch(1, client: client, packageInfoLoader: () async => _packageInfo()),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('403'))),
    );
  });
}
