import 'package:f95_portal/models/f95_metadata.dart';
import 'package:f95_portal/models/search_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';

void main() {
  late F95Metadata metadata;

  setUpAll(() {
    metadata = loadAndInstallMetadata();
  });

  group('F95Metadata.fromJson', () {
    test('parses prefixes for every category', () {
      for (final category in SearchCategory.values) {
        expect(metadata.prefixesFor(category), isNotEmpty, reason: 'no prefixes for $category');
      }
    });

    test('maps the corrected games engine prefixes', () {
      expect(metadata.prefixById(SearchCategory.games, 3)?.name, 'Unity');
      expect(metadata.prefixById(SearchCategory.games, 7)?.name, "Ren'Py");
      expect(metadata.prefixById(SearchCategory.games, 13)?.name, 'VN');
      expect(metadata.prefixById(SearchCategory.games, 47)?.name, 'WebGL');
      expect(metadata.prefixById(SearchCategory.games, 116)?.name, 'Godot');
    });

    test('identifies status prefixes via group 4', () {
      final completed = metadata.prefixById(SearchCategory.games, 18);
      expect(completed?.name, 'Completed');
      expect(completed?.isStatus, isTrue);
      expect(metadata.prefixById(SearchCategory.games, 7)?.isStatus, isFalse);
    });

    test('status prefixes exist for comics too', () {
      expect(metadata.prefixById(SearchCategory.comics, 22)?.name, 'Abandoned');
    });

    test('resolves tag names and reverse lookups', () {
      expect(metadata.tagName(191), 'futa/trans');
      expect(metadata.tagName(107), '3dcg');
      expect(metadata.tagIdsByName['pregnancy'], 225);
      expect(metadata.tagName(999999), isNull);
    });
  });

  group('F95Metadata.instance', () {
    test('throws a helpful error when not loaded', () {
      final previous = F95Metadata.instance;
      F95Metadata.reset();
      expect(() => F95Metadata.instance, throwsStateError);
      F95Metadata.instance = previous;
    });
  });

  group('F95Metadata.load', () {
    testWidgets('loads the bundled asset via rootBundle as main() does', (tester) async {
      final previous = F95Metadata.instance;
      F95Metadata.reset();

      final loaded = await F95Metadata.load();

      expect(loaded.prefixById(SearchCategory.games, 7)?.name, "Ren'Py");
      expect(identical(F95Metadata.instance, loaded), isTrue);
      F95Metadata.instance = previous;
    });
  });
}
