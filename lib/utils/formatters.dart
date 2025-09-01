import 'dart:ui';

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

class GameUtils {
  /// Maps prefix IDs to engine names based on observed API data
  /// This mapping is based on the edge cases provided
  static const Map<int, String> _prefixToEngine = {
    13: 'WebGL',
    3: 'VN',
    47: 'Unity',
    7: 'HTML', // Based on "Cocky Me" example - may need adjustment
    // Add more mappings as we discover them
  };

  /// Maps tag IDs to engine names (placeholder mapping for now)
  /// This will need to be updated based on actual tag mappings from the API
  static const Map<int, String> _tagToEngine = {
    107: 'Unity',
    130: 'Ren\'Py',
    191: 'Others',
    // Add more mappings as we learn the actual tag system
  };

  /// Gets multiple engines from prefixes and tags
  /// Returns a list of engine names found in the game data
  static List<String> getEnginesFromGame(List<int> prefixes, List<int> tags) {
    Set<String> engines = <String>{};

    // Check prefixes first (they seem to be more reliable for engines)
    for (int prefix in prefixes) {
      if (_prefixToEngine.containsKey(prefix)) {
        engines.add(_prefixToEngine[prefix]!);
      }
    }

    // Fallback to tags if no engines found in prefixes
    if (engines.isEmpty) {
      for (int tag in tags) {
        if (_tagToEngine.containsKey(tag)) {
          engines.add(_tagToEngine[tag]!);
        }
      }
    }

    // Return default if no engines found
    if (engines.isEmpty) {
      engines.add('Others');
    }

    return engines.toList();
  }

  /// Formats the time string for display
  static String formatTime(String timeString) {
    // The API returns strings like "3 weeks", "4 days", "2 months"
    // For now, just return as-is since they're already formatted
    return timeString;
  }
}
