# F95 Portal — agent notes

Flutter app (Android is the real target; web is for development). Only rules
that aren't obvious from reading the code:

## Conventions

- Any backdrop blur must go through the `GlassAware` widget
  (`lib/widgets/glass_aware.dart`) so the "Glass effects" setting can disable
  it — a raw `BackdropFilter` ignores the user's performance preference.
- Tests first (TDD): write or extend a failing test before the implementation
  change. Run `flutter analyze` before committing.

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
