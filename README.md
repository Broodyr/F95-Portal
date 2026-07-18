# F95Zone Portal

A Flutter mobile frontend for F95zone. Dark, glassmorphic UI; targets Android primarily, web builds run entirely on mock data due to CORS.

## Project Snapshot
- Four tabs: **Browse** (fully featured feed/search), **Forum** (directory → thread lists → thread viewer, alerts & bookmarks), **Settings**, **Profile** (profile posts, postings, & about sections).
- Stateful services (auth, settings) are singletons; fetch services are static with injectable clients, so tests and web builds run on mocks.

## Layout

| Path | What lives here |
| --- | --- |
| `lib/services/` | Everything that talks to f95zone: the JSON list API, the XenForo page fetchers, and the tolerant HTML parsers they feed. Auth and settings live here too. |
| `lib/models/` | Immutable data — search queries, parsed threads and forum pages, the prefix/tag vocabulary. |
| `lib/screens/` | One file per destination: the four tabs, plus the forum drill-down, search, and login. |
| `lib/widgets/` | Shared UI — sheets, the glass and SFW wrappers, and the pieces screens compose. |
| `lib/theme/`, `lib/constants.dart` | Colors and shared design tokens (blur tiers, radii, motion, mock latency). Nothing else should hardcode them. |
| `test/` | Mirrors `lib/`. `test/fixtures/` holds 28 saved forum pages the parsers are TDD'd against. |
| `docs/api_mappings.md` | The authoritative API reference: endpoint surface, params, prefix/tag tables, and the server's quirks. Read it before touching `api_service.dart`. |

## Things that will surprise you

- **Web is a dev target, not a product.** Browser builds can't reach the API (CORS), so the services return query-filtered mock data on web. Never "fix" web networking — verify real API behavior on Android.
- **Every cache clears on auth change.** Pages fetched as a guest have locked spoilers and hidden downloads baked in; keeping them after sign-in would show a logged-in user the logged-out site.
- **The forum half is scraped, not APId.** Only the Browse list has a JSON endpoint. Everything else parses XenForo HTML, so the parsers are deliberately tolerant and every one is TDD'd against saved fixtures — upstream markup changes break them silently otherwise.
- **Sign-in is a real webview.** There's no auth API; login loads the actual f95 login page and captures session cookies when `xf_user` appears. It also lifts the anonymous hourly rate limit.

## Development

- `flutter pub get && flutter run`; `flutter test`; `flutter analyze`. Helper scripts in `tool/`.
- Conventions that aren't obvious from the code — glass and segmented-control rules, theme tokens, the pinned Android toolchain, fixture traps — are in [AGENTS.md](AGENTS.md). Read it before your first change.
- TDD: tests first, mirroring lib structure. Helpers in `test/helpers/` (metadata loader, in-memory cookie/settings storages). Services take injectable `client`/`packageInfoLoader`; widgets take injectable fetch/launch/action callbacks.
- **After adding native plugins: verify `flutter build apk --release`** — AGP/AndroidX metadata checks are stricter than debug, and the failure doesn't reproduce in a debug build.
- Widget-test gotchas seen repeatedly: `scrollUntilVisible` needs `scrollable: find.byType(Scrollable).first` when a TextField is present; follow with `ensureVisible` before tapping; cached_network_image leaves pending timers (end tests with `tester.pump(Duration(minutes: 1))`) and its spinners never settle (use fixed pumps).
