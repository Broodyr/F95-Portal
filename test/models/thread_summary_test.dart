import 'package:flutter_test/flutter_test.dart';
import 'package:f95_portal/models/thread_summary.dart';

void main() {
  group('ThreadSummary', () {
    test('fromJson parses full payload', () {
      final json = {
        'thread_id': 42,
        'title': 'Sample Thread',
        'creator': 'Sample Creator',
        'version': 'v1.2.3',
        'views': 12345,
        'likes': 678,
        'prefixes': [3, 18],
        'tags': [107, 191],
        'rating': 4.2,
        'cover': 'https://example.com/cover.png',
        'screens': ['screen1.png'],
        'date': '2 days',
        'watched': true,
        'ignored': false,
        'new': true,
        'ts': 1234567890,
      };

      final thread = ThreadSummary.fromJson(json);

      expect(thread.threadId, 42);
      expect(thread.title, 'Sample Thread');
      expect(thread.creator, 'Sample Creator');
      expect(thread.version, 'v1.2.3');
      expect(thread.views, 12345);
      expect(thread.likes, 678);
      expect(thread.prefixes, [3, 18]);
      expect(thread.tags, [107, 191]);
      expect(thread.rating, 4.2);
      expect(thread.cover, 'https://example.com/cover.png');
      expect(thread.screens, ['screen1.png']);
      expect(thread.date, '2 days');
      expect(thread.watched, isTrue);
      expect(thread.ignored, isFalse);
      expect(thread.isNew, isTrue);
      expect(thread.timestamp, 1234567890);
    });

    test('fromJson tolerates numeric fields arriving as doubles', () {
      // JSON numbers decode as double whenever the API emits a decimal point;
      // one such thread must not kill the whole response parse.
      final json = {
        'thread_id': 42.0,
        'title': 'Doubles',
        'views': 12345.0,
        'likes': 678.0,
        'prefixes': [3.0, 18],
        'tags': [107, 191.0],
        'rating': 4,
        'ts': 1234567890.0,
      };

      final thread = ThreadSummary.fromJson(json);

      expect(thread.threadId, 42);
      expect(thread.views, 12345);
      expect(thread.likes, 678);
      expect(thread.prefixes, [3, 18]);
      expect(thread.tags, [107, 191]);
      expect(thread.rating, 4.0);
      expect(thread.timestamp, 1234567890);
    });

    test('toJson serializes correctly', () {
      final thread = ThreadSummary(
        threadId: 7,
        title: 'Serialize Me',
        creator: 'Serializer',
        version: 'v0.9',
        views: 9000,
        likes: 123,
        prefixes: const [7, 18],
        tags: const [107],
        rating: 4.8,
        cover: '',
        screens: const [],
        date: '1 week',
        watched: false,
        ignored: true,
        isNew: false,
        timestamp: 555,
      );

      final json = thread.toJson();

      expect(json['thread_id'], 7);
      expect(json['title'], 'Serialize Me');
      expect(json['creator'], 'Serializer');
      expect(json['version'], 'v0.9');
      expect(json['views'], 9000);
      expect(json['likes'], 123);
      expect(json['prefixes'], [7, 18]);
      expect(json['tags'], [107]);
      expect(json['rating'], 4.8);
      expect(json['cover'], '');
      expect(json['screens'], isEmpty);
      expect(json['date'], '1 week');
      expect(json['watched'], isFalse);
      expect(json['ignored'], isTrue);
      expect(json['new'], isFalse);
      expect(json['ts'], 555);
    });

    test('status helpers detect completion edge cases', () {
      final thread = ThreadSummary(
        threadId: 1,
        title: 'Edges',
        creator: 'Edge Lord',
        version: 'v1.0',
        views: 100,
        likes: 10,
        prefixes: const [18, 22, 20],
        tags: const [],
        rating: 4.0,
        cover: '',
        screens: const [],
        date: 'today',
        watched: false,
        ignored: false,
        isNew: false,
        timestamp: 0,
      );

      expect(thread.isCompleted, isTrue);
      expect(thread.isAbandoned, isTrue);
      expect(thread.isOnhold, isTrue);
    });
  });

  group('ApiResponse', () {
    test('parses nested data structure', () {
      final json = {
        'status': 'ok',
        'msg': {
          'data': [
            {'thread_id': 1, 'title': 'Nested'},
          ],
          'pagination': {'page': 2, 'total': 4},
          'count': 120,
        },
      };

      final response = ApiResponse.fromJson(json);

      expect(response.status, 'ok');
      expect(response.data.threads, hasLength(1));
      expect(response.data.pagination.page, 2);
      expect(response.data.pagination.total, 4);
      expect(response.data.count, 120);
      expect(response.data.threads.first.title, 'Nested');
    });

    test('tolerates double-typed pagination and count', () {
      final json = {
        'status': 'ok',
        'msg': {
          'data': [],
          'pagination': {'page': 2.0, 'total': 4.0},
          'count': 120.0,
        },
      };

      final response = ApiResponse.fromJson(json);

      expect(response.data.pagination.page, 2);
      expect(response.data.pagination.total, 4);
      expect(response.data.count, 120);
    });
  });
}
