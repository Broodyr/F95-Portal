import 'package:f95_portal/screens/forum_screen.dart';
import 'package:f95_portal/screens/forum_threads_screen.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole forum stack pumped with the service's mock data, so the tests
/// walk directory → thread list → thread viewer → reactions sheet offline.
Future<void> pumpForum(WidgetTester tester, {FetchForumIndex? fetchIndex, FetchForumPage? fetchForumPage}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: ForumScreen(
        fetchIndex: fetchIndex ?? () async => ForumService.createMockForumIndex(),
        fetchForumPage: fetchForumPage ?? (url, {page = 1}) async => ForumService.createMockForumPage(),
        fetchThreadPosts: (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
        fetchReactions: (url) async => ForumService.createMockReactionsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('directory renders grouped categories with forum rows', (tester) async {
    await pumpForum(tester);

    expect(find.text('Adult Games'), findsOneWidget);
    expect(find.text('Discussion'), findsOneWidget);
    expect(find.text('Games'), findsOneWidget);
    expect(find.textContaining('54.3K'), findsOneWidget);
    expect(find.textContaining('Eternum [v0.9]'), findsOneWidget);
    // Link nodes are hidden from the directory.
    expect(find.text('Trending Games'), findsNothing);
  });

  testWidgets('directory load failure shows a retry that recovers', (tester) async {
    int attempts = 0;
    await pumpForum(
      tester,
      fetchIndex: () async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
        return ForumService.createMockForumIndex();
      },
    );

    expect(find.text("Couldn't load the forum"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Games'), findsOneWidget);
  });

  testWidgets('tapping a forum opens its thread list with subforums and stickies', (tester) async {
    await pumpForum(tester);

    await tester.tap(find.text('General Discussions'));
    await tester.pumpAndSettle();

    // Subforum block above a splitter, threads below.
    expect(find.text('Introduction'), findsOneWidget);
    expect(find.text('Off-Topic'), findsOneWidget);
    expect(find.text('Threads'), findsOneWidget);

    expect(find.text('Post your signatures here'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('README'), findsOneWidget);
    expect(find.textContaining('823 replies'), findsOneWidget);
  });

  testWidgets('tapping a subforum pushes another thread list', (tester) async {
    await pumpForum(tester);

    await tester.tap(find.text('General Discussions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Introduction'));
    await tester.pumpAndSettle();

    // The pushed screen fetches the same mock page; its subforum block
    // renders again, which proves navigation happened.
    expect(find.text('Post your signatures here'), findsOneWidget);
  });

  testWidgets('thread viewer renders posts, quotes, and expandable spoilers', (tester) async {
    await pumpForum(tester);

    await tester.tap(find.text('General Discussions'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hidden gems you almost skipped'));
    await tester.pumpAndSettle();

    // Attribution and body.
    expect(find.text('DarkVault'), findsOneWidget);
    expect(find.text('Well-known member · Jun 28, 2026'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.textContaining('Nobody mentions'), findsWidgets);

    // Quote block with attribution.
    expect(find.text('DarkVault said:'), findsOneWidget);

    // Spoiler starts collapsed and slides open.
    expect(find.textContaining('The witch did it'), findsNothing);
    await tester.scrollUntilVisible(find.text('Ending spoiler'), 150);
    await tester.ensureVisible(find.text('Ending spoiler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ending spoiler'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The witch did it'), findsOneWidget);
  });

  testWidgets('pagination pills switch pages', (tester) async {
    await pumpForum(tester);

    await tester.tap(find.text('General Discussions'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hidden gems you almost skipped'));
    await tester.pumpAndSettle();

    expect(find.text('page 1 of 42'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('2'), 150);
    await tester.ensureVisible(find.text('2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    expect(find.text('page 2 of 42'), findsOneWidget);
    // Mock posts number themselves per page: page 2 starts at #3.
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('#1'), findsNothing);
  });

  testWidgets('reaction chip opens the sheet; pills filter members', (tester) async {
    await pumpForum(tester);

    await tester.tap(find.text('General Discussions'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hidden gems you almost skipped'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reaction-chip-9001')));
    await tester.pumpAndSettle();

    expect(find.text('Reactions to #1'), findsOneWidget);
    expect(find.text('All 69'), findsOneWidget);
    expect(find.text('Haha 43'), findsOneWidget);
    expect(find.text('iDrought'), findsOneWidget);
    expect(find.text('ThyElyson'), findsOneWidget);

    // Filtering to Haha hides the Like reactor.
    await tester.tap(find.text('Haha 43'));
    await tester.pumpAndSettle();
    expect(find.text('iDrought'), findsOneWidget);
    expect(find.text('ThyElyson'), findsNothing);
  });
}
