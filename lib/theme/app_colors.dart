import 'package:flutter/material.dart';

import '../constants.dart';

/// Core palette constants referenced by the [ThemeData] in main.dart.
/// All other code should read colors from the theme
/// ([ColorScheme] or [AppColors.of]) rather than these constants.
abstract final class AppPalette {
  static const Color primary = Color(0xFFDC144D);
  static const Color secondary = Color(0xFF181818);
  static const Color surface = Color(0xFF1C1C1C);
  static const Color background = Color(0xFF0F0F0F);
  static const Color appBar = Color(0xFF1A1A1A);

  /// Wired to `ColorScheme.surfaceContainerHighest` — see the note in
  /// main.dart for why that role has to be pinned by hand. Chips paint it at
  /// [AppAlphas.chipFill] over sheets that are themselves [surface], so it
  /// has to sit well clear of [surface] to register at all — most of the
  /// gap between them is eaten by that 35%.
  static const Color raisedSurface = Color(0xFF303030);

  /// Wired to `ColorScheme.onSurfaceVariant`, and the same value as
  /// [AppColors.subtleText] — the role means the muted counterpart to
  /// onSurface, which is what that token already is. Left unpinned it comes
  /// back as pure white, no different from onSurface, so everything written
  /// to read as secondary renders at full strength instead.
  static const Color subtleText = Color(0xFF9E9E9E);
}

/// Theme extension for app-specific colors that don't map onto
/// standard Material [ColorScheme] tokens.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.placeholderSurface,
    required this.mutedForeground,
    required this.chipSurface,
    required this.brightText,
    required this.bodyText,
    required this.subtleText,
    required this.hintText,
  });

  /// Card/image placeholders, spoiler backgrounds.
  final Color placeholderSurface;

  /// Muted icons and borders.
  final Color mutedForeground;

  /// Small raised elements: popup menus, pills.
  final Color chipSurface;

  /// Near-white emphasis text: usernames, toast messages, field values.
  final Color brightText;

  /// Softer body copy: post bodies, bios.
  final Color bodyText;

  /// The supporting line under a heading: setting subtitles, section blurbs,
  /// row metadata. Reads as secondary to [bodyText] without receding as far
  /// as [hintText], which has to stay distinguishable from real input.
  final Color subtleText;

  /// Placeholder text in empty input fields; dimmer than [bodyText] so a
  /// hint never reads as something the user typed.
  final Color hintText;

  static const AppColors dark = AppColors(
    placeholderSurface: Color(0xFF2A2A2A),
    mutedForeground: Color(0xFF666666),
    chipSurface: Color(0xFF262629),
    brightText: Color(0xFFE8E8E8),
    bodyText: Color(0xFFC9C9C9),
    subtleText: AppPalette.subtleText,
    hintText: Color(0xFF757575),
  );

  /// Falls back to [dark] when the theme lacks the extension (bare
  /// MaterialApp in tests); the app is dark-only, so it's always right.
  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>() ?? dark;

  @override
  AppColors copyWith({
    Color? placeholderSurface,
    Color? mutedForeground,
    Color? chipSurface,
    Color? brightText,
    Color? bodyText,
    Color? subtleText,
    Color? hintText,
  }) {
    return AppColors(
      placeholderSurface: placeholderSurface ?? this.placeholderSurface,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      chipSurface: chipSurface ?? this.chipSurface,
      brightText: brightText ?? this.brightText,
      bodyText: bodyText ?? this.bodyText,
      subtleText: subtleText ?? this.subtleText,
      hintText: hintText ?? this.hintText,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      placeholderSurface: Color.lerp(placeholderSurface, other.placeholderSurface, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      chipSurface: Color.lerp(chipSurface, other.chipSurface, t)!,
      brightText: Color.lerp(brightText, other.brightText, t)!,
      bodyText: Color.lerp(bodyText, other.bodyText, t)!,
      subtleText: Color.lerp(subtleText, other.subtleText, t)!,
      hintText: Color.lerp(hintText, other.hintText, t)!,
    );
  }
}
