import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/app_text_scale.dart';
import 'package:f95_portal/widgets/search_options_sheet.dart';
import 'package:f95_portal/widgets/segmented_selector.dart';
import 'package:f95_portal/widgets/sliding_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_settings_storage.dart';
import '../helpers/metadata_test_utils.dart';
import '../helpers/widget_test_utils.dart';

/// Pumps a host app with a button that opens the sheet; returns a getter for
/// the SearchQuery the sheet eventually pops with.
Future<SearchQuery? Function()> pumpSheet(
  WidgetTester tester, {
  SearchQuery initialQuery = const SearchQuery(),
  List<PopularTag> popularTags = const [],
}) async {
  SearchQuery? result;

  fakePopular({SearchCategory category = SearchCategory.games}) async => popularTags;

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => AppTextScale(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<SearchQuery>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SearchOptionsSheet(initialQuery: initialQuery, fetchPopularTags: fakePopular),
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

Future<void> submitSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Search'));
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
}

/// Scrolls the sheet body (the TextField contributes a second Scrollable,
/// so the default single-Scrollable lookup fails).
Future<void> scrollSheetTo(WidgetTester tester, Finder finder) async {
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

  testWidgets('large font scales contents but anchors the field and headers at 16pt', (tester) async {
    await SettingsService.instance.update(
      SettingsService.instance.settings.copyWith(fontSize: FontSizeOption.large),
    );
    await pumpSheet(tester);

    // Anchored: section headers and the search field hold their base size.
    expect(effectiveFontSize(tester, find.text('Sort by')), moreOrLessEquals(16));
    expect(effectiveFontSize(tester, find.text('Search titles, tags, creators…')), moreOrLessEquals(16));

    // Their contents still scale: a segmented label grows past its 12pt base.
    expect(effectiveFontSize(tester, find.text('Any')), moreOrLessEquals(12 * FontSizeOption.large.scale));

    // The submit button scales from its enlarged 18pt base.
    expect(effectiveFontSize(tester, find.text('Search')), moreOrLessEquals(18 * FontSizeOption.large.scale));
  });

  testWidgets('small font trims anchored elements by 1pt and keeps the big search button', (tester) async {
    await SettingsService.instance.update(
      SettingsService.instance.settings.copyWith(fontSize: FontSizeOption.small),
    );
    await pumpSheet(tester);

    expect(effectiveFontSize(tester, find.text('Sort by')), moreOrLessEquals(15));
    expect(effectiveFontSize(tester, find.text('Search titles, tags, creators…')), moreOrLessEquals(15));
    expect(effectiveFontSize(tester, find.text('Search')), moreOrLessEquals(18));
  });

  testWidgets('typing suggests tags; tapping one adds an include filter', (tester) async {
    final getResult = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'pregn');
    await tester.pumpAndSettle();

    expect(find.text('pregnancy'), findsWidgets);

    await tester.tap(find.text('pregnancy').first);
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query, isNotNull);
    expect(query!.tags, [225]);
    expect(query.notags, isEmpty);
    expect(query.search, isEmpty);
  });

  testWidgets('tapping a filter chip toggles it to an exclusion', (tester) async {
    final getResult = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'netorar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('netorare').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('netorare'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.notags, [258]);
    expect(query.tags, isEmpty);
  });

  testWidgets('engine and status prefixes are suggested too', (tester) async {
    final getResult = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'godot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Godot').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'complet');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').first);
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.prefixes, containsAll([116, 18]));
    expect(query.noprefixes, isEmpty);
  });

  testWidgets('creator suggestion converts the text into a creator filter', (tester) async {
    final getResult = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'Caribdis');
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Creator:'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.creator, 'Caribdis');
    expect(query.search, isEmpty);
  });

  testWidgets('title suggestion converts the text into a title filter', (tester) async {
    final getResult = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'goblin layer');
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Title:'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.search, 'goblin layer');
    expect(query.creator, isEmpty);
  });

  testWidgets('tag suggestions show their per-category match counts', (tester) async {
    await pumpSheet(tester, popularTags: const [PopularTag(tagId: 225, count: 4700)]);

    await tester.enterText(find.byType(TextField), 'pregn');
    await tester.pumpAndSettle();

    expect(find.text('pregnancy'), findsOneWidget);
    expect(find.text('4.7K'), findsOneWidget);
  });

  testWidgets('include tags are capped at 10, matching the API limit', (tester) async {
    final getResult = await pumpSheet(
      tester,
      initialQuery: const SearchQuery(tags: [30, 44, 45, 75, 103, 105, 107, 111, 130, 141]),
    );

    await tester.enterText(find.byType(TextField), 'netorar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('netorare').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.tags, hasLength(10));
    expect(query.tags, isNot(contains(258)));
  });

  testWidgets('match-any toggle appears with two include tags and round-trips', (tester) async {
    final getResult = await pumpSheet(tester, initialQuery: const SearchQuery(tags: [225, 103]));

    expect(find.text('Match: all'), findsOneWidget);

    await tester.tap(find.text('Match: all'));
    await tester.pumpAndSettle();
    expect(find.text('Match: any'), findsOneWidget);

    await submitSheet(tester);

    final query = getResult();
    expect(query!.anyTags, isTrue);
    expect(query.tags, [225, 103]);
  });

  testWidgets('match toggle is hidden with fewer than two include tags', (tester) async {
    await pumpSheet(tester, initialQuery: const SearchQuery(tags: [225]));

    expect(find.textContaining('Match:'), findsNothing);
  });

  testWidgets('date limit selection round-trips', (tester) async {
    final getResult = await pumpSheet(tester);

    await tester.ensureVisible(find.text('30d'));
    await tester.tap(find.text('30d'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.dateDays, 30);
  });

  testWidgets('leftover text in the field becomes the title search', (tester) async {
    final getResult = await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'goblin layer');
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.search, 'goblin layer');
  });

  testWidgets('initial query reconstructs chips and settings', (tester) async {
    final getResult = await pumpSheet(
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

    await submitSheet(tester);

    final query = getResult();
    expect(query!.tags, [225]);
    expect(query.noprefixes, [22]);
    expect(query.creator, 'SomeDev');
    expect(query.sort, SortOrder.rating);
  });

  testWidgets('popular tags appear once the empty field is focused', (tester) async {
    final getResult = await pumpSheet(tester, popularTags: const [PopularTag(tagId: 103, count: 999)]);

    // Compact until the user shows intent by focusing the field.
    expect(find.text('corruption'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('corruption'), findsOneWidget);

    await tester.tap(find.text('corruption'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.tags, [103]);
  });

  testWidgets('recent tags come first, popular tags fill the rest, duplicates collapse', (tester) async {
    final service = SettingsService.instance;
    await service.update(service.settings.copyWith(recentTags: [225]));

    final getResult = await pumpSheet(
      tester,
      popularTags: const [PopularTag(tagId: 225, count: 4700), PopularTag(tagId: 103, count: 999)],
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('Suggestions'), findsOneWidget);
    // 225 (pregnancy) is both recent and popular; it shows once, as a recent.
    expect(find.text('pregnancy'), findsOneWidget);
    expect(find.text('corruption'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);

    await tester.tap(find.text('pregnancy'));
    await tester.pumpAndSettle();
    await submitSheet(tester);

    expect(getResult()!.tags, [225]);
  });

  testWidgets('segmented labels shrink to fit instead of wrapping on narrow screens', (tester) async {
    // A narrow phone at the biggest font size is the worst case for the
    // four-way Category row ("Animations" is the widest label).
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await SettingsService.instance.update(
      SettingsService.instance.settings.copyWith(fontSize: FontSizeOption.large),
    );

    await pumpSheet(tester);

    // A wrapped label would make its track ~15px taller, so the Category row
    // must come out as tall as the Sort by row (within the sub-pixel drift
    // scaleDown introduces when rows shrink by different amounts).
    final categoryHeight = tester.getSize(find.byType(SegmentedSelector<SearchCategory>)).height;
    final sortHeight = tester.getSize(find.byType(SegmentedSelector<SortOrder>)).height;
    expect(categoryHeight, moreOrLessEquals(sortHeight, epsilon: 2));

    // And the widest label still renders on a single line.
    final animations = tester.renderObject<RenderParagraph>(find.text('Animations'));
    expect(animations.size.height, lessThan(2 * animations.text.style!.fontSize!));
  });

  testWidgets('category is an always-visible segmented row that round-trips', (tester) async {
    final getResult = await pumpSheet(tester);

    // No expanding needed: all four categories are tappable immediately.
    expect(find.text('Comics'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);

    await tester.tap(find.text('Comics'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    expect(getResult()!.category, SearchCategory.comics);
  });

  testWidgets('switching category drops prefixes that do not resolve there', (tester) async {
    // Godot (116) is a games-only engine prefix.
    final getResult = await pumpSheet(tester, initialQuery: const SearchQuery(prefixes: [116]));

    await tester.tap(find.text('Comics'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.category, SearchCategory.comics);
    expect(query.prefixes, isEmpty);
  });

  testWidgets('sort selection round-trips', (tester) async {
    final getResult = await pumpSheet(tester);

    await scrollSheetTo(tester, find.text('Rating'));
    await tester.tap(find.text('Rating'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.sort, SortOrder.rating);
  });

  testWidgets('segmented rows slide a single highlight pill to the tapped segment', (tester) async {
    await pumpSheet(tester);

    await scrollSheetTo(tester, find.text('Rating'));

    // One sliding highlight per segmented row: Category, Sort by, and
    // Updated within.
    final highlights = find.byKey(const Key('segment-highlight'));
    expect(highlights, findsNWidgets(3));

    // Default sort is Date — the first segment, so the pill sits hard left.
    AnimatedAlign sortHighlight() => tester.widget<AnimatedAlign>(highlights.at(1));
    expect(sortHighlight().alignment, const Alignment(-1, 0));

    await tester.tap(find.text('Rating'));
    await tester.pump();

    // Rating is the last of five segments; the same pill now targets the
    // far right and animates over a nonzero duration.
    expect(sortHighlight().alignment, const Alignment(1, 0));
    expect(sortHighlight().duration, greaterThan(Duration.zero));
    await tester.pumpAndSettle();
  });

  testWidgets('the suggestion dropdown slides open and closed', (tester) async {
    await pumpSheet(tester, popularTags: const [PopularTag(tagId: 103, count: 999)]);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    // The list mounts immediately and slides open.
    SlidingReveal dropdown() => tester.widget<SlidingReveal>(find.byKey(const Key('suggestion-dropdown')));
    expect(dropdown().visible, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('corruption'), findsOneWidget);

    // Unfocusing keeps the list mounted while it slides shut, then drops it.
    // (Focus changes apply after the frame, so pump twice to rebuild.)
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    expect(dropdown().visible, isFalse);
    expect(find.text('corruption'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('corruption'), findsNothing);
  });

  testWidgets('section bodies slide open and closed instead of popping', (tester) async {
    await pumpSheet(tester);

    await scrollSheetTo(tester, find.text('Engine'));
    expect(find.text('Godot'), findsNothing);

    await tester.tap(find.text('Engine'));
    await tester.pump();

    // The body mounts immediately and slides open.
    final reveal = tester.widget<SlidingReveal>(find.byKey(const Key('section-body-Engine')));
    expect(reveal.visible, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Godot'), findsOneWidget);

    // Collapsing keeps the content mounted while it slides shut, then
    // drops it so hidden pills don't linger in the tree.
    await tester.tap(find.text('Engine'));
    await tester.pump();
    expect(find.text('Godot'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Godot'), findsNothing);
  });

  testWidgets('engine pills cycle to include and the section lists the vocabulary', (tester) async {
    final getResult = await pumpSheet(tester);

    // Sections start collapsed; expand Engine first.
    await scrollSheetTo(tester, find.text('Engine'));
    await tester.tap(find.text('Engine'));
    await tester.pumpAndSettle();

    await scrollSheetTo(tester, find.text('Godot'));
    // The full engine vocabulary is visible without typing anything.
    expect(find.text('RPGM'), findsOneWidget);
    expect(find.text('Java'), findsOneWidget);

    await tester.tap(find.text('Godot'));
    await tester.pumpAndSettle();
    await submitSheet(tester);

    final query = getResult();
    expect(query!.prefixes, [116]);
    expect(query.noprefixes, isEmpty);
  });

  testWidgets('a second tap on a status pill turns it into an exclusion', (tester) async {
    final getResult = await pumpSheet(tester);

    await scrollSheetTo(tester, find.text('Status'));
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();

    await scrollSheetTo(tester, find.text('Abandoned'));
    await tester.tap(find.text('Abandoned'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abandoned'));
    await tester.pumpAndSettle();

    await submitSheet(tester);

    final query = getResult();
    expect(query!.noprefixes, [22]);
    expect(query.prefixes, isEmpty);
  });

  testWidgets('a third tap clears the prefix pill', (tester) async {
    final getResult = await pumpSheet(tester);

    await scrollSheetTo(tester, find.text('Engine'));
    await tester.tap(find.text('Engine'));
    await tester.pumpAndSettle();

    await scrollSheetTo(tester, find.text('Unity'));
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('Unity'));
      await tester.pumpAndSettle();
    }

    await submitSheet(tester);

    final query = getResult();
    expect(query!.prefixes, isEmpty);
    expect(query.noprefixes, isEmpty);
  });
}
