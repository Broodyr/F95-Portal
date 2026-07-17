import 'package:flutter/painting.dart';

abstract class AppDurations {
  static const Duration toastDuration = Duration(milliseconds: 2800);
}

abstract class AppButtons {
  /// Label style for the tall full-width CTA buttons (Search, Open thread,
  /// composer submit, sign-in). The M3 default 14pt label looked lost in
  /// them; this still scales with the font-size setting.
  static const TextStyle ctaTextStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

  /// Icon size that visually matches [ctaTextStyle].
  static const double ctaIconSize = 22;
}
