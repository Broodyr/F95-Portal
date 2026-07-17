import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_settings_storage.dart';

void main() {
  late InMemorySettingsStorage storage;
  late SettingsService service;

  setUp(() {
    storage = InMemorySettingsStorage();
    service = SettingsService(storage);
  });

  group('SettingsService', () {
    test('starts with sane defaults', () {
      expect(service.settings.defaultQuery, const SearchQuery());
      expect(service.settings.sfwBlur, isFalse);
      expect(service.settings.recentTags, isEmpty);
    });

    test('update persists and notifies', () async {
      int notifications = 0;
      service.addListener(() => notifications++);

      await service.update(
        service.settings.copyWith(
          sfwBlur: true,
          recentTags: [225, 103],
          defaultQuery: const SearchQuery(category: SearchCategory.comics, notags: [258]),
        ),
      );

      expect(notifications, 1);
      expect(storage.stored, isNotNull);

      final fresh = SettingsService(storage);
      await fresh.load();
      expect(fresh.settings.sfwBlur, isTrue);
      expect(fresh.settings.recentTags, [225, 103]);
      expect(fresh.settings.defaultQuery.category, SearchCategory.comics);
      expect(fresh.settings.defaultQuery.notags, [258]);
    });

    test('recordTagUse keeps a deduped most-recent-first list, capped at 30', () async {
      await service.recordTagUse([1, 2, 3]);
      await service.recordTagUse([3, 4]);

      expect(service.settings.recentTags.take(4), [3, 4, 1, 2]);

      await service.recordTagUse(List.generate(40, (i) => 100 + i));
      expect(service.settings.recentTags.length, 30);
    });

    test('recordTagUse with no tags is a no-op', () async {
      int notifications = 0;
      service.addListener(() => notifications++);

      await service.recordTagUse(const []);

      expect(notifications, 0);
      expect(storage.stored, isNull);
    });

    test('load tolerates corrupt storage', () async {
      storage.stored = '{{{ not json';

      await service.load();

      expect(service.settings.sfwBlur, isFalse);
    });
  });
}
