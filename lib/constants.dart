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

  /// Idle time before an in-progress composer draft is written to disk.
  static const Duration draftSave = Duration(milliseconds: 400);
}

abstract final class AppBlur {
  /// Backdrop blur for the large glass surfaces: sheets, panels.
  static const double panel = 24;

  /// Lighter blur for thin chrome — bars and toasts — where the panel value
  /// smears the content behind them into mush.
  static const double bar = 15;

  /// Even lighter blur for dialogs that sit on top of low-detail content.
  static const double dialog = 6;
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
  /// Scrim behind modal sheets and dialogs.
  static const double sheetBarrier = 0.55;

  /// Fill for chips, tiles, and unselected pill tracks.
  static const double chipFill = 0.35;

  /// Primary-tinted fill behind a selected pill or an active toggle — the
  /// segmented selector's slider, the sort/filter pills, the current page.
  static const double selectedFill = 0.25;

  /// Primary-tinted fill behind a prefix or label chip — thread prefixes,
  /// alert labels, the picked-member name chip.
  static const double labelChip = 0.2;

  /// Primary-tinted wash marking a row as highlighted or unread — an unread
  /// alert, a jumped-to profile comment.
  static const double highlightWash = 0.15;

  /// Edge on an outlined control or an emphasized container — outlined
  /// buttons, toggle pills, the quote rail, a jumped-to post's outline. Drawn
  /// over primary where the edge marks emphasis or an active state, over a
  /// neutral where it only needs to describe the shape.
  static const double outlineEdge = 0.5;

  /// The quieter edge, for lines that describe a shape without asking to be
  /// pressed — a comment rail, the faint outline on a chip. [outlineEdge]
  /// would read as a border on these.
  static const double subtleEdge = 0.2;

  /// The app's divider weight: a rule that only separates, carrying no edge
  /// of its own. Half [subtleEdge] — at that strength a divider stops
  /// reading as a gap between rows and starts reading as a box around them.
  static const double hairline = 0.1;
}

abstract final class AppLimits {
  /// URL-keyed LRU page caches in the forum and thread-page services.
  static const int pageCacheEntries = 20;

  /// Unsent composer drafts kept on disk; past this the least-recently-saved
  /// destination is dropped.
  static const int composerDrafts = 30;
}

abstract final class AppButtons {
  /// Label style for the tall full-width CTA buttons (Search, Open thread,
  /// composer submit, sign-in). The M3 default 14pt label looked lost in
  /// them; this still scales with the font-size setting.
  static const TextStyle ctaTextStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

  /// Icon size that visually matches [ctaTextStyle].
  static const double ctaIconSize = 22;
}
