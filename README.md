# F95Zone Portal - Flutter Mobile App

## Overview
A Flutter mobile app for browsing F95Zone content.
Design is inspired by iOS with glassmorphism, floating navigation, and gesture-based scrolling.

**Status**: Early development — only the *Games* screen is partially implemented.

## Features
- **Modern UI**: Floating nav, glassmorphism, blur effects
- **Gesture Pass-Through**: Scroll content via floating elements
- **Live Data**: F95Zone API integration for game listings
- **Game Management**: Status indicators (Completed, Abandoned, Onhold)
- **Engine Support**: Color-coded tags for 12+ engines (Ren’Py, Unity, RPGM, etc.)
- **Game Cards**: Cover art, ratings, metadata

## Core Components
### MainApp (`lib/main_app.dart`)
Root widget handling navigation & scroll control.
- Central `ScrollController`
- Bottom nav bar
- Stack layout for floating UI

### GamesScreen (`lib/screens/games_screen.dart`)
Primary screen for game listings.
- Integrates `ScrollController`
- Floating Action Buttons linked to scroll

### GamesList (`lib/widgets/games_list.dart`)
Scrollable list of game cards.
- API integration
- Pull-to-refresh
- External scroll control

### GameCard (`lib/widgets/game_card.dart`)
Individual game entry.
- 3:1 aspect ratio cover images
- Engine + status tags
- Star ratings & metadata

### Gesture System
- **CustomBottomNavigation** (`widgets/bottom_navigation.dart`): Floating pill nav with scroll-through gestures
- **GlassmorphicFabs** (`widgets/glassmorphic_fabs.dart`): FABs with scroll control
- **Manual Scroll Control**: Shared `ScrollController` with `jumpTo()`

## Design System
See [`./docs/api_mappings.md`](./docs/api_mappings.md)

## Development
### Prerequisites
- Flutter (latest stable)
- Dart 3.0+
- Android Studio or VS Code
- Emulator/device for testing

### Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.2.2
  cached_network_image: ^3.4.1
````

### Run

```bash
flutter pub get
flutter run
```

## API

* **Endpoint**: `https://f95zone.to/sam/latest_alpha/latest_data.php`
* **Method**: GET
* **Response**: JSON with game listings

### Data Model (`GameThread`)

```dart
class GameThread {
  final int id;
  final String title;
  final String? imageUrl;
  final List<String> tags;
  final double? rating;
  final String? version;
  final bool isCompleted;
  final bool isAbandoned;
  final bool isOnhold;
  final DateTime? lastUpdate;
  final int? likesCount;
  final int? viewsCount;
  // ... additional fields
}
```

## Roadmap

* Filtering system
* Advanced search
* User authentication (F95Zone accounts)
* Favorites & bookmarks
* Forum browsing
* Settings & themes
