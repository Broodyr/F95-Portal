import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/widgets/active_filters_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';
import '../helpers/widget_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    loadAndInstallMetadata();
  });

  const query = SearchQuery(
    category: SearchCategory.games,
    search: 'goblin',
    creator: 'SomeDev',
    tags: [225],
    notags: [258],
    prefixes: [116],
    sort: SortOrder.likes,
  );

  testWidgets('renders a chip for every active filter plus the result count', (tester) async {
    await pumpTestApp(
      tester,
      ActiveFiltersBar(query: query, resultCount: 1247, onQueryChanged: (_) {}),
    );

    expect(find.text('"goblin"'), findsOneWidget);
    expect(find.text('SomeDev'), findsOneWidget);
    expect(find.text('pregnancy'), findsOneWidget);
    expect(find.text('netorare'), findsOneWidget);
    expect(find.text('Godot'), findsOneWidget);
    expect(find.text('Sort: Likes'), findsOneWidget);
    expect(find.text('1.2K results'), findsOneWidget);
  });

  testWidgets('removing a single chip updates only that filter', (tester) async {
    SearchQuery? updated;
    await pumpTestApp(
      tester,
      ActiveFiltersBar(query: query, resultCount: null, onQueryChanged: (q) => updated = q),
    );

    await tester.tap(find.text('pregnancy'));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.tags, isEmpty);
    expect(updated!.notags, [258]);
    expect(updated!.search, 'goblin');
    expect(updated!.sort, SortOrder.likes);
  });

  testWidgets('removing the sort chip resets sort to date', (tester) async {
    SearchQuery? updated;
    const sortOnly = SearchQuery(tags: [225], sort: SortOrder.likes);
    await pumpTestApp(
      tester,
      ActiveFiltersBar(query: sortOnly, resultCount: null, onQueryChanged: (q) => updated = q),
    );

    await tester.tap(find.text('Sort: Likes'));
    await tester.pumpAndSettle();

    expect(updated!.sort, SortOrder.date);
    expect(updated!.tags, [225]);
  });

  testWidgets('date limit renders as a chip and removal clears it', (tester) async {
    SearchQuery? updated;
    const dated = SearchQuery(dateDays: 30);
    await pumpTestApp(
      tester,
      ActiveFiltersBar(query: dated, resultCount: null, onQueryChanged: (q) => updated = q),
    );

    await tester.tap(find.text('Updated: 30d'));
    await tester.pumpAndSettle();

    expect(updated!.dateDays, isNull);
  });

  testWidgets('clear all resets everything except the category', (tester) async {
    SearchQuery? updated;
    const comicsQuery = SearchQuery(category: SearchCategory.comics, tags: [225], search: 'x');
    await pumpTestApp(
      tester,
      ActiveFiltersBar(query: comicsQuery, resultCount: 5, onQueryChanged: (q) => updated = q),
    );

    await tester.tap(find.byTooltip('Clear all filters'));
    await tester.pumpAndSettle();

    expect(updated, const SearchQuery(category: SearchCategory.comics));
  });
}
