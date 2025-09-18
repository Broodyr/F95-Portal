# F95Zone Portal

## Project Snapshot
- Early-stage Flutter prototype focused on the Games feed; other bottom-nav tabs are placeholders that surface "coming soon".
- Targeting mobile builds (Android/iOS). Web builds always use seeded mock data due to CORS; mobile/desktop now surface API errors instead of silently falling back.
- Visual language leans toward glassmorphism: blurred surfaces, floating FABs, and nav elements that pass gestures through to underlying scroll content.

## Key Files & Responsibilities
- `lib/main.dart`: Entrypoint, edge-to-edge system UI setup, and dark theme definition.
- `lib/main_app.dart`: App shell with the shared `ScrollController`, `ValueNotifier` that hides/shows the nav bar, and tab switching logic.
- `lib/screens/games_screen.dart`: Hosts the gradient background, `GamesList`, and floating glassmorphic FAB column.
- `lib/widgets/games_list.dart`: Stateful list that owns loading state, calls `ApiService.fetchGames()`, exposes pull-to-refresh, and opens the detail modal.
- `lib/services/api_service.dart`: Wraps `https://f95zone.to/sam/latest_alpha/latest_data.php` with default query params, custom headers, and an optional mock fallback (`createMockData`).
- `lib/models/game_thread.dart`: Strongly-typed model for API responses, including helpers for completion/abandoned/on-hold status flags and response scaffolding (`ApiResponse`, `Pagination`).
- `docs/api_mappings.md`: Running catalog of numeric prefix/tag IDs mapped to engine/status semantics used by `GameUtils`.

## Data Flow
1. `GamesList` runs `_loadGames`, which awaits `ApiService.fetchGames()`.
2. `ApiService` builds the request from default filter parameters (`cmd=list`, `cat=games`, prefix/tag filters, `rows=90`) and tries the live endpoint.
   - When `kIsWeb == true`, `createMockData()` returns a curated set of `GameThread` objects to keep the UI flowing without network access. On other platforms the service throws `ApiException` on failure (unless `fallbackToMockOnError` is explicitly enabled).
3. The resolved `ApiResponse` populates `_games`; list items render via `GameCard`, and pull-to-refresh re-runs `_loadGames`.

`GameThread` exposes `isCompleted`, `isAbandoned`, and `isOnhold` based on prefix IDs 18, 22, and 20 respectively.

## UI Building Blocks
- `GameCard` (`lib/widgets/game_card.dart`): 3:1 cover art with mirrored reflection, segmented `EngineTag`, status-aware `VersionPill`, star rating badge, and a metadata row for formatted likes/views/time.
- `EngineTag` & `VersionPill`: Use `GameUtils` and `EngineColors` (`lib/utils/formatters.dart`) to map prefix/tag IDs to display strings and palette.
- `CustomBottomNavigation` (`lib/widgets/bottom_navigation.dart`): Glass pill nav with animated icons; vertical drags and taps pass through to the shared scroll controller for gesture continuity.
- `GlassmorphicFabs` (`lib/widgets/glassmorphic_fabs.dart`): Floating filter/search buttons that also forward vertical drags to scrolling; callbacks currently stubbed for future filter/search modals.
- `GameDetailsModal` (`lib/widgets/game_details_modal.dart`): Bottom sheet placeholder opened on card tap, ready for richer detail content.
- `PreRenderedNoisyBackground` (`lib/widgets/noisy_background.dart`): Utility for caching a noise texture; the call is currently commented out in `GamesScreen`.

## Development Notes
- Toolchain: Flutter SDK 3.8.1+, Dart 3.8+ (`pubspec.yaml`).
- Dependencies in use: `http` (network), `cached_network_image` (cover caching), `flutter_staggered_grid_view` (reserved for upcoming layouts), `cupertino_icons`.
- Install & run:
  ```bash
  flutter pub get
  flutter run
  ```
- There are no automated tests yet; manual QA is required after feature changes.

## Current Limitations & Next Actions
- Only the Games tab is wired up; other tabs trigger snackbars and placeholder screens.
- Filter/search UX is not implemented; wire `GlassmorphicFabs` callbacks once designs are ready.
- `GameDetailsModal` contains placeholder messaging.
- Engine and tag mappings in `GameUtils` are incomplete and based on a small sample set; update alongside `docs/api_mappings.md` as more API data is observed.
- Networking lacks pagination, rich error messaging, and auth/session handling; consider introducing repository-level caching once live data usage stabilizes.

## Roadmap Seeds
- Filtering and advanced search that leverage the existing query-parameter hooks.
- User accounts (F95Zone auth), favorites/bookmarks, and broader forum browsing.
- Theme/setting personalization and richer detail views with screenshots and metadata.
