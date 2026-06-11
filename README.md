# F95Zone Portal

## Project Snapshot
- Early-stage Flutter prototype focused on the Threads feed; other bottom-nav tabs are placeholders that surface "coming soon".
- Targeting mobile builds (Android/iOS). Web builds always use seeded mock data due to CORS; mobile/desktop now surface API errors instead of silently falling back.
- Visual language leans toward glassmorphism: blurred surfaces, floating FABs, and nav elements that pass gestures through to underlying scroll content.

## Key Files & Responsibilities
- `lib/main.dart`: Entrypoint, edge-to-edge system UI setup, and dark theme definition.
- `lib/main_app.dart`: App shell with the shared `ScrollController`, `ValueNotifier` that hides/shows the nav bar, and tab switching logic.
- `lib/screens/threads_screen.dart`: Hosts the gradient background, `ThreadsList`, and floating search FAB column.
- `lib/widgets/threads_list.dart`: Stateful list that owns loading state, calls `ApiService.fetchThreads()`, exposes pull-to-refresh, and opens the detail modal.
- `lib/services/api_service.dart`: Wraps `https://f95zone.to/sam/latest_alpha/latest_data.php` (`cmd=list` for threads, `cmd=tags` for popular tags), with an optional mock fallback (`createMockData`).
- `lib/services/auth_service.dart`: Holds the F95Zone (XenForo) session cookies captured at login, persisted in platform secure storage; `ApiService` attaches them to every request, lifting the anonymous hourly rate limit.
- `lib/screens/login_screen.dart` / `lib/screens/profile_screen.dart`: In-app webview pointed at the real f95zone.to login page (captcha/2FA work natively) that captures the `xf_user` remember-me cookie, and the Profile tab hosting sign-in/sign-out.
- `lib/models/search_query.dart`: Immutable description of a feed/search request (category, title/creator search, tag/prefix include+exclude filters, sort) and its mapping to API query parameters.
- `lib/models/f95_metadata.dart`: Typed access to the bundled prefix/tag vocabulary (`assets/f95_metadata.json`), loaded once at startup; powers engine labels and search autocomplete.
- `lib/models/thread_summary.dart`: Strongly-typed model for API responses, including helpers for completion/abandoned/on-hold status flags and response scaffolding (`ApiResponse`, `Pagination`).
- `docs/api_mappings.md`: Verified reference for the API surface and the numeric prefix/tag vocabulary.

## Data Flow
1. `ThreadsScreen` owns the active `SearchQuery` (defaults to an unfiltered games feed); the search FAB opens `SearchOptionsModal`, which pops an updated query.
2. `ThreadsList` reloads whenever its query changes, awaiting `ApiService.fetchThreads(query: …)`.
3. `ApiService` maps the query onto the endpoint's parameters (`search`, `creator`, `tags[]`/`notags[]` ANDed, `prefixes[]`/`noprefixes[]` ORed, `sort`).
   - When `kIsWeb == true`, `createMockData()` is filtered client-side by the same query semantics to keep the UI flowing without network access. On other platforms the service throws `ApiException` on failure (unless `fallbackToMockOnError` is explicitly enabled).
4. The resolved `ApiResponse` populates `_threads`; list items render via `ThreadCard`, and pull-to-refresh re-runs `_loadThreads`.

`ThreadSummary` exposes `isCompleted`, `isAbandoned`, and `isOnhold` based on prefix IDs 18, 22, and 20 respectively.

## UI Building Blocks
- `ThreadCard` (`lib/widgets/thread_card.dart`): 3:1 cover art with mirrored reflection, segmented `EngineTag`, status-aware `VersionPill`, star rating badge, and a metadata row for formatted likes/views/time.
- `EngineTag` & `VersionPill`: Use `ThreadUtils` and `EngineColors` (`lib/utils/formatters.dart`) to map prefix/tag IDs to display strings and palette.
- `CustomBottomNavigation` (`lib/widgets/bottom_navigation.dart`): Glass pill nav with animated icons; vertical drags and taps pass through to the shared scroll controller for gesture continuity.
- `SearchFab` (`lib/widgets/search_fab.dart`): Floating search button that also forwards vertical drags to scrolling; opens `SearchOptionsModal`.
- `SearchOptionsModal` (`lib/widgets/search_options_modal.dart`): Omni-search bottom sheet — one field autocompletes tags, engines, statuses, and creators from the bundled vocabulary; selections become chips (tap toggles include/exclude, x removes), leftover text is the title search. Shows popular tags (live `cmd=tags`) while empty; pops a `SearchQuery`.
- `ThreadDetailsModal` (`lib/widgets/thread_details_modal.dart`): Draggable detail sheet opened on card tap — cover header with engine/version pills, stats row, screenshot strip (tap for the fullscreen pinch-zoom `ScreenshotGallery`), tag chips (tap adds the tag to the active search, long-press replaces it), and open-in-browser/share actions.
- `PreRenderedNoisyBackground` (`lib/widgets/noisy_background.dart`): Utility for caching a noise texture; the call is currently commented out in `ThreadsScreen`.

## Development Notes
- Toolchain: Flutter SDK 3.8.1+, Dart 3.8+ (`pubspec.yaml`).
- Dependencies in use: `http` (network), `cached_network_image` (cover caching), `flutter_staggered_grid_view` (reserved for upcoming layouts), `package_info_plus` (User-Agent versioning), `flutter_inappwebview` (login webview), `flutter_secure_storage` (session cookies), `cupertino_icons`.
- Install & run:
  ```bash
  flutter pub get
  flutter run
  ```
- Automated unit/service/widget tests live under `test/`; run `flutter test` (or the platform-specific helpers `tool/run_tests.sh` on macOS/Linux and `tool/run_tests.ps1` on Windows) so dependencies and toolchain setup stay consistent after every change.

## Test-Driven Development Workflow
- Write or update a failing test under `test/` before touching production code; mirror the lib structure (for example `test/services`, `test/widgets`).
- Reuse `test/helpers/test_data.dart` for realistic `ThreadSummary` fixtures and `test/helpers/widget_test_utils.dart` to wrap widgets in a minimal `MaterialApp`.
- Service tests can inject dependencies via the optional `client`/`packageInfoLoader` parameters on `ApiService.fetchThreads`; widget tests can pass a custom `fetchThreads` callback into `ThreadsList`.
- Keep feedback fast with `flutter test --coverage` (or the helper scripts in `tool/`), or scope runs to a single file (`flutter test test/widgets/threads_list_test.dart`) during active TDD loops.
- Aim to keep the suite green after each change set - tests double as living documentation for API contracts and UI states.

## Current Limitations & Next Actions
- Browse, Settings, and Profile tabs are wired up; only Forum still shows the placeholder.
- Settings (`lib/screens/settings_screen.dart` + `lib/services/settings_service.dart`): default search filters (edited via the same search modal, applied at startup and on filter-bar clear), popular-vs-recent empty-search suggestions, SFW cover blur (`lib/widgets/sfw_blur.dart`), and image cache clearing — persisted via shared_preferences.
- Forum tab is the last placeholder; the thread-page parser it needs already exists.
- Thread details are scraped live: `lib/services/thread_page_parser.dart` parses the first post (tolerant block model — meta fields, overview, generic spoiler sections, per-platform downloads with extras) and `lib/services/thread_page_service.dart` fetches/caches it; the modal renders whatever blocks exist. Parser is TDD'd against `test/fixtures/*.htm`.
- Consider introducing repository-level caching once live data usage stabilizes.
- Sign-in state shows no username/avatar yet — the latest_alpha endpoint exposes no profile info, so that needs scraping a forum page.
- Cover image aspect ratio is still being tweaked (docs say 4:1, `CoverImage` renders 3:1); settle during final design pass.

## Roadmap Seeds
- Filtering and advanced search that leverage the existing query-parameter hooks.
- User accounts (F95Zone auth), favorites/bookmarks, and broader forum browsing.
- Theme/setting personalization and richer detail views with screenshots and metadata.
