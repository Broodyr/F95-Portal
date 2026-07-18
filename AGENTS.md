# F95 Portal — agent notes

Flutter app (Android is the real target; web is for development). Only rules
that aren't obvious from reading the code:

## Conventions

- Any backdrop blur must go through the `GlassAware` widget
  (`lib/widgets/glass_aware.dart`) so the "Glass effects" setting can disable
  it — a raw `BackdropFilter` ignores the user's performance preference.
- Any exclusive-choice control (radio group, sort order, kind filter, tab
  bar) must use `SegmentedSelector` (`lib/widgets/segmented_selector.dart`):
  a dark pill track with one sliding bordered highlight. Size can vary
  (`dense`, `shrinkWrap`), the style cannot. Don't hand-roll pill rows or use
  Material `SegmentedButton`/`Radio`. Exceptions only where a fixed
  equal-width track can't work: option sets of variable/unbounded count that
  must wrap (download group switcher in `browse_details_sheet.dart`) or
  scroll (reaction tabs in `reactions_sheet.dart`).
- No `Color(0x...)` literals in widgets or screens — every color reads from
  the theme. The app is dark-only and single-accent (crimson primary;
  `secondary` is deliberately a neutral grey — don't give it a hue).
  Sources, in order of preference:
  - `Theme.of(context).colorScheme.*` for Material tokens (surface, primary,
    surfaceContainerHighest, ...). Don't set `Scaffold.backgroundColor` or
    sheet backgrounds explicitly; the theme defaults already cover them.
  - `AppColors.of(context)` (`lib/theme/app_colors.dart`) for app-specific
    tokens (placeholderSurface, mutedForeground, chipSurface). Need a new
    color? Add a token there, don't inline the hex.
  - `AppPalette` constants are for the `ThemeData` definition in `main.dart`
    only — never reference them from widgets.
  Exception: semantic one-off palettes where the hex *is* the meaning
  (version-pill status badges, reaction/label colors in
  `utils/formatters.dart`) stay local to their widget. Enforced by
  `test/theme_guard_test.dart` — its whitelist is the authoritative
  exception list.
- Tests first (TDD): write or extend a failing test before the implementation
  change. Run `flutter analyze` before committing.
- Don't launch the web dev server / Browser pane to verify changes — the
  user always tests by hand and prefers saving the usage. Tests plus
  `flutter analyze` are sufficient verification.

## Constraints

- Android toolchain is pinned on purpose: Gradle 8.14 / AGP 8.11.1 /
  Kotlin 2.2.20. Do not upgrade to Gradle/AGP 9.x until flutter_inappwebview
  supports it — the versions look outdated but are deliberately held back.
- Web builds can't reach the F95Zone API (CORS), so `ApiService` serves
  query-filtered mock data on web. Don't "fix" web networking; verify real
  API behavior on Android.

## Test-fixture traps (saved forum pages in test/fixtures/)

- Browser-saved fixtures absolutize hrefs, but live pages serve relative
  ones. Parsers must absolutize URLs themselves, and each parser needs a
  synthetic relative-href test — fixture-only tests will pass against a
  parser that breaks on live pages.
- Fixtures capture the post-JavaScript DOM. Attributes like aria tab wiring
  are JS-added and absent from the server-rendered HTML the app actually
  fetches. Scope parsers on server-rendered markers (e.g. `data-href`), and
  test against fixtures with the JS-added attributes stripped.
