import 'package:f95_portal/models/profile.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/screens/profile_screen.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/draft_service.dart';
import 'package:f95_portal/services/site_error.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:f95_portal/services/profile_service.dart';
import 'package:f95_portal/widgets/reaction_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cookie_storage.dart';
import '../helpers/in_memory_draft_storage.dart';
import '../helpers/widget_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService previous;
  late DraftService previousDrafts;

  setUp(() {
    previous = AuthService.instance;
    AuthService.instance = AuthService(InMemoryCookieStorage());
    // Composer drafts are persisted; keep them off the real backing store.
    previousDrafts = DraftService.instance;
    installTestDrafts();
  });

  tearDown(() {
    AuthService.instance = previous;
    DraftService.instance = previousDrafts;
  });

  Future<void> signIn() => AuthService.instance.saveCookies({'xf_user': '1957582,tok'});

  Future<void> pumpProfile(
    WidgetTester tester, {
    FetchProfile? fetchProfile,
    FetchProfilePostings? fetchPostings,
    FetchProfileAbout? fetchAbout,
    ProfileMessagePoster? messagePoster,
    EditFetcher? editFetcher,
    EditSaver? editSaver,
    ProfilePostDeleter? postDeleter,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: fetchProfile ?? () async => ProfileService.createMockProfilePage(),
          fetchPostings: fetchPostings ?? (_) async => ProfileService.createMockPostings(),
          fetchAbout: fetchAbout ?? (_) async => ProfileService.createMockProfileAbout(),
          messagePoster: messagePoster,
          editFetcher: editFetcher,
          editSaver: editSaver,
          postDeleter: postDeleter,
          fetchThreadPosts: (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('sign-in gate', () {
    testWidgets('shows the call to action when logged out', (tester) async {
      await pumpProfile(tester);

      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Sign in to F95Zone'), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsNothing);
    });

    testWidgets('the sign-in button uses the enlarged 18pt CTA label', (tester) async {
      await pumpProfile(tester);

      expect(effectiveFontSize(tester, find.text('Sign in to F95Zone')), moreOrLessEquals(18));
    });

    testWidgets('signing in mid-session loads the profile', (tester) async {
      await pumpProfile(tester);

      await signIn();
      await tester.pumpAndSettle();

      // Thrice: the identity header, the mock's own wall post author, and
      // their own comment on it.
      expect(find.text('Broodyr'), findsNWidgets(3));
      expect(find.text('Not signed in'), findsNothing);
    });

    testWidgets('signing out returns to the gate', (tester) async {
      await signIn();
      await pumpProfile(tester);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Not signed in'), findsOneWidget);
      expect(AuthService.instance.isLoggedIn, isFalse);
    });
  });

  group('header', () {
    testWidgets('shows identity, stats, and member title', (tester) async {
      await signIn();
      await pumpProfile(tester);

      // Thrice: the identity header, the mock's own wall post author, and
      // their own comment on it.
      expect(find.text('Broodyr'), findsNWidgets(3));
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('291 messages · Joined Dec 11, 2017'), findsOneWidget);
      expect(find.text('Last seen Today at 4:55 PM'), findsOneWidget);

      // The tab bar uses the app's segmented-track radio design.
      expect(find.byKey(const Key('segment-highlight')), findsOneWidget);
    });

    testWidgets('shows a retry on load failure', (tester) async {
      await signIn();
      int calls = 0;
      await pumpProfile(
        tester,
        fetchProfile: () async {
          calls++;
          if (calls == 1) throw Exception('boom');
          return ProfileService.createMockProfilePage();
        },
      );

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Broodyr'), findsNWidgets(3));
    });
  });

  group('profile posts tab', () {
    testWidgets('shows wall posts with nested comments', (tester) async {
      await signIn();
      await pumpProfile(tester);

      // Twice: as the wall post's author and on their own follow-up comment.
      expect(find.text('VoidWalker'), findsNWidgets(2));
      expect(find.textContaining('gallery unlock works great'), findsOneWidget);
      expect(find.textContaining('report anything odd'), findsOneWidget);
      expect(find.text('Will do!'), findsOneWidget);
    });

    testWidgets('shows the empty state when the wall has no posts', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async =>
            const ProfilePage(username: 'Broodyr', profileUrl: 'https://example.com/members/x.1/'),
      );

      expect(find.text('No messages on your profile yet.'), findsOneWidget);
      // No composer without a wall-post action.
      expect(find.text('Write something…'), findsNothing);
    });

    testWidgets('posts a wall message through the composer', (tester) async {
      await signIn();
      final posted = <(String, String, String)>[];
      await pumpProfile(tester, messagePoster: (url, csrf, message) async => posted.add((url, csrf, message)));

      await tester.tap(find.text('Write something…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Hello wall');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();

      expect(posted.single.$1, 'https://example.com/members/broodyr.1957582/post');
      expect(posted.single.$2, 'mock-csrf');
      expect(posted.single.$3, 'Hello wall');
    });

    testWidgets('tapping a wall author opens their profile', (tester) async {
      await signIn();
      await pumpProfile(tester);

      // The post author's header row; index 0 is the wall post, 1 their comment.
      await tester.tap(find.text('VoidWalker').first);
      // No pumpAndSettle: the pushed screen's real fetch stays pending under
      // fake async and its loader would never settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final pushed = tester.widgetList<ProfileScreen>(find.byType(ProfileScreen)).firstWhere((s) => s.url != null);
      expect(pushed.url, 'https://example.com/members/voidwalker.101/');
      expect(pushed.username, 'VoidWalker');
    });

    testWidgets('tapping a comment avatar opens that member too', (tester) async {
      await signIn();
      await pumpProfile(tester);

      // VoidWalker's follow-up comment renders a 17px avatar.
      final commentAvatar = find.byWidgetPredicate(
        (w) => w is ForumAvatar && w.username == 'VoidWalker' && w.size == 17,
      );
      await tester.tap(commentAvatar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final pushed = tester.widgetList<ProfileScreen>(find.byType(ProfileScreen)).firstWhere((s) => s.url != null);
      expect(pushed.url, 'https://example.com/members/voidwalker.101/');
    });

    testWidgets('tapping the viewed profile owner in a comment goes nowhere', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async => const ProfilePage(
          username: 'OtherGuy',
          profileUrl: 'https://example.com/members/otherguy.42/',
          wallPosts: [
            ProfilePost(
              id: 1,
              author: 'Visitor',
              body: 'Nice mods!',
              comments: [
                ProfileComment(
                  id: 2,
                  author: 'OtherGuy',
                  authorUrl: 'https://example.com/members/otherguy.42/',
                  body: 'Thanks!',
                ),
              ],
            ),
          ],
        ),
      );

      await tester.tap(find.text('OtherGuy').last);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('comments on a wall post through its add-comment action', (tester) async {
      await signIn();
      final posted = <(String, String, String)>[];
      await pumpProfile(tester, messagePoster: (url, csrf, message) async => posted.add((url, csrf, message)));

      await tester.tap(find.text('Comment').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Nice one');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();

      expect(posted.single.$1, 'https://example.com/profile-posts/142106/add-comment');
      expect(posted.single.$3, 'Nice one');
    });

    testWidgets('an abandoned wall post and comment keep separate drafts', (tester) async {
      await signIn();
      await pumpProfile(tester);

      // Start a wall post, then back out of it.
      await tester.tap(find.text('Write something…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('composer-message')), 'a wall post in progress');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      // The comment box on one of that profile's posts is its own draft.
      await tester.tap(find.text('Comment').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('composer-message'))).controller!.text,
        '',
      );
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      // Reopening the wall composer brings the abandoned text back.
      await tester.tap(find.text('Write something…'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('composer-message'))).controller!.text,
        'a wall post in progress',
      );
    });
  });

  group('own post actions', () {
    // A wall with one viewer-owned post (edit/delete links present) and one
    // visitor post without them, mirroring what the parser produces.
    ProfilePage ownPostPage() => const ProfilePage(
      username: 'Broodyr',
      profileUrl: 'https://example.com/members/broodyr.1957582/',
      csrfToken: 'mock-csrf',
      wallPosts: [
        ProfilePost(
          id: 146954,
          author: 'Broodyr',
          body: 'My own wall post',
          commentUrl: 'https://example.com/profile-posts/146954/add-comment',
          editUrl: 'https://example.com/profile-posts/146954/edit',
          deleteUrl: 'https://example.com/profile-posts/146954/delete',
          comments: [
            ProfileComment(id: 173518, author: 'Visitor', body: 'A visitor comment'),
            ProfileComment(
              id: 173522,
              author: 'Broodyr',
              body: 'My own comment',
              editUrl: 'https://example.com/profile-posts/comments/173522/edit',
              deleteUrl: 'https://example.com/profile-posts/comments/173522/delete',
            ),
          ],
        ),
        ProfilePost(
          id: 1,
          author: 'Visitor',
          body: 'Someone else wrote this',
          commentUrl: 'https://example.com/profile-posts/1/add-comment',
        ),
      ],
    );

    /// The overflow belonging to the comment with [body]; both sit in the
    /// same Column, the header Row above the body text.
    Finder overflowFor(WidgetTester tester, String body) {
      return find.descendant(
        of: find.ancestor(of: find.text(body), matching: find.byType(Column)).first,
        matching: find.byTooltip('Post tools'),
      );
    }

    /// An entry in an open overflow. Scoped to the menu because a wall post's
    /// footer carries buttons with these same labels.
    Finder menuItem(String label) => find.widgetWithText(PopupMenuItem<VoidCallback>, label);

    testWidgets('shows Edit and Delete only on posts carrying their action URLs', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => ownPostPage());

      // One own post, so exactly one Edit and one Delete among two posts.
      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Comment'), findsNWidgets(2));
    });

    testWidgets('edits an own post through the composer prefilled with its BBCode', (tester) async {
      await signIn();
      final fetched = <String>[];
      final saved = <(String, String, String)>[];
      await pumpProfile(
        tester,
        fetchProfile: () async => ownPostPage(),
        editFetcher: (url) async {
          fetched.add(url);
          return 'Original body';
        },
        editSaver: (url, csrf, message) async => saved.add((url, csrf, message)),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(fetched.single, 'https://example.com/profile-posts/146954/edit');
      expect(find.text('Original body'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Updated body');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(saved.single.$1, 'https://example.com/profile-posts/146954/edit');
      expect(saved.single.$2, 'mock-csrf');
      expect(saved.single.$3, 'Updated body');
    });

    testWidgets('deletes an own post after confirming', (tester) async {
      await signIn();
      final deleted = <(String, String)>[];
      await pumpProfile(
        tester,
        fetchProfile: () async => ownPostPage(),
        postDeleter: (url, csrf) async => deleted.add((url, csrf)),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete profile post?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deleted.single.$1, 'https://example.com/profile-posts/146954/delete');
      expect(deleted.single.$2, 'mock-csrf');
    });

    testWidgets('cancelling the delete confirm leaves the post alone', (tester) async {
      await signIn();
      final deleted = <(String, String)>[];
      await pumpProfile(
        tester,
        fetchProfile: () async => ownPostPage(),
        postDeleter: (url, csrf) async => deleted.add((url, csrf)),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(deleted, isEmpty);
      expect(find.text('My own wall post'), findsOneWidget);
    });

    testWidgets('offers edit and delete only on an own comment, report on any', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => ownPostPage());

      // Located by the comment they belong to rather than by index: the
      // overflows render post, comment, comment, post, and an index would
      // silently follow the wrong one if that order ever changed.
      await tester.tap(overflowFor(tester, 'My own comment'));
      await tester.pumpAndSettle();
      expect(menuItem('Edit'), findsOneWidget);
      expect(menuItem('Delete'), findsOneWidget);
      expect(menuItem('Report…'), findsOneWidget);
      Navigator.of(tester.element(menuItem('Report…'))).pop();
      await tester.pumpAndSettle();

      // A visitor's comment can still be reported, but not rewritten.
      await tester.tap(overflowFor(tester, 'A visitor comment'));
      await tester.pumpAndSettle();
      expect(menuItem('Edit'), findsNothing);
      expect(menuItem('Delete'), findsNothing);
      expect(menuItem('Report…'), findsOneWidget);
    });

    testWidgets('edits an own comment through the composer', (tester) async {
      await signIn();
      final saved = <(String, String, String)>[];
      await pumpProfile(
        tester,
        fetchProfile: () async => ownPostPage(),
        editFetcher: (url) async => 'Original comment',
        editSaver: (url, csrf, message) async => saved.add((url, csrf, message)),
      );

      await tester.tap(overflowFor(tester, 'My own comment'));
      await tester.pumpAndSettle();
      await tester.tap(menuItem('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Original comment'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Updated comment');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(saved.single.$1, 'https://example.com/profile-posts/comments/173522/edit');
      expect(saved.single.$2, 'mock-csrf');
      expect(saved.single.$3, 'Updated comment');
    });

    testWidgets('deletes an own comment after confirming', (tester) async {
      await signIn();
      final deleted = <(String, String)>[];
      await pumpProfile(
        tester,
        fetchProfile: () async => ownPostPage(),
        postDeleter: (url, csrf) async => deleted.add((url, csrf)),
      );

      await tester.tap(overflowFor(tester, 'My own comment'));
      await tester.pumpAndSettle();
      await tester.tap(menuItem('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete comment?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deleted.single.$1, 'https://example.com/profile-posts/comments/173522/delete');
      expect(deleted.single.$2, 'mock-csrf');
    });
  });

  group('postings tab', () {
    testWidgets('lazy loads and renders postings with their footer', (tester) async {
      await signIn();
      int fetches = 0;
      await pumpProfile(
        tester,
        fetchPostings: (_) async {
          fetches++;
          return ProfileService.createMockPostings();
        },
      );
      expect(fetches, 0);

      await tester.tap(find.text('Postings'));
      await tester.pumpAndSettle();

      expect(fetches, 1);
      expect(find.textContaining('Myth of Slayer Walkthrough [Ch 11]'), findsOneWidget);
      expect(find.text('Post #29 · 21 minutes ago · Mods'), findsOneWidget);
      expect(find.text('Thread · Jun 2, 2026 · Replies: 1 · Mods'), findsOneWidget);
      expect(find.text('Mod'), findsWidgets);
    });

    testWidgets('uses an inline postings pane without refetching', (tester) async {
      await signIn();
      int fetches = 0;
      await pumpProfile(
        tester,
        fetchProfile: () async => ProfilePage(
          username: 'Broodyr',
          profileUrl: 'https://example.com/members/x.1/',
          postings: ProfileService.createMockPostings(),
        ),
        fetchPostings: (_) async {
          fetches++;
          return const [];
        },
      );

      await tester.tap(find.text('Postings'));
      await tester.pumpAndSettle();

      expect(fetches, 0);
      expect(find.textContaining('Myth of Slayer Walkthrough [Ch 11]'), findsOneWidget);
    });

    testWidgets('tapping a posting opens the internal thread viewer', (tester) async {
      await signIn();
      await pumpProfile(tester);

      await tester.tap(find.text('Postings'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Myth of Slayer Walkthrough [Ch 11]'));
      await tester.pumpAndSettle();

      expect(find.byType(ForumThreadScreen), findsOneWidget);
      final screen = tester.widget<ForumThreadScreen>(find.byType(ForumThreadScreen));
      // The /post-N suffix is stripped so the viewer loads the thread.
      expect(screen.url, 'https://example.com/threads/myth-of-slayer.276090/');
    });
  });

  group('other member profiles (url mode)', () {
    Future<void> pumpOther(WidgetTester tester, {FetchProfile? fetchProfile}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            url: 'https://example.com/members/otherguy.42/',
            username: 'OtherGuy',
            fetchProfile: fetchProfile,
            fetchPostings: (_) async => ProfileService.createMockPostings(),
            fetchAbout: (_) async => ProfileService.createMockProfileAbout(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('loads by URL with a back button and no sign-out', (tester) async {
      await signIn();
      await pumpOther(
        tester,
        fetchProfile: () async => const ProfilePage(
          username: 'OtherGuy',
          memberTitle: 'Member',
          profileUrl: 'https://example.com/members/otherguy.42/',
        ),
      );

      // Username in the top bar and the identity header.
      expect(find.text('OtherGuy'), findsNWidgets(2));
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsNothing);
      expect(find.text('No messages on this profile yet.'), findsOneWidget);
    });

    testWidgets('logged out prompts with a sign-in link instead of the gate', (tester) async {
      await pumpOther(tester);

      // "Sign in" renders as its own tappable widget inside the sentence.
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.textContaining('to view member profiles.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Not signed in'), findsNothing);
      expect(find.text('OtherGuy'), findsOneWidget);
    });

    testWidgets('signing in mid-view loads the profile over the prompt', (tester) async {
      await pumpOther(
        tester,
        fetchProfile: () async =>
            const ProfilePage(username: 'OtherGuy', profileUrl: 'https://example.com/members/otherguy.42/'),
      );
      expect(find.text('Sign in'), findsOneWidget);

      await signIn();
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsNothing);
      expect(find.text('OtherGuy'), findsNWidgets(2));
    });
  });

  group('about tab', () {
    testWidgets('lazy loads bio and detail fields', (tester) async {
      await signIn();
      await pumpProfile(tester);

      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      expect(find.text('Birthday'), findsOneWidget);
      expect(find.text('Jan 28'), findsOneWidget);
      expect(find.text('example.itch.io'), findsOneWidget);
      expect(find.text('The Netherlands'), findsOneWidget);
      expect(find.textContaining('Modding Ren\'Py games'), findsOneWidget);
    });

    testWidgets('shows an empty state when nothing is set', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchAbout: (_) async => const ProfileAbout());

      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing here yet.'), findsOneWidget);
    });
  });

  group('a profile the member closed off', () {
    testWidgets('states the reason under the empty-state glyph, with no retry', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async =>
            throw ContentUnavailableException('This member limits who may view their full profile.'),
      );

      expect(find.text('This member limits who may view their full profile.'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // Retrying only earns the same 403.
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      // Never the raw exception the user saw before.
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.textContaining('403'), findsNothing);
    });

    testWidgets('a member who is gone reads as missing, not as private', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async =>
            throw ContentUnavailableException('The requested member could not be found.', statusCode: 404),
      );

      expect(find.text('Member not found'), findsOneWidget);
      expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
      // A padlock would say the member shut you out, which they did not.
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    });

    testWidgets('an ordinary failure still offers a retry', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => throw ApiException('Failed to load profile page: 500'));

      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byIcon(Icons.person_off_outlined), findsNothing);
      // The class name is not something to put in front of a reader.
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.text('Failed to load profile page: 500'), findsOneWidget);
    });
  });
}
