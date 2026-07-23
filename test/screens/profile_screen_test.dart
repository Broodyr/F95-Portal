import 'package:f95_portal/constants.dart';
import 'package:f95_portal/models/profile.dart';
import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/screens/profile_screen.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/draft_service.dart';
import 'package:f95_portal/services/site_error.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:f95_portal/services/profile_service.dart';
import 'package:f95_portal/widgets/image_gallery.dart';
import 'package:f95_portal/widgets/pagination_bar.dart';
import 'package:f95_portal/widgets/reaction_icon.dart';
import 'package:flutter/gestures.dart';
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
    FetchProfilePostingsPage? postingsPager,
    FetchProfileWallPage? wallPager,
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
          fetchPostings: fetchPostings ?? (_) async => ProfileService.createMockPostingsPage(),
          postingsPager: postingsPager,
          wallPager: wallPager,
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

    testWidgets('tapping the avatar opens it full size', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async => const ProfilePage(
          username: 'Broodyr',
          avatarUrl: 'https://f95zone.to/data/avatars/l/1/1957582.jpg',
          avatarFullUrl: 'https://f95zone.to/data/avatars/o/1/1957582.jpg',
        ),
      );

      await tester.tap(find.byType(ForumAvatar));
      // The gallery's loading spinner animates indefinitely (the image never
      // resolves in tests), so pump the route transition instead of settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The original upload, not the downscaled variant the header shows.
      final gallery = tester.widget<ImageGallery>(find.byType(ImageGallery));
      expect(gallery.urls, ['https://f95zone.to/data/avatars/o/1/1957582.jpg']);

      // cached_network_image leaves pending timers.
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a member with no avatar has nothing to open', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => const ProfilePage(username: 'Broodyr'));

      // The miss is the point: the letter tile stands in for an avatar, so
      // it carries no tap target and there is no image behind it.
      await tester.tap(find.byType(ForumAvatar), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ImageGallery), findsNothing);

      await tester.pump(const Duration(minutes: 1));
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

  group('wall pagination', () {
    ProfilePage wall({required int page, required int total, required String body}) => ProfilePage(
      username: 'Broodyr',
      profileUrl: 'https://example.com/members/broodyr.1957582/',
      wallPage: page,
      wallTotalPages: total,
      wallPosts: [ProfilePost(id: page, author: 'Visitor', body: body)],
    );

    testWidgets('shows the page bar only when the wall runs past one page', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => wall(page: 1, total: 1, body: 'The only page'));

      expect(find.byType(PaginationBar), findsNothing);
    });

    testWidgets('jumps to a page through its pill, swapping the feed', (tester) async {
      await signIn();
      final requested = <(String, int)>[];
      await pumpProfile(
        tester,
        fetchProfile: () async => wall(page: 1, total: 3, body: 'First wall page'),
        wallPager: (url, page) async {
          requested.add((url, page));
          return wall(page: page, total: 3, body: 'Third wall page');
        },
      );

      expect(find.byType(PaginationBar), findsOneWidget);
      expect(find.text('First wall page'), findsOneWidget);

      // Tap the last-page pill: a non-adjacent jump, straight through the bar.
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();

      expect(requested.single, ('https://example.com/members/broodyr.1957582/', 3));
      expect(find.text('Third wall page'), findsOneWidget);
      expect(find.text('First wall page'), findsNothing);
    });

    testWidgets('a failed page jump keeps the current page and warns', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async => wall(page: 1, total: 2, body: 'First wall page'),
        wallPager: (url, page) async => throw Exception('network down'),
      );

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      // The current page stays; the failure surfaces as a toast, not a swap.
      expect(find.text('First wall page'), findsOneWidget);
      expect(find.byType(PaginationBar), findsOneWidget);
    });
  });

  group('jump to a permalinked post or comment', () {
    // A wall with two posts; the second may carry comments. The permalink's
    // id decides the target, so it lands whichever the url names.
    ProfilePage wall({List<ProfileComment> comments = const []}) => ProfilePage(
      username: 'Owner',
      profileUrl: 'https://example.com/members/owner.1/',
      wallPosts: [
        const ProfilePost(id: 500, author: 'Someone', body: 'An ordinary post'),
        ProfilePost(id: 146954, author: 'Writer', body: 'The targeted post', comments: comments),
      ],
    );

    Future<void> pumpJump(WidgetTester tester, {required String url, ProfilePage? page}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            url: url,
            fetchProfile: () async => page ?? wall(),
            fetchPostings: (_) async => const ProfilePostingsPage(),
            fetchAbout: (_) async => const ProfileAbout(),
          ),
        ),
      );
      // Drains the load, the scroll animation, and the settle window.
      await tester.pumpAndSettle();
    }

    // The nearest ancestor Container that carries a border: the post card for
    // a post target, a comment's own rail segment for a comment target.
    BoxDecoration borderedAncestor(WidgetTester tester, Finder of) {
      for (final c in tester.widgetList<Container>(find.ancestor(of: of, matching: find.byType(Container)))) {
        final d = c.decoration;
        if (d is BoxDecoration && d.border != null) return d;
      }
      fail('no bordered Container above $of');
    }

    bool hasBorderedAncestor(WidgetTester tester, Finder of) => tester
        .widgetList<Container>(find.ancestor(of: of, matching: find.byType(Container)))
        .any((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).border != null);

    testWidgets('a post permalink outlines the targeted post in primary', (tester) async {
      await signIn();
      await pumpJump(tester, url: 'https://example.com/profile-posts/146954/');

      final primary = Theme.of(tester.element(find.text('The targeted post'))).colorScheme.primary;
      final border = borderedAncestor(tester, find.text('The targeted post')).border! as Border;
      expect(border.top.color, primary.withValues(alpha: AppAlphas.outlineEdge));

      // The other post carries no outline.
      expect(hasBorderedAncestor(tester, find.text('An ordinary post')), isFalse);
    });

    testWidgets("a comment permalink lights only that comment's rail segment", (tester) async {
      await signIn();
      await pumpJump(
        tester,
        url: 'https://example.com/profile-posts/comments/222/',
        page: wall(
          comments: const [
            ProfileComment(id: 111, author: 'A', body: 'first reply'),
            ProfileComment(id: 222, author: 'B', body: 'the targeted reply'),
          ],
        ),
      );

      final ctx = tester.element(find.text('the targeted reply'));
      final primary = Theme.of(ctx).colorScheme.primary;
      final neutral = Theme.of(ctx).colorScheme.onSurface.withValues(alpha: AppAlphas.subtleEdge);

      // The jumped-to reply's rail turns primary and its row takes a faint wash.
      final target = borderedAncestor(tester, find.text('the targeted reply'));
      expect((target.border! as Border).left.color, primary);
      expect(target.color, primary.withValues(alpha: AppAlphas.highlightWash));

      // Its neighbour's segment stays the neutral rail colour.
      final sibling = borderedAncestor(tester, find.text('first reply'));
      expect((sibling.border! as Border).left.color, neutral);

      // The post around the comment stays plain — the rail carries the accent,
      // so the post body has no outlined card above it.
      expect(hasBorderedAncestor(tester, find.text('The targeted post')), isFalse);
    });
  });

  group('classifying a content URL', () {
    test('profile-post and comment permalinks are wall content', () {
      expect(isProfilePostUrl('https://f95zone.to/profile-posts/143769/'), isTrue);
      expect(isProfilePostUrl('https://f95zone.to/profile-posts/comments/169480/'), isTrue);
    });

    test('threads and member pages are not', () {
      expect(isProfilePostUrl('https://f95zone.to/threads/some-game.1/post-77'), isFalse);
      expect(isProfilePostUrl('https://f95zone.to/members/baasb.801262/'), isFalse);
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

    /// An entry in an open overflow. Scoped to the sheet because a wall post's
    /// footer carries buttons with these same labels.
    Finder menuItem(String label) => find.descendant(of: find.byType(BottomSheet), matching: find.text(label));

    testWidgets('shows Edit and Delete only on posts carrying their action URLs', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => ownPostPage());

      // One own post, so exactly one Edit and one Delete among two posts.
      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Comment'), findsNWidgets(2));
    });

    testWidgets('a footer row sits equally clear of the comments above and the card edge below', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => ownPostPage());

      // A comment sits inside three Containers: its own rail segment, the
      // comments block, then the post card. Innermost first, so the block —
      // whose filled bottom the footer clears — is the middle one.
      final wrappers = find.ancestor(of: find.text('A visitor comment'), matching: find.byType(Container));
      expect(wrappers, findsNWidgets(3));
      final commentsBlock = tester.getRect(wrappers.at(1));
      // The card's rect runs to the far side of the 8pt margin separating it
      // from the next card, so its drawn edge is that much higher.
      final cardEdge = tester.getRect(wrappers.last).bottom - 8;
      // The buttons' 48pt tap targets dwarf their labels, so the labels are
      // what the eye reads as the row's extent.
      final label = tester.getRect(
        find.descendant(of: find.widgetWithText(TextButton, 'Edit'), matching: find.text('Edit')),
      );

      expect(label.top - commentsBlock.bottom, moreOrLessEquals(cardEdge - label.bottom));
    });

    testWidgets('a post with no footer row keeps its bottom padding', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async => const ProfilePage(
          username: 'Broodyr',
          profileUrl: 'https://example.com/members/broodyr.1957582/',
          wallPosts: [ProfilePost(id: 1, author: 'Visitor', body: 'Nothing to act on')],
        ),
      );

      final body = tester.getRect(find.text('Nothing to act on'));
      final card = find.ancestor(of: find.text('Nothing to act on'), matching: find.byType(Container));
      expect(tester.getRect(card.last).bottom - 8 - body.bottom, moreOrLessEquals(8));
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
      final searchedUrls = <String>[];
      await pumpProfile(
        tester,
        fetchPostings: (url) async {
          searchedUrls.add(url);
          return ProfileService.createMockPostingsPage();
        },
      );
      expect(searchedUrls, isEmpty);

      await tester.tap(find.text('Postings'));
      await tester.pumpAndSettle();

      // The tab loads the member's "See more" query, not the profile URL.
      expect(searchedUrls, ['https://example.com/search/member?user_id=1957582']);
      expect(find.textContaining('Myth of Slayer Walkthrough [Ch 11]'), findsOneWidget);
      expect(find.text('Post #29 · 21 minutes ago · Mods'), findsOneWidget);
      expect(find.text('Thread · Jun 2, 2026 · Replies: 1 · Mods'), findsOneWidget);
      expect(find.text('Mod'), findsWidgets);
    });

    testWidgets('shows the empty state when the query has no postings', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchPostings: (_) async => const ProfilePostingsPage());

      await tester.tap(find.text('Postings'));
      await tester.pumpAndSettle();

      expect(find.text('No postings yet.'), findsOneWidget);
    });

    testWidgets('pages in more postings as the list nears the end', (tester) async {
      await signIn();
      final pagesFetched = <int>[];
      await pumpProfile(
        tester,
        fetchProfile: () async => const ProfilePage(
          username: 'Broodyr',
          profileUrl: 'https://example.com/members/x.1/',
          postingsSearchUrl: 'https://example.com/search/member?user_id=1',
        ),
        fetchPostings: (_) async => const ProfilePostingsPage(
          postings: [ProfilePosting(title: 'First page hit', url: 'https://example.com/threads/a.1/post-1')],
          totalPages: 2,
          searchUrl: 'https://example.com/search/99/?c[users]=Broodyr',
        ),
        postingsPager: (url, page) async {
          pagesFetched.add(page);
          return const ProfilePostingsPage(
            postings: [ProfilePosting(title: 'Second page hit', url: 'https://example.com/threads/b.2/post-2')],
            currentPage: 2,
            totalPages: 2,
            searchUrl: 'https://example.com/search/99/?c[users]=Broodyr',
          );
        },
      );

      await tester.tap(find.text('Postings'));
      // A load-more spinner rides the list while a next page exists, so it
      // never settles — pump by hand rather than pumpAndSettle.
      await tester.pump();
      await tester.pump();
      expect(find.text('First page hit'), findsOneWidget);

      // Crossing the 600px lead near the end pulls the next page in.
      await tester.drag(find.text('First page hit'), const Offset(0, -1200));
      await tester.pump();
      await tester.pump();

      expect(pagesFetched, [2]);
      expect(find.text('Second page hit'), findsOneWidget);
    });

    testWidgets('tapping a posting opens the thread viewer on that post', (tester) async {
      await signIn();
      await pumpProfile(tester);

      await tester.tap(find.text('Postings'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Myth of Slayer Walkthrough [Ch 11]'));
      await tester.pumpAndSettle();

      expect(find.byType(ForumThreadScreen), findsOneWidget);
      final screen = tester.widget<ForumThreadScreen>(find.byType(ForumThreadScreen));
      // The /post-N suffix rides along so the viewer scrolls to the reply,
      // the same as bookmarks and alerts.
      expect(screen.url, 'https://example.com/threads/myth-of-slayer.276090/post-20908354');
    });

    testWidgets('a profile-post posting opens the member wall, not the thread viewer', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchPostings: (_) async => const ProfilePostingsPage(
          postings: [ProfilePosting(title: 'Left a note', url: 'https://example.com/profile-posts/143769/')],
          searchUrl: 'https://example.com/search/1/',
        ),
      );

      await tester.tap(find.text('Postings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Left a note'));
      // The pushed profile's real fetch stays pending under fake async; pump
      // the route transition rather than settling on it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ForumThreadScreen), findsNothing);
      final pushed = tester.widgetList<ProfileScreen>(find.byType(ProfileScreen)).firstWhere((s) => s.url != null);
      expect(pushed.url, 'https://example.com/profile-posts/143769/');
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
            fetchPostings: (_) async => ProfileService.createMockPostingsPage(),
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

  group('wall posts render like forum posts', () {
    ProfilePage pageWith({required List<RichPiece> rich, String body = 'fallback'}) => ProfilePage(
      username: 'Someone',
      profileUrl: 'https://f95zone.to/members/someone.1/',
      wallPosts: [ProfilePost(id: 1, author: 'Poster', body: body, rich: rich)],
    );

    testWidgets('a body is selectable, so it can be long-pressed and copied', (tester) async {
      await signIn();
      await pumpProfile(
        tester,
        fetchProfile: () async => pageWith(rich: const [RichPiece.text('Something worth copying.')]),
      );

      expect(find.text('Something worth copying.'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Something worth copying.'), matching: find.byType(SelectionArea)),
        findsOneWidget,
      );
    });

    testWidgets('a link in a body opens rather than reading as plain text', (tester) async {
      await signIn();
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            fetchProfile: () async => pageWith(
              rich: const [
                RichPiece.text('See '),
                RichPiece.text('the rules', url: 'https://f95zone.to/threads/general-rules.5589/'),
              ],
            ),
            fetchPostings: (_) async => const ProfilePostingsPage(),
            fetchAbout: (_) async => const ProfileAbout(),
            urlLauncher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      TapGestureRecognizer? tap;
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        text.textSpan?.visitChildren((child) {
          if (child is TextSpan && child.text == 'the rules') tap = child.recognizer as TapGestureRecognizer?;
          return true;
        });
      }
      expect(tap, isNotNull, reason: 'the link piece carries a tap recognizer');
      tap!.onTap!();

      expect(opened.single.toString(), 'https://f95zone.to/threads/general-rules.5589/');
    });

    testWidgets('a hand-built post with no pieces still shows its text', (tester) async {
      await signIn();
      await pumpProfile(tester, fetchProfile: () async => pageWith(rich: const [], body: 'Plain and unparsed.'));

      expect(find.text('Plain and unparsed.'), findsOneWidget);
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
