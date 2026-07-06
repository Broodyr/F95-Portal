import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/screens/forum_screen.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/screens/forum_threads_screen.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole forum stack pumped with the service's mock data, so the tests
/// walk directory → thread list → thread viewer → reactions sheet offline.
Future<void> pumpForum(
  WidgetTester tester, {
  FetchForumIndex? fetchIndex,
  FetchForumPage? fetchForumPage,
  FetchThreadPosts? fetchThreadPosts,
  ReactSender? reactSender,
  ReplySender? replySender,
  ThreadPoster? threadPoster,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: ForumScreen(
        fetchIndex: fetchIndex ?? () async => ForumService.createMockForumIndex(),
        fetchForumPage: fetchForumPage ?? (url, {page = 1}) async => ForumService.createMockForumPage(),
        fetchThreadPosts: fetchThreadPosts ?? (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
        fetchReactions: (url) async => ForumService.createMockReactionsPage(),
        reactSender: reactSender,
        replySender: replySender,
        threadPoster: threadPoster,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Directory → General Discussions → the mock thread's viewer.
Future<void> openThreadViewer(WidgetTester tester) async {
  await tester.tap(find.text('General Discussions'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Hidden gems you almost skipped'));
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

  testWidgets('React opens the picker and sends the picked reaction', (tester) async {
    final reacted = <(int, int, String)>[];
    await pumpForum(tester, reactSender: (postId, reactionId, csrf) async => reacted.add((postId, reactionId, csrf)));
    await openThreadViewer(tester);

    await tester.tap(find.text('React').first);
    await tester.pumpAndSettle();
    expect(find.text('Yay, update!'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pick-reaction-14')));
    await tester.pumpAndSettle();

    expect(reacted, [(9001, 14, 'mock-csrf')]);
  });

  testWidgets('Quote prefills the composer; posting sends the reply', (tester) async {
    final replies = <(String, String, String)>[];
    await pumpForum(tester, replySender: (url, csrf, message) async => replies.add((url, csrf, message)));
    await openThreadViewer(tester);

    await tester.tap(find.text('Quote').first);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const Key('composer-message')));
    expect(field.controller!.text, contains('[QUOTE="DarkVault, post: 9001"]'));
    expect(field.controller!.text, contains('Nobody mentions Wands & Witches'));

    await tester.tap(find.text('Post reply'));
    await tester.pumpAndSettle();

    expect(replies, hasLength(1));
    expect(replies.single.$1, 'https://example.com/threads/188349/add-reply');
    expect(replies.single.$2, 'mock-csrf');
    expect(replies.single.$3, contains('[/QUOTE]'));
  });

  testWidgets('the reply FAB opens the composer and posts the message', (tester) async {
    final replies = <String>[];
    await pumpForum(tester, replySender: (url, csrf, message) async => replies.add(message));
    await openThreadViewer(tester);

    await tester.tap(find.byTooltip('Reply'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('composer-message')), 'Nice thread!');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post reply'));
    await tester.pumpAndSettle();

    expect(replies, ['Nice thread!']);
  });

  testWidgets('write actions are hidden when the page has no reply URL', (tester) async {
    await pumpForum(
      tester,
      fetchThreadPosts: (url, {page = 1}) async => const ThreadPostsPage(
        title: 'Guest view',
        posts: [ForumPost(postId: 1, number: 1, author: 'A')],
      ),
    );
    await openThreadViewer(tester);

    expect(find.text('React'), findsNothing);
    expect(find.text('Quote'), findsNothing);
    expect(find.byTooltip('Reply'), findsNothing);
  });

  testWidgets('the new-thread FAB posts a titled thread', (tester) async {
    final posted = <(String, String, String, String)>[];
    await pumpForum(
      tester,
      threadPoster: (url, csrf, {required title, required message}) async => posted.add((url, csrf, title, message)),
    );

    await tester.tap(find.text('General Discussions'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New thread'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('composer-title')), 'Hello forum');
    await tester.enterText(find.byKey(const Key('composer-message')), 'First post!');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post thread'));
    await tester.pumpAndSettle();

    expect(posted, [
      ('https://example.com/forums/general-discussions.9/post-thread', 'mock-csrf', 'Hello forum', 'First post!'),
    ]);
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
