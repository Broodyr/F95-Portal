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

  // ColorScheme.dark() predates the M3 roles and hands back a placeholder for
  // each rather than deriving one. Reading a role the theme never pins gets
  // that placeholder — which is how the detail sheet's chip fills came to
  // render as nothing at all, painting surface onto surface, and how every
  // muted label drew at the same full strength as the text above it.
  //
  // Grouped by what the constructor actually leaves behind. Anything not
  // listed here (primary, onSurface, error, the scrim and shadow) gets a
  // sensible value and is fine to read unpinned.
  const junkRoles = <String>[
    // All eight come back identical to `surface`, so a fill drawn with one
    // over a surface-coloured parent is invisible.
    'surfaceDim', 'surfaceBright',
    'surfaceContainerLowest', 'surfaceContainerLow', 'surfaceContainer',
    'surfaceContainerHigh', 'surfaceContainerHighest',
    // Pure white, so the contrast step they exist to provide is absent.
    'onSurfaceVariant', 'outline', 'outlineVariant',
    // The 2014 Material purple and teal, unrelated to the app's crimson.
    'surfaceTint', 'primaryContainer', 'onPrimaryContainer',
    'secondaryContainer', 'onSecondaryContainer',
    'tertiary', 'onTertiary', 'tertiaryContainer', 'onTertiaryContainer',
    // White, and surface, swapped in for each other.
    'inverseSurface', 'onInverseSurface', 'inversePrimary',
  ];

  test('every M3 role the app reads is pinned in the ColorScheme', () {
    final theme = File('lib/main.dart').readAsStringSync();
    final pattern = RegExp(r'\.(' + junkRoles.join('|') + r')\b');
    final used = <String>{};
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        used.addAll(pattern.allMatches(line).map((m) => m[1]!));
      }
    }

    final unpinned = used.where((role) => !theme.contains('$role:')).toList()..sort();
    expect(
      unpinned,
      isEmpty,
      reason:
          'These roles are read but never set on the ColorScheme in '
          'lib/main.dart, so they resolve to whatever ColorScheme.dark() '
          'happens to leave there — surface, pure white, or a legacy Material '
          'accent — rather than to anything this theme chose: '
          '${unpinned.join(', ')}. Pin them in main.dart (ask first: the value '
          'is a design decision) or use a token that already exists.',
    );
  });
}
