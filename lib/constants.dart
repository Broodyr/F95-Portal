import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Shared timing for the app's micro-animations (slide reveals, segment
/// highlights, chevrons). One knob keeps every surface in sync.
abstract final class Motion {
  static const Duration duration = Duration(milliseconds: 180);
  static const Curve curve = Curves.easeOutCubic;
}

abstract final class AppDurations {
  static const Duration toastDuration = Duration(milliseconds: 2800);

  /// Simulated latency for the web/test mock services, so the loading states
  /// are exercised during development instead of resolving instantly. Reads
  /// (list and page fetches) feel slower than writes by design.
  static const Duration mockRead = Duration(milliseconds: 300);
  static const Duration mockWrite = Duration(milliseconds: 200);
}

abstract final class AppBlur {
  /// Backdrop blur for the large glass surfaces: sheets, panels, dialogs.
  static const double panel = 24;

  /// Lighter blur for thin chrome — bars and toasts — where the panel value
  /// smears the content behind them into mush.
  static const double bar = 15;
}

abstract final class AppRadii {
  /// Fully-rounded pill. The app's controls are circles and pills by
  /// identity (see `GlassFab`), so this is a shape decision, not a number.
  static const double pill = 999;

  /// Outer corner of the segmented pills that overlay cover art (engine,
  /// version). Only the run's outer corners take it — inner seams stay
  /// square so adjacent segments read as one pill. See `SegmentedPill`.
  static const double pillSegment = 16;
}

abstract final class AppAlphas {
  /// Scrim behind modal sheets.
  static const double sheetBarrier = 0.55;

  /// Fill for chips, tiles, and unselected pill tracks.
  static const double chipFill = 0.35;
}

abstract final class AppLimits {
  /// URL-keyed LRU page caches in the forum and thread-page services.
  static const int pageCacheEntries = 20;
}

abstract final class AppButtons {
  /// Label style for the tall full-width CTA buttons (Search, Open thread,
  /// composer submit, sign-in). The M3 default 14pt label looked lost in
  /// them; this still scales with the font-size setting.
  static const TextStyle ctaTextStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

  /// Icon size that visually matches [ctaTextStyle].
  static const double ctaIconSize = 22;
}
