import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';

void main() {
  setUpAll(() {
    loadAndInstallMetadata();
  });

  group('NumberFormatter', () {
    test('returns raw numbers under 1000', () {
      expect(NumberFormatter.formatNumber(999), '999');
    });

    test('formats thousands with suffix', () {
      expect(NumberFormatter.formatNumber(1500), '1.5K');
    });

    test('formats millions with suffix', () {
      expect(NumberFormatter.formatNumber(2500000), '2.5M');
    });
  });

  group('EngineColors', () {
    test('returns known engine color', () {
      final color = EngineColors.getEngineColor("Ren'Py");
      expect(color.toARGB32(), 0xFF9d46e3);
    });

    test('has a color for every games-category prefix name', () {
      final metadata = loadAndInstallMetadata();
      for (final prefix in metadata.prefixesFor(SearchCategory.games)) {
        if (prefix.isStatus) continue;
        expect(EngineColors.isValidEngine(prefix.name), isTrue, reason: 'missing color for ${prefix.name}');
      }
    });

    test('falls back to Others for unknown engines', () {
      final color = EngineColors.getEngineColor('Unknown Engine');
      expect(color.toARGB32(), 0xFF6c9c34);
    });
  });

  group('ThreadUtils.getEnginesFromThread', () {
    test('maps corrected prefix IDs to names', () {
      expect(ThreadUtils.getEnginesFromThread([7]), ["Ren'Py"]);
      expect(ThreadUtils.getEnginesFromThread([13, 7]), ['VN', "Ren'Py"]);
      expect(ThreadUtils.getEnginesFromThread([3]), ['Unity']);
      expect(ThreadUtils.getEnginesFromThread([116]), ['Godot']);
    });

    test('excludes status prefixes from the engine list', () {
      expect(ThreadUtils.getEnginesFromThread([7, 18]), ["Ren'Py"]);
      expect(ThreadUtils.getEnginesFromThread([2, 22]), ['RPGM']);
    });

    test('ignores tags entirely and falls back to Others', () {
      expect(ThreadUtils.getEnginesFromThread(const []), ['Others']);
    });

    test('renders unknown prefix IDs as raw IDs instead of crashing', () {
      expect(ThreadUtils.getEnginesFromThread([99999]), ['#99999']);
    });

    test('resolves names from the requested category', () {
      expect(ThreadUtils.getEnginesFromThread([43], category: SearchCategory.comics), ['Manga']);
      expect(ThreadUtils.getEnginesFromThread([38], category: SearchCategory.animations), ['GIF']);
    });
  });
}
