import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiService.clearUserAgentCache();
  });

  group('ApiService.createMockData', () {
    test('returns expected structure', () {
      final response = ApiService.createMockData();

      expect(response.status, 'ok');
      expect(response.data.threads, isNotEmpty);
      expect(response.data.pagination.page, 1);
      expect(response.data.count, greaterThan(0));
    });
  });

  group('ApiService.fetchThreads', () {
    test('parses successful HTTP response', () async {
      int loaderCalls = 0;
      final PackageInfoLoader loader = () async {
        loaderCalls++;
        return PackageInfo(
          appName: 'F95 Portal',
          packageName: 'com.example.f95portal',
          version: '1.0.0',
          buildNumber: '42',
        );
      };

      final client = MockClient((request) async {
        expect(request.headers['User-Agent'], 'F95Portal/1.0.0 (42)');
        final body = jsonEncode({
          'status': 'ok',
          'msg': {
            'data': [
              {'thread_id': 1, 'title': 'From API'},
            ],
            'pagination': {'page': 1, 'total': 5},
            'count': 100,
          },
        });
        return http.Response(body, 200, headers: {'content-type': 'application/json'});
      });

      final response = await ApiService.fetchThreads(client: client, packageInfoLoader: loader);

      expect(loaderCalls, 1);
      expect(response.status, 'ok');
      expect(response.data.threads, hasLength(1));
      expect(response.data.threads.first.title, 'From API');
      expect(response.data.pagination.total, 5);
    });

    test('reuses cached user agent on subsequent calls', () async {
      int loaderCalls = 0;
      final PackageInfoLoader loader = () async {
        loaderCalls++;
        return PackageInfo(
          appName: 'F95 Portal',
          packageName: 'com.example.f95portal',
          version: '1.0.0',
          buildNumber: '1',
        );
      };

      Future<http.Response> handler(http.Request request) async {
        final body = jsonEncode({
          'status': 'ok',
          'msg': {
            'data': [
              {'thread_id': request.hashCode, 'title': 'Call ${request.hashCode}'},
            ],
            'pagination': {'page': 1, 'total': 1},
            'count': 1,
          },
        });
        return http.Response(body, 200);
      }

      final client = MockClient(handler);

      await ApiService.fetchThreads(client: client, packageInfoLoader: loader);
      await ApiService.fetchThreads(client: client, packageInfoLoader: loader);

      expect(loaderCalls, 1);
    });

    test('returns mock data when fallback enabled', () async {
      final client = MockClient((_) async => http.Response('error', 500));

      final response = await ApiService.fetchThreads(
        client: client,
        fallbackToMockOnError: true,
        packageInfoLoader: () async => PackageInfo(
          appName: 'F95 Portal',
          packageName: 'com.example.f95portal',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

      expect(response.status, 'ok');
      expect(response.data.threads, isNotEmpty);
    });

    test('throws ApiException when fallback disabled', () async {
      final client = MockClient((_) async => http.Response('error', 500));

      expect(
        () => ApiService.fetchThreads(
          client: client,
          packageInfoLoader: () async => PackageInfo(
            appName: 'F95 Portal',
            packageName: 'com.example.f95portal',
            version: '1.0.0',
            buildNumber: '1',
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('wraps unexpected exceptions in ApiException', () async {
      final client = MockClient((_) async => throw StateError('boom'));

      expect(
        () => ApiService.fetchThreads(
          client: client,
          packageInfoLoader: () async => PackageInfo(
            appName: 'F95 Portal',
            packageName: 'com.example.f95portal',
            version: '1.0.0',
            buildNumber: '1',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });
}
