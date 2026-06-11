import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/search_options_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_settings_storage.dart';
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
  await tester.ensureVisible(find.text('Search'));
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
}

/// Scrolls the sheet body (the TextField contributes a second Scrollable,
/// so the default single-Scrollable lookup fails).
Future<void> scrollModalTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    loadAndInstallMetadata();
  });

  late SettingsService previousSettings;

  setUp(() {
    previousSettings = SettingsService.instance;
    installTestSettings();
  });

  tearDown(() {
    SettingsService.instance = previousSettings;
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

  testWidgets('title suggestion converts the text into a title filter', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.enterText(find.byType(TextField), 'goblin layer');
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Title:'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.search, 'goblin layer');
    expect(query.creator, isEmpty);
  });

  testWidgets('tag suggestions show their per-category match counts', (tester) async {
    await pumpModal(tester, popularTags: const [PopularTag(tagId: 225, count: 4700)]);

    await tester.enterText(find.byType(TextField), 'pregn');
    await tester.pumpAndSettle();

    expect(find.text('pregnancy'), findsOneWidget);
    expect(find.text('4.7K'), findsOneWidget);
  });

  testWidgets('include tags are capped at 10, matching the API limit', (tester) async {
    final getResult = await pumpModal(
      tester,
      initialQuery: const SearchQuery(tags: [30, 44, 45, 75, 103, 105, 107, 111, 130, 141]),
    );

    await tester.enterText(find.byType(TextField), 'netorar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('netorare').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.tags, hasLength(10));
    expect(query.tags, isNot(contains(258)));
  });

  testWidgets('match-any toggle appears with two include tags and round-trips', (tester) async {
    final getResult = await pumpModal(tester, initialQuery: const SearchQuery(tags: [225, 103]));

    expect(find.text('Match: all'), findsOneWidget);

    await tester.tap(find.text('Match: all'));
    await tester.pumpAndSettle();
    expect(find.text('Match: any'), findsOneWidget);

    await submitModal(tester);

    final query = getResult();
    expect(query!.anyTags, isTrue);
    expect(query.tags, [225, 103]);
  });

  testWidgets('match toggle is hidden with fewer than two include tags', (tester) async {
    await pumpModal(tester, initialQuery: const SearchQuery(tags: [225]));

    expect(find.textContaining('Match:'), findsNothing);
  });

  testWidgets('date limit selection round-trips', (tester) async {
    final getResult = await pumpModal(tester);

    await tester.ensureVisible(find.text('30d'));
    await tester.tap(find.text('30d'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.dateDays, 30);
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

  testWidgets('popular tags appear once the empty field is focused', (tester) async {
    final getResult = await pumpModal(tester, popularTags: const [PopularTag(tagId: 103, count: 999)]);

    // Compact until the user shows intent by focusing the field.
    expect(find.text('corruption'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('corruption'), findsOneWidget);

    await tester.tap(find.text('corruption'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.tags, [103]);
  });

  testWidgets('recent tags replace popular ones when that source is selected', (tester) async {
    final service = SettingsService.instance;
    await service.update(
      service.settings.copyWith(suggestionSource: SuggestionSource.recent, recentTags: [225, 103]),
    );

    final getResult = await pumpModal(tester, popularTags: const [PopularTag(tagId: 130, count: 999)]);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('pregnancy'), findsOneWidget);
    expect(find.text('corruption'), findsOneWidget);
    expect(find.text('big tits'), findsNothing);
    expect(find.textContaining('Recent tags'), findsOneWidget);

    await tester.tap(find.text('pregnancy'));
    await tester.pumpAndSettle();
    await submitModal(tester);

    expect(getResult()!.tags, [225]);
  });

  testWidgets('sort selection round-trips', (tester) async {
    final getResult = await pumpModal(tester);

    await scrollModalTo(tester, find.text('Rating'));
    await tester.tap(find.text('Rating'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.sort, SortOrder.rating);
  });

  testWidgets('engine pills cycle to include and the section lists the vocabulary', (tester) async {
    final getResult = await pumpModal(tester);

    await scrollModalTo(tester, find.text('Godot'));
    // The full engine vocabulary is visible without typing anything.
    expect(find.text('RPGM'), findsOneWidget);
    expect(find.text('Java'), findsOneWidget);

    await tester.tap(find.text('Godot'));
    await tester.pumpAndSettle();
    await submitModal(tester);

    final query = getResult();
    expect(query!.prefixes, [116]);
    expect(query.noprefixes, isEmpty);
  });

  testWidgets('a second tap on a status pill turns it into an exclusion', (tester) async {
    final getResult = await pumpModal(tester);

    await scrollModalTo(tester, find.text('Abandoned'));
    await tester.tap(find.text('Abandoned'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abandoned'));
    await tester.pumpAndSettle();

    await submitModal(tester);

    final query = getResult();
    expect(query!.noprefixes, [22]);
    expect(query.prefixes, isEmpty);
  });

  testWidgets('a third tap clears the prefix pill', (tester) async {
    final getResult = await pumpModal(tester);

    await scrollModalTo(tester, find.text('Unity'));
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('Unity'));
      await tester.pumpAndSettle();
    }

    await submitModal(tester);

    final query = getResult();
    expect(query!.prefixes, isEmpty);
    expect(query.noprefixes, isEmpty);
  });
}
