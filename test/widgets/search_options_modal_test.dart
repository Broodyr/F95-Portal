import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/widgets/search_options_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';

/// Pumps a host app with a button that opens the modal; returns a getter for
/// the SearchQuery the modal eventually pops with.
Future<SearchQuery? Function()> pumpModal(
  WidgetTester tester, {
  SearchQuery initialQuery = const SearchQuery(),
  List<PopularTag> popularTags = const [],
}) async {
  SearchQuery? result;

  fakePopular({SearchCategory category = SearchCategory.games}) async => popularTags;

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<SearchQuery>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SearchOptionsModal(initialQuery: initialQuery, fetchPopularTags: fakePopular),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  return () => result;
}

Future<void> submitModal(WidgetTester tester) async {
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    loadAndInstallMetadata();
  });

  testWidgets('typing suggests tags; tapping one adds an include filter', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.enterText(find.byType(TextField), 'pregn');
    await tester.pumpAndSettle();

    expect(find.text('pregnancy'), findsWidgets);

    await tester.tap(find.text('pregnancy').first);
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query, isNotNull);
    expect(query!.tags, [225]);
    expect(query.notags, isEmpty);
    expect(query.search, isEmpty);
  });

  testWidgets('tapping a filter chip toggles it to an exclusion', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.enterText(find.byType(TextField), 'netorar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('netorare').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('netorare'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.notags, [258]);
    expect(query.tags, isEmpty);
  });

  testWidgets('engine and status prefixes are suggested too', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.enterText(find.byType(TextField), 'godot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Godot').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'complet');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').first);
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.prefixes, containsAll([116, 18]));
    expect(query.noprefixes, isEmpty);
  });

  testWidgets('creator suggestion converts the text into a creator filter', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.enterText(find.byType(TextField), 'Caribdis');
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Creator:'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.creator, 'Caribdis');
    expect(query.search, isEmpty);
  });

  testWidgets('leftover text in the field becomes the title search', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.enterText(find.byType(TextField), 'goblin layer');
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.search, 'goblin layer');
  });

  testWidgets('initial query reconstructs chips and settings', (tester) async {
    final getResult = await pumpModal(
      tester,
      initialQuery: const SearchQuery(
        category: SearchCategory.games,
        tags: [225],
        noprefixes: [22],
        creator: 'SomeDev',
        sort: SortOrder.rating,
      ),
    );

    expect(find.text('pregnancy'), findsOneWidget);
    expect(find.text('Abandoned'), findsOneWidget);
    expect(find.textContaining('SomeDev'), findsOneWidget);

    await submitModal(tester);

    final query = getResult();
    expect(query!.tags, [225]);
    expect(query.noprefixes, [22]);
    expect(query.creator, 'SomeDev');
    expect(query.sort, SortOrder.rating);
  });

  testWidgets('popular tags appear as suggestions while the field is empty', (tester) async {
    final getResult = await pumpModal(tester, popularTags: const [PopularTag(tagId: 103, count: 999)]);

    expect(find.text('corruption'), findsOneWidget);

    await tester.tap(find.text('corruption'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.tags, [103]);
  });

  testWidgets('sort selection round-trips', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.tap(find.text('Rating'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.sort, SortOrder.rating);
  });
}
