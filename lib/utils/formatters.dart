import 'dart:ui';

import '../models/f95_metadata.dart';
import '../models/search_category.dart';

class NumberFormatter {
  /// Formats large numbers with K/M suffixes
  /// 1000 -> "1.0K", 1500000 -> "1.5M"
  static String formatNumber(int number) {
    if (number < 1000) {
      return number.toString();
    } else if (number < 1000000) {
      double thousands = number / 1000;
      return "${thousands.toStringAsFixed(1)}K";
    } else {
      double millions = number / 1000000;
      return "${millions.toStringAsFixed(1)}M";
    }
  }
}

class EngineColors {
  static const Map<String, Color> _engineColors = {
    'Unity': Color(0xFFea5201),
    'Others': Color(0xFF6e9e37),
    'Ren\'Py': Color(0xFF9d46e3),
    'RPGM': Color(0xFF228fe6),
    'Tads': Color(0xFF0b79d1),
    'ADRIFT': Color(0xFF0b79d1),
    'Unreal Engine': Color(0xFF1152b7),
    'HTML': Color(0xFF54812d),
    'Java': Color(0xFF52a6b0),
    'Flash': Color(0xFF616161),
    'QSP': Color(0xFFaa2d77),
    'RAGS': Color(0xFFc77700),
    'WebGL': Color(0xFFfe5901),
    'VN': Color(0xFFd32f2f),
    'Godot': Color(0xFF478cbf),
    'Wolf RPG': Color(0xFF4caf50),
    'Collection': Color(0xFF616161),
    'SiteRip': Color(0xFF6e9e37),
    // Non-games categories
    'Comics': Color(0xFFc77700),
    'Manga': Color(0xFF0fb2fc),
    'Pinup': Color(0xFF228fe6),
    'CG': Color(0xFFa8980b),
    'Video': Color(0xFFc77700),
    'GIF': Color(0xFF03a9f4),
    'App': Color(0xFF4caf50),
  };

  /// Gets the color for a given engine name
  /// Returns Others' as default if engine not found
  static Color getEngineColor(String engine) {
    return _engineColors[engine] ?? _engineColors['Others']!;
  }

  /// Gets all available engine names
  static List<String> get allEngines => _engineColors.keys.toList();

  /// Checks if an engine is recognized
  static bool isValidEngine(String engine) {
    return _engineColors.containsKey(engine);
  }
}

class ThreadUtils {
  /// Resolves a thread's non-status prefixes to display names using the
  /// bundled vocabulary (assets/f95_metadata.json). Tags are content/genre
  /// descriptors and carry no engine information, so they play no part here.
  /// Unknown prefix IDs render as `#<id>` rather than crashing.
  static List<String> getEnginesFromThread(List<int> prefixes, {SearchCategory category = SearchCategory.games}) {
    final metadata = F95Metadata.instance;
    final engines = <String>[];

    for (final id in prefixes) {
      final prefix = metadata.prefixById(category, id);
      if (prefix == null) {
        engines.add('#$id');
      } else if (!prefix.isStatus) {
        engines.add(prefix.name);
      }
    }

    if (engines.isEmpty) {
      engines.add('Others');
    }

    return engines;
  }

  /// Formats the time string for display
  static String formatTime(String timeString) {
    // The API returns strings like "3 weeks", "4 days", "2 months"
    // For now, just return as-is since they're already formatted
    return timeString;
  }
}
