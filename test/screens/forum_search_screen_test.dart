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
          searcher: (keywords, {titleOnly = false, user = '', order = 'relevance'}) async =>
              ForumSearchPage(results: [result], searchUrl: 'https://example.com/search/1/'),
          fetchThreadPosts: (url, {page = 1}) async => const ThreadPostsPage(title: 'T', posts: []),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('forum-search-field')), 'anything');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
  }

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
