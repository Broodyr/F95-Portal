import 'package:f95_portal/main_app.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/screens/threads_screen.dart';
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
  Future<ScrollPosition> pumpApp(WidgetTester tester) async {
    installTestSettings();
    final threads = List.generate(30, (i) => createThreadSummary(threadId: i + 1, title: 'Thread ${i + 1}'));

    mockFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return createApiResponse(threads: threads, count: threads.length);
    }

    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: MainApp(fetchThreads: mockFetch)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final scrollable = find.descendant(of: find.byType(ThreadsScreen), matching: find.byType(Scrollable)).first;
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
