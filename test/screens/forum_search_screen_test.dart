import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/screens/forum_search_screen.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/screens/profile_screen.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cookie_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService previous;

  setUp(() {
    previous = AuthService.instance;
    AuthService.instance = AuthService(InMemoryCookieStorage());
  });

  tearDown(() => AuthService.instance = previous);

  // Searching is gated behind an account, so every case signs in first.
  Future<void> pumpSearch(WidgetTester tester, {required ForumSearchResult result}) async {
    await AuthService.instance.saveCookies({'xf_user': '1957582,tok'});
    await tester.pumpWidget(
      MaterialApp(
        home: ForumSearchScreen(
          searcher: (keywords, {titleOnly = false, user = '', order = 'relevance', threadId}) async =>
              ForumSearchPage(results: [result], searchUrl: 'https://example.com/search/1/'),
          fetchThreadPosts: (url, {page = 1}) async => const ThreadPostsPage(title: 'T', posts: []),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('forum-search-field')), 'anything');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
  }

  // The thread-scoped variant (the overflow's "Search thread"): no options
  // row — the scope replaces them — and results come newest first.
  group('thread scope', () {
    testWidgets('hides the options row and searches the thread newest-first', (tester) async {
      await AuthService.instance.saveCookies({'xf_user': '1957582,tok'});
      final calls = <(String, String, int?)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ForumSearchScreen(
            scopeThreadId: 207754,
            searcher: (keywords, {titleOnly = false, user = '', order = 'relevance', threadId}) async {
              calls.add((keywords, order, threadId));
              return const ForumSearchPage(results: [ForumSearchResult(title: 'Hit', url: 'u')]);
            },
          ),
        ),
      );

      expect(find.text('Titles only'), findsNothing);
      expect(find.text('Relevance'), findsNothing);
      expect(find.text('Newest'), findsNothing);

      await tester.enterText(find.byKey(const Key('forum-search-field')), 'walkthrough');
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(calls, [('walkthrough', 'date', 207754)]);
      expect(find.textContaining('Hit'), findsOneWidget);
    });

    testWidgets('an unscoped search sends no thread constraint', (tester) async {
      int? sentThreadId = -1;
      await AuthService.instance.saveCookies({'xf_user': '1957582,tok'});
      await tester.pumpWidget(
        MaterialApp(
          home: ForumSearchScreen(
            searcher: (keywords, {titleOnly = false, user = '', order = 'relevance', threadId}) async {
              sentThreadId = threadId;
              return const ForumSearchPage(results: []);
            },
          ),
        ),
      );

      expect(find.text('Titles only'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('forum-search-field')), 'anything');
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(sentThreadId, isNull);
    });
  });

  group('opening a result', () {
    testWidgets('a thread hit opens the thread viewer', (tester) async {
      await pumpSearch(
        tester,
        result: const ForumSearchResult(title: 'A game thread', url: 'https://example.com/threads/game.1/post-77'),
      );

      await tester.tap(find.textContaining('A game thread'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ProfileScreen), findsNothing);
      final screen = tester.widget<ForumThreadScreen>(find.byType(ForumThreadScreen));
      expect(screen.url, 'https://example.com/threads/game.1/post-77');
    });

    testWidgets('a profile-post hit opens the member wall instead', (tester) async {
      await pumpSearch(
        tester,
        result: const ForumSearchResult(title: 'A wall note', url: 'https://example.com/profile-posts/143769/'),
      );

      await tester.tap(find.textContaining('A wall note'));
      // The pushed profile's real fetch stays pending; pump the transition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ForumThreadScreen), findsNothing);
      final pushed = tester.widget<ProfileScreen>(find.byType(ProfileScreen));
      expect(pushed.url, 'https://example.com/profile-posts/143769/');
    });
  });
}
