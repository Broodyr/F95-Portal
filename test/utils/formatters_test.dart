import 'package:flutter_test/flutter_test.dart';
import 'package:f95_portal/utils/formatters.dart';

void main() {
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

    test('falls back to Others for unknown engines', () {
      final color = EngineColors.getEngineColor('Unknown Engine');
      expect(color.toARGB32(), 0xFF6e9e37);
    });
  });

  group('ThreadUtils', () {
    test('prefers engines mapped from prefixes', () {
      final engines = ThreadUtils.getEnginesFromThread([13], const []);
      expect(engines, ['WebGL']);
    });

    test('falls back to tags when prefixes empty', () {
      final engines = ThreadUtils.getEnginesFromThread(const [], const [130]);
      expect(engines, ["Ren'Py"]);
    });

    test('returns Others when no mapping available', () {
      final engines = ThreadUtils.getEnginesFromThread(const [], const []);
      expect(engines, ['Others']);
    });
  });
}
