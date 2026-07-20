import 'package:f95_portal/models/account.dart';
import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/screens/alerts_screen.dart';
import 'package:f95_portal/screens/bookmarks_screen.dart';
import 'package:f95_portal/screens/forum_screen.dart';
import 'package:f95_portal/screens/forum_search_screen.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/screens/forum_threads_screen.dart';
import 'package:f95_portal/screens/profile_screen.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:f95_portal/widgets/glass_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cookie_storage.dart';
import '../helpers/widget_test_utils.dart';

/// Swaps in a signed-in in-memory auth session for one test.
Future<void> signIn() async {
  final previousAuth = AuthService.instance;
  addTearDown(() => AuthService.instance = previousAuth);
  AuthService.instance = AuthService(InMemoryCookieStorage());
  await AuthService.instance.saveCookies({'xf_user': 'tok'});
}

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
  ForumSearcher? searcher,
  ForumSearchPager? searchPager,
  FetchBookmarks? fetchBookmarks,
  BookmarkDeleter? bookmarkDeleter,
  FetchAlerts? fetchAlerts,
  AlertsAcknowledger? alertsAcknowledger,
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
        searcher:
            searcher ??
            (keywords, {titleOnly = false, user = '', order = 'relevance'}) async =>
                ForumService.createMockSearchPage(),
        searchPager: searchPager ?? (url, page) async => ForumService.createMockSearchPage(page: page),
        fetchBookmarks: fetchBookmarks ?? ({page = 1}) async => ForumService.createMockBookmarks(page: page),
        bookmarkDeleter: bookmarkDeleter,
        fetchAlerts: fetchAlerts ?? ({page = 1}) async => ForumService.createMockAlerts(page: page),
        alertsAcknowledger: alertsAcknowledger ?? (ids) async {},
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

  testWidgets('deleting an own post confirms first, then reloads the thread', (tester) async {
    final deleted = <(String, String)>[];
    int fetches = 0;
    const thread = ThreadPostsPage(
      title: 'T',
      csrfToken: 'tok',
      posts: [
        ForumPost(postId: 1, number: 1, author: 'Someone'),
        ForumPost(
          postId: 2,
          number: 2,
          author: 'Broodyr',
          editUrl: 'https://f95zone.to/posts/2/edit',
          deleteUrl: 'https://f95zone.to/posts/2/delete',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/t.1/',
          title: 'T',
          fetchPosts: (url, {page = 1}) async {
            fetches++;
            return thread;
          },
          deleteSender: (url, csrf) async => deleted.add((url, csrf)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Only the viewer's own post offers it.
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete post?'), findsOneWidget);

    // Backing out sends nothing.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);

    final before = fetches;
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted.single, ('https://f95zone.to/posts/2/delete', 'tok'));
    expect(fetches, greaterThan(before), reason: 'the thread refetches so the post disappears');
  });

  // The dialog has its own tests; this covers the wiring between them — that
  // the overflow exists on a post and hands the dialog that post's permalink.
  testWidgets('a post overflow opens the report dialog for that post', (tester) async {
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/t.1/',
          title: 'T',
          fetchPosts: (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
          reportFormFetcher: (url) async {
            requested = url;
            return ForumService.createMockReportForm();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Post tools').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report…'));
    await tester.pumpAndSettle();

    expect(requested, matches(RegExp(r'^https://f95zone\.to/posts/\d+/report$')));
    expect(find.text('Report content'), findsOneWidget);
    expect(find.text('Game update'), findsOneWidget);
  });

  testWidgets('tapping a post author opens their profile', (tester) async {
    await pumpForum(tester);
    await openThreadViewer(tester);

    await tester.tap(find.text('DarkVault').first);
    await tester.pumpAndSettle();

    final profile = tester.widget<ProfileScreen>(find.byType(ProfileScreen));
    expect(profile.url, 'https://example.com/members/darkvault.4242/');
    expect(profile.username, 'DarkVault');
    // Logged out in this test, so the pushed profile asks to sign in.
    expect(find.textContaining('to view member profiles.'), findsOneWidget);
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
    expect(field.controller!.text, contains('[QUOTE="DarkVault, post: 9001, member: 4242"]'));
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

  testWidgets('the reply FAB is a 56pt glass button riding one row above the search FAB spot', (tester) async {
    await pumpForum(tester);
    await openThreadViewer(tester);

    final fab = find.byType(GlassFab);
    expect(fab, findsOneWidget);
    final rect = tester.getRect(fab);
    final screen = tester.getRect(find.byType(Scaffold).last);
    expect(rect.size, const Size(56, 56));
    expect(screen.right - rect.right, 32);
    expect(screen.bottom - rect.bottom, 88);
  });

  testWidgets('the new-thread FAB is a 56pt glass button anchored at the search FAB spot', (tester) async {
    await pumpForum(tester);
    await tester.tap(find.text('General Discussions'));
    await tester.pumpAndSettle();

    final fab = find.byType(GlassFab);
    expect(fab, findsOneWidget);
    final rect = tester.getRect(fab);
    final screen = tester.getRect(find.byType(Scaffold).last);
    expect(rect.size, const Size(56, 56));
    expect(screen.right - rect.right, 32);
    expect(screen.bottom - rect.bottom, 24);
  });

  testWidgets('the composer BBCode link opens the cheatsheet dialog', (tester) async {
    await pumpForum(tester);
    await openThreadViewer(tester);

    await tester.tap(find.byTooltip('Reply'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('composer-bbcode-help')));
    await tester.pumpAndSettle();

    expect(find.text('BBCode cheatsheet'), findsOneWidget);
    expect(find.text('[b]bold[/b]'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('[spoiler=Title]hidden[/spoiler]'),
      60,
      scrollable: find.descendant(
        of: find.byKey(const Key('bbcode-cheatsheet-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('[spoiler=Title]hidden[/spoiler]'), findsOneWidget);
    expect(find.text('[quote="name"]text[/quote]'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('BBCode cheatsheet'), findsNothing);
    // The composer is still open underneath.
    expect(find.byKey(const Key('composer-message')), findsOneWidget);
  });

  testWidgets('the composer submit button uses the enlarged 18pt CTA label', (tester) async {
    await pumpForum(tester);
    await openThreadViewer(tester);

    await tester.tap(find.byTooltip('Reply'));
    await tester.pumpAndSettle();

    expect(effectiveFontSize(tester, find.text('Post reply')), moreOrLessEquals(18));
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
    // Watch gates on its member-only anchor, absent from guest pages.
    expect(find.byTooltip('Watch thread'), findsNothing);
  });

  testWidgets('a post permalink lands on its real page, scrolls to the post, and paginates', (tester) async {
    final fetched = <(String, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/posts/508/',
          title: 'Hidden gems',
          // The server redirects post permalinks to their thread page; the
          // fake lands page-3 content for the permalink fetch.
          fetchPosts: (url, {page = 1}) async {
            fetched.add((url, page));
            return ThreadPostsPage(
              title: 'Hidden gems',
              currentPage: url.contains('/posts/') ? 3 : page,
              totalPages: 5,
              threadUrl: 'https://example.com/threads/hidden-gems.42/',
              posts: [
                for (int i = 1; i <= 12; i++)
                  ForumPost(
                    postId: 500 + i,
                    number: i,
                    author: 'Author$i',
                    blocks: [
                      ForumPostBlock(
                        kind: PostBlockKind.rich,
                        pieces: [
                          for (int line = 0; line < 4; line++) ...[
                            RichPiece.text('Post $i body line $line'),
                            RichPiece.newline(),
                          ],
                        ],
                      ),
                    ],
                  ),
              ],
            );
          },
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The counter reflects the page the server actually served.
    expect(find.text('page 3 of 5'), findsOneWidget);

    // The list scrolled the targeted post into view.
    expect(find.text('Author8').hitTestable(), findsOneWidget);
    expect(find.text('Author1').hitTestable(), findsNothing);

    // Pagination builds on the canonical thread URL, not the permalink.
    await tester.scrollUntilVisible(find.text('4'), 200);
    await tester.ensureVisible(find.text('4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    expect(fetched.last, ('https://example.com/threads/hidden-gems.42/', 4));
    expect(find.text('page 4 of 5'), findsOneWidget);
  });

  testWidgets('the OP watch toggle posts the watch action and toggles state', (tester) async {
    final sent = <(String, String, Map<String, String>)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/188349/',
          title: 'Hidden gems',
          fetchPosts: (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
          watchSender: (url, csrf, fields) async => sent.add((url, csrf, fields)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Only the OP carries the toggle, at the top of the thread.
    expect(find.byTooltip('Watch thread'), findsOneWidget);

    await tester.tap(find.byTooltip('Watch thread'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    expect(sent.single.$1, 'https://example.com/threads/188349/watch');
    expect(sent.single.$2, 'mock-csrf');
    expect(sent.single.$3, isEmpty);

    // Unwatching sends stop=1.
    await tester.tap(find.byTooltip('Unwatch thread'));
    await tester.pumpAndSettle();
    expect(sent.last.$3, {'stop': '1'});
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('long-pressing the bell offers the email watch mode', (tester) async {
    final sent = <(String, String, Map<String, String>)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/188349/',
          title: 'Hidden gems',
          fetchPosts: (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
          watchSender: (url, csrf, fields) async => sent.add((url, csrf, fields)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byTooltip('Watch thread'));
    await tester.pumpAndSettle();

    // Not watching, so Off is the highlighted mode.
    expect(find.text('Watch thread'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Not watching')).style?.fontWeight, FontWeight.w600);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Alerts + email'));
    await tester.pumpAndSettle();

    expect(sent.single.$1, 'https://example.com/threads/188349/watch');
    expect(sent.single.$3, {'email_subscribe': '1'});
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
  });

  testWidgets('a watched thread preselects no mode; picking one posts it', (tester) async {
    final sent = <Map<String, String>>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/188349/',
          title: 'Hidden gems',
          fetchPosts: (url, {page = 1}) async => const ThreadPostsPage(
            title: 'Hidden gems',
            csrfToken: 'mock-csrf',
            watchUrl: 'https://example.com/threads/188349/watch',
            watched: true,
            posts: [ForumPost(postId: 9001, number: 1, author: 'DarkVault')],
          ),
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
          watchSender: (url, csrf, fields) async => sent.add(fields),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byTooltip('Unwatch thread'));
    await tester.pumpAndSettle();

    // The site's markup never says whether an existing watch emails, so
    // nothing is highlighted and the header says as much.
    expect(find.text('Watching this thread'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    // Picking a watch mode re-posts it (updates the subscription).
    await tester.tap(find.text('Alerts + email'));
    await tester.pumpAndSettle();
    expect(sent, [
      {'email_subscribe': '1'},
    ]);
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);

    await tester.longPress(find.byTooltip('Unwatch thread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not watching'));
    await tester.pumpAndSettle();

    expect(sent.last, {'stop': '1'});
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('a failed watch toggle reverts the optimistic state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/188349/',
          title: 'Hidden gems',
          fetchPosts: (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
          watchSender: (url, csrf, fields) async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Watch thread'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.byTooltip('Watch thread'), findsOneWidget);
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

  testWidgets('forum search prompts guests to sign in', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());

    await pumpForum(tester);
    await tester.tap(find.byTooltip('Search the forum'));
    await tester.pumpAndSettle();

    expect(find.text('Searching requires an account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('forum search runs a query and opens results in the viewer', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());
    await AuthService.instance.saveCookies({'xf_user': 'tok'});

    final queries = <(String, bool, String)>[];
    final openedThreads = <String>[];
    await pumpForum(
      tester,
      searcher: (keywords, {titleOnly = false, user = '', order = 'relevance'}) async {
        queries.add((keywords, titleOnly, order));
        return ForumService.createMockSearchPage();
      },
      fetchThreadPosts: (url, {page = 1}) async {
        openedThreads.add(url);
        return ForumService.createMockThreadPosts(page: page);
      },
    );

    await tester.tap(find.byTooltip('Search the forum'));
    await tester.pumpAndSettle();

    // The sort radios share the app's segmented-track design: one sliding
    // highlight pill (the Titles-only toggle stays a lone pill).
    expect(find.byKey(const Key('segment-highlight')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('forum-search-field')), 'futanari');
    await tester.tap(find.text('Titles only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(queries, [('futanari', true, 'date')]);
    expect(find.textContaining('Corruption of Champions II'), findsOneWidget);
    expect(find.textContaining('might make the player feel powerful'), findsOneWidget);

    // Opening a result keeps the /post-N permalink so the viewer lands on
    // the matched post's page and scrolls to it.
    await tester.tap(find.textContaining('Corruption of Champions II'));
    await tester.pumpAndSettle();
    expect(openedThreads, ['https://example.com/threads/coc2.11371/post-20920001']);
  });

  testWidgets('Edit fetches the post source, saves, and reloads', (tester) async {
    const editUrl = 'https://example.com/posts/9001/edit';
    final saved = <(String, String, String)>[];
    int fetches = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/188349/',
          title: 'Hidden gems',
          fetchPosts: (url, {page = 1}) async {
            fetches++;
            return const ThreadPostsPage(
              title: 'Hidden gems',
              csrfToken: 'mock-csrf',
              replyUrl: 'https://example.com/threads/188349/add-reply',
              posts: [ForumPost(postId: 9001, number: 1, author: 'Broodyr', editUrl: editUrl)],
            );
          },
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
          editFetcher: (url) async => 'Old [b]body[/b]',
          editSaver: (url, csrf, message) async => saved.add((url, csrf, message)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const Key('composer-message')));
    expect(field.controller!.text, 'Old [b]body[/b]');

    await tester.enterText(find.byKey(const Key('composer-message')), 'New body');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, [(editUrl, 'mock-csrf', 'New body')]);
    expect(fetches, 2); // initial load + post-save reload
  });

  testWidgets('tapping the pagination ellipsis jumps to an exact page', (tester) async {
    await pumpForum(tester);
    await openThreadViewer(tester);

    await tester.scrollUntilVisible(find.text('…'), 150);
    await tester.ensureVisible(find.text('…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('…'));
    await tester.pumpAndSettle();

    expect(find.text('Go to page'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('page-jump-field')), '7');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('page 7 of 42'), findsOneWidget);
    // Mock posts number themselves per page: page 7 starts at #13.
    expect(find.text('#13'), findsOneWidget);

    // Out-of-range input clamps to the last page.
    await tester.scrollUntilVisible(find.text('…').first, 150);
    await tester.ensureVisible(find.text('…').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('…').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('page-jump-field')), '999');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('page 42 of 42'), findsOneWidget);
  });

  testWidgets('forum header opens bookmarks; the bell badges unread alerts and opens the feed', (tester) async {
    await signIn();
    await pumpForum(tester);

    // Two mock alerts are unread.
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();
    expect(find.byType(BookmarksScreen), findsOneWidget);
    expect(find.textContaining('Mousetrap'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Alerts'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertsScreen), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('the bell badge appears on sign-in without a restart', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());

    await pumpForum(tester);
    expect(find.text('2'), findsNothing);

    // Signing in notifies the screen; no rebuild or restart involved.
    await AuthService.instance.saveCookies({'xf_user': 'tok'});
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    // Signing out clears it again.
    await AuthService.instance.logout();
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);
  });

  testWidgets('the bell badge repolls while the app stays open', (tester) async {
    await signIn();
    int calls = 0;
    await pumpForum(
      tester,
      fetchAlerts: ({page = 1}) async {
        calls++;
        return AlertsPage(badgeCount: calls == 1 ? 1 : 3);
      },
    );

    expect(find.text('1'), findsOneWidget);

    // The 5-minute poll picks up alerts that arrived server-side.
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    // Dispose the screen so the poll timer cancels before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bell badge caps its display at 99+', (tester) async {
    await signIn();
    await pumpForum(tester, fetchAlerts: ({page = 1}) async => const AlertsPage(badgeCount: 137));

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('137'), findsNothing);
  });

  testWidgets('pull-to-refresh reloads the bookmarks list', (tester) async {
    await signIn();
    int fetches = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BookmarksScreen(
          fetchBookmarks: ({page = 1}) async {
            fetches++;
            return ForumService.createMockBookmarks(page: page);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetches, 1);

    await tester.fling(find.textContaining('Mousetrap'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(fetches, 2);
    expect(find.textContaining('Mousetrap'), findsOneWidget);
  });

  // The overflow used to stand as its own column beside the content, where
  // Material's tap box reserved 48px of card width down every row. It rides
  // the badge row now, so the title and snippet get the full card.
  testWidgets('the bookmark overflow rides the badge row without reserving a column', (tester) async {
    await signIn();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BookmarksScreen(fetchBookmarks: ({page = 1}) async => ForumService.createMockBookmarks(page: page)),
      ),
    );
    await tester.pumpAndSettle();

    final overflow = find.byType(PopupMenuButton<String>).first;
    final badgeRow = find.ancestor(of: find.text('POST').first, matching: find.byType(Row)).first;
    expect(
      find.descendant(of: badgeRow, matching: find.byType(PopupMenuButton<String>)),
      findsOneWidget,
      reason: 'the overflow should sit in the same row as the POST/THREAD badge',
    );
    // Under 40 means it is not an M3 IconButton, which cannot go smaller and
    // is what made it too big to live in that row.
    expect(tester.getSize(overflow).width, lessThan(40));
  });

  testWidgets('bookmarks list renders, filters by kind, and opens the viewer', (tester) async {
    await signIn();
    final openedThreads = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BookmarksScreen(
          fetchBookmarks: ({page = 1}) async => ForumService.createMockBookmarks(page: page),
          fetchThreadPosts: (url, {page = 1}) async {
            openedThreads.add(url);
            return ForumService.createMockThreadPosts(page: page);
          },
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Mousetrap'), findsOneWidget);
    expect(find.textContaining('Secret Flasher Manaka'), findsOneWidget);
    expect(find.text('THREAD'), findsOneWidget);
    expect(find.text('POST'), findsOneWidget);

    // The kind filter uses the app's segmented-track radio design.
    expect(find.byKey(const Key('segment-highlight')), findsOneWidget);

    // Kind filter narrows the list client-side.
    await tester.tap(find.text('Posts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mousetrap'), findsNothing);
    expect(find.textContaining('Secret Flasher Manaka'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Mousetrap'));
    await tester.pumpAndSettle();
    expect(find.byType(ForumThreadScreen), findsOneWidget);
    expect(openedThreads, ['https://example.com/threads/mousetrap.254486/']);
  });

  testWidgets('removing a bookmark posts delete=1 and drops the row', (tester) async {
    await signIn();
    final deleted = <(String, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BookmarksScreen(
          fetchBookmarks: ({page = 1}) async => ForumService.createMockBookmarks(page: page),
          bookmarkDeleter: (url, csrf) async => deleted.add((url, csrf)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bookmark tools').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove bookmark'));
    await tester.pumpAndSettle();

    expect(deleted, [('https://example.com/posts/16935508/bookmark', 'mock-csrf')]);
    expect(find.textContaining('Mousetrap'), findsNothing);
    expect(find.textContaining('Secret Flasher Manaka'), findsOneWidget);
  });

  testWidgets('a failed bookmark delete restores the row with an error toast', (tester) async {
    await signIn();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BookmarksScreen(
          fetchBookmarks: ({page = 1}) async => ForumService.createMockBookmarks(page: page),
          bookmarkDeleter: (url, csrf) async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bookmark tools').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove bookmark'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mousetrap'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('alerts feed renders date groups, acknowledges the bell, and opens targets', (tester) async {
    await signIn();
    final openedThreads = <String>[];
    final acknowledged = <List<int>>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AlertsScreen(
          fetchAlerts: ({page = 1}) async => ForumService.createMockAlerts(page: page),
          alertsAcknowledger: (ids) async => acknowledged.add(ids),
          fetchThreadPosts: (url, {page = 1}) async {
            openedThreads.add(url);
            return ForumService.createMockThreadPosts(page: page);
          },
          fetchReactions: (url) async => ForumService.createMockReactionsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.textContaining('TMakuboss'), findsOneWidget);
    expect(find.text('Unity'), findsOneWidget);
    expect(find.textContaining('Mage Kanade'), findsOneWidget);

    // Opening the feed acknowledged it server-side with the displayed
    // unread rows, while this visit keeps its unread tints (the fetched
    // state still says unread).
    expect(acknowledged, [
      [91, 92],
    ]);
    expect(find.byTooltip('Mark all read'), findsNothing);

    await tester.tap(find.textContaining('TMakuboss'));
    await tester.pumpAndSettle();
    expect(find.byType(ForumThreadScreen), findsOneWidget);
    expect(openedThreads, ['https://example.com/posts/20969203/']);
  });

  testWidgets('a failed alerts acknowledgment surfaces as an error toast', (tester) async {
    await signIn();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AlertsScreen(
          fetchAlerts: ({page = 1}) async => ForumService.createMockAlerts(page: page),
          alertsAcknowledger: (ids) async => throw Exception('Action failed (HTTP 403)'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The feed still renders; the stuck read state is called out instead
    // of failing silently.
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining("Couldn't mark alerts read"), findsOneWidget);
    expect(find.textContaining('HTTP 403'), findsOneWidget);
  });

  testWidgets('bookmarks and alerts prompt guests to sign in', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());

    await tester.pumpWidget(const MaterialApp(home: BookmarksScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarks require an account'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: AlertsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Alerts require an account'), findsOneWidget);
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

  testWidgets('a thread list titles itself with the icon of the row that opened it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadsScreen(
          node: ForumNode(id: 5, title: 'Rejected Game Requests', url: 'https://example.com/forums/x.5/'),
          // The page's own title differs from the node's, as it can live.
          fetchPage: (url, {page = 1}) async => ForumService.createMockForumPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The mock page calls itself General Discussions, so the two titles
    // disagree and only the node's gives cancel_outlined.
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.byIcon(Icons.forum_outlined)), findsNothing);
    final icon = find.descendant(of: bar, matching: find.byIcon(Icons.cancel_outlined));
    expect(icon, findsOneWidget, reason: 'the node title decides, not the fetched page title');
    expect(
      tester.widget<Icon>(icon).color,
      ThemeData.dark().colorScheme.primary,
      reason: 'primary reads as decorative, not as a close button',
    );
  });
}
