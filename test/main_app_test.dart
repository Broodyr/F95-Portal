import 'package:f95_portal/main_app.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/screens/settings_screen.dart';
import 'package:f95_portal/screens/browse_screen.dart';
import 'package:f95_portal/widgets/bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/in_memory_settings_storage.dart';
import 'helpers/metadata_test_utils.dart';
import 'helpers/test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    loadAndInstallMetadata();
  });

  // The nav bar's active item pulses forever, so pumpAndSettle never
  // settles inside MainApp; every wait below uses bounded pumps instead.
  Future<ScrollPosition> pumpApp(WidgetTester tester, {int threadCount = 30}) async {
    installTestSettings();
    final threads = List.generate(threadCount, (i) => createBrowseThread(threadId: i + 1, title: 'Thread ${i + 1}'));

    mockFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return createApiResponse(threads: threads, count: threads.length);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MainApp(fetchThreads: mockFetch),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final scrollable = find.descendant(of: find.byType(BrowseScreen), matching: find.byType(Scrollable)).first;
    return tester.state<ScrollableState>(scrollable).position;
  }

  testWidgets('re-tapping Browse while on it scrolls the list back to the top', (tester) async {
    final position = await pumpApp(tester);

    // Jump (rather than drag) so the nav bar stays visible for the tap.
    position.jumpTo(600);
    await tester.pump();
    expect(position.pixels, greaterThan(0));

    await tester.tap(find.byIcon(Icons.explore));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(position.pixels, 0);
  });

  /// The nav bar's on-screen rect; when hidden it animates fully below the
  /// 600pt test surface.
  Rect navBarRect(WidgetTester tester) => tester.getRect(find.byType(CustomBottomNavigation));

  Finder tabScrollable(Type screen) =>
      find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first;

  testWidgets('scrolling the Settings tab hides the nav bar and scrolling back shows it', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(seconds: 1));

    await tester.drag(tabScrollable(SettingsScreen), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBarRect(tester).top, greaterThanOrEqualTo(600));

    await tester.drag(tabScrollable(SettingsScreen), const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(navBarRect(tester).bottom, lessThanOrEqualTo(600));
  });

  testWidgets('nav bar drags scroll through to the active tab, not just Browse', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(seconds: 1));

    final settingsPosition = tester.state<ScrollableState>(tabScrollable(SettingsScreen)).position;
    expect(settingsPosition.pixels, 0);

    // A point on the nav bar background, between the third and fourth items.
    await tester.dragFrom(const Offset(400, 570), const Offset(0, -150));
    await tester.pump();

    expect(settingsPosition.pixels, greaterThan(0));
  });

  testWidgets('a page that fits on screen never hides the nav bar', (tester) async {
    final position = await pumpApp(tester, threadCount: 1);
    expect(position.maxScrollExtent, 0);

    await tester.drag(tabScrollable(BrowseScreen), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(navBarRect(tester).bottom, lessThanOrEqualTo(600));
  });

  testWidgets('re-tapping the active Settings tab scrolls its list back to the top', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(seconds: 1));

    final settingsPosition = tester.state<ScrollableState>(tabScrollable(SettingsScreen)).position;
    settingsPosition.jumpTo(200);
    await tester.pump();
    expect(settingsPosition.pixels, 200);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(settingsPosition.pixels, 0);
  });

  testWidgets('returning to Browse from another tab keeps the scroll offset', (tester) async {
    final position = await pumpApp(tester);

    position.jumpTo(600);
    await tester.pump();
    final offset = position.pixels;
    expect(offset, greaterThan(0));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pump(const Duration(seconds: 1));

    expect(position.pixels, offset);
  });
}
