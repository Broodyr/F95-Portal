import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Colors must come from the theme (see AGENTS.md): `colorScheme.*`,
/// `AppColors.of(context)`, or a new token in lib/theme/app_colors.dart.
/// Raw `Color(0x...)` literals are only allowed where the hex itself is the
/// meaning (semantic one-off palettes) or where the theme is defined.
const _allowed = {
  // Theme definition.
  'lib/main.dart',
  'lib/theme/app_colors.dart',
  // Semantic palettes: the hex is the meaning, not shared chrome.
  'lib/utils/formatters.dart', // engine/label colors
  'lib/widgets/reaction_icon.dart', // reaction glyph + avatar palettes
  'lib/widgets/version_pill.dart', // thread status colors
  'lib/widgets/star_rating.dart', // gold star
};

void main() {
  test('no hardcoded Color(0x...) literals outside the theme and semantic palettes', () {
    final offenders = <String>[];
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      if (_allowed.contains(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains(RegExp(r'Color\(0x'))) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Hardcoded color literals found. Use Theme.of(context).colorScheme.*, '
          'AppColors.of(context), or add a token to lib/theme/app_colors.dart '
          '(see AGENTS.md). Offenders:\n${offenders.join('\n')}',
    );
  });
}
