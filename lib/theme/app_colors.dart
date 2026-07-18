import 'package:flutter/material.dart';

/// Core palette constants referenced by the [ThemeData] in main.dart.
/// All other code should read colors from the theme
/// ([ColorScheme] or [AppColors.of]) rather than these constants.
abstract final class AppPalette {
  static const Color surface = Color(0xFF1C1C1C);
  static const Color background = Color(0xFF0F0F0F);
  static const Color appBar = Color(0xFF1A1A1A);
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

  static const AppColors dark = AppColors(
    placeholderSurface: Color(0xFF2A2A2A),
    mutedForeground: Color(0xFF666666),
    chipSurface: Color(0xFF262629),
    brightText: Color(0xFFE8E8E8),
    bodyText: Color(0xFFC9C9C9),
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
  }) {
    return AppColors(
      placeholderSurface: placeholderSurface ?? this.placeholderSurface,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      chipSurface: chipSurface ?? this.chipSurface,
      brightText: brightText ?? this.brightText,
      bodyText: bodyText ?? this.bodyText,
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
    );
  }
}
