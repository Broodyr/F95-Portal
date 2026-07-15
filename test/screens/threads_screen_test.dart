import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/screens/threads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_settings_storage.dart';
import '../helpers/metadata_test_utils.dart';
import '../helpers/test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    loadAndInstallMetadata();
  });

  Future<List<SearchQuery>> pumpScreen(WidgetTester tester) async {
    final receivedQueries = <SearchQuery>[];

    recordingFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      receivedQueries.add(query);
      return createApiResponse();
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ThreadsScreen(bottomNavVisible: ValueNotifier(true), fetchThreads: recordingFetch),
      ),
    );
    await tester.pumpAndSettle();
    return receivedQueries;
  }

  testWidgets('starts from the default query in settings', (tester) async {
    final settings = installTestSettings();
    const defaults = SearchQuery(tags: [191]);
    await settings.update(settings.settings.copyWith(defaultQuery: defaults));

    final queries = await pumpScreen(tester);

    expect(queries, [defaults]);
  });

  testWidgets('adopts newly saved defaults while the search is untouched', (tester) async {
    final settings = installTestSettings();
    final queries = await pumpScreen(tester);
    expect(queries, [const SearchQuery()]);

    const newDefaults = SearchQuery(tags: [191, 225]);
    await settings.update(settings.settings.copyWith(defaultQuery: newDefaults));
    await tester.pumpAndSettle();

    expect(queries.last, newDefaults);
  });

  testWidgets('keeps a customized search when defaults change', (tester) async {
    final settings = installTestSettings();
    const defaults = SearchQuery(tags: [191]);
    await settings.update(settings.settings.copyWith(defaultQuery: defaults));

    final queries = await pumpScreen(tester);
    expect(queries, [defaults]);

    // Remove the default tag's chip from the filters bar: the search now
    // differs from the saved default, i.e. the user customized it.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(queries.last, const SearchQuery());

    const newDefaults = SearchQuery(tags: [225]);
    await settings.update(settings.settings.copyWith(defaultQuery: newDefaults));
    await tester.pumpAndSettle();

    expect(queries.last, const SearchQuery());
  });
}
