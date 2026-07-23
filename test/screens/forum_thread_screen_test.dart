import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/widgets/remote_image.dart';
import 'package:f95_portal/screens/forum_search_screen.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/screens/thread_reviews_screen.dart';
import 'package:f95_portal/widgets/star_rating.dart';
import 'package:f95_portal/widgets/image_gallery.dart';
import 'package:f95_portal/widgets/rich_spoiler_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping a post image opens a gallery spanning the whole post', (tester) async {
    // One post, images split across a quote block and a rich block.
    final postsPage = ThreadPostsPage(
      title: 'Gallery scope',
      posts: [
        ForumPost(
          postId: 1,
          number: 1,
          author: 'A',
          blocks: const [
            ForumPostBlock(
              kind: PostBlockKind.quote,
              label: 'B',
              pieces: [RichPiece.image('https://example.com/thumb/q.jpg', fullImageUrl: 'https://example.com/q.jpg')],
            ),
            ForumPostBlock(
              kind: PostBlockKind.rich,
              pieces: [
                RichPiece.text('Two shots:'),
                RichPiece.image('https://example.com/thumb/a.jpg', fullImageUrl: 'https://example.com/a.jpg'),
                RichPiece.image('https://example.com/thumb/b.jpg', fullImageUrl: 'https://example.com/b.jpg'),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/gallery-scope.1/',
          title: 'Gallery scope',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the second image of the rich block (post-wide index 2).
    await tester.tap(find.byType(RemoteImage).at(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final gallery = tester.widget<ImageGallery>(find.byType(ImageGallery));
    expect(gallery.urls, ['https://example.com/q.jpg', 'https://example.com/a.jpg', 'https://example.com/b.jpg']);
    expect(gallery.initialIndex, 2);

    // cached_network_image leaves pending timers.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a signature renders below the post, smaller and dimmed', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Signed',
      posts: const [
        ForumPost(
          postId: 1,
          number: 1,
          author: 'A',
          blocks: [
            ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('the message')]),
          ],
          signature: [RichPiece.text('my signature', italic: true), RichPiece.image('https://example.com/banner.gif')],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/signed.1/',
          title: 'Signed',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('my signature', findRichText: true), findsOneWidget);

    // The signature block renders at reduced scale, under the body's text.
    final texts = tester.widgetList<RichSpoilerText>(find.byType(RichSpoilerText)).toList();
    expect(texts, hasLength(2));
    final body = texts.first;
    final signature = texts.last;
    expect(signature.pieces.first.text, 'my signature');
    expect(signature.fontSize, lessThan(body.fontSize));
    expect(signature.maxImageHeight, lessThan(body.maxImageHeight));

    // cached_network_image leaves pending timers.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a post without a signature renders no extra text block', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Unsigned',
      posts: const [
        ForumPost(
          postId: 1,
          number: 1,
          author: 'A',
          blocks: [
            ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('the message')]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/unsigned.1/',
          title: 'Unsigned',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RichSpoilerText), findsOneWidget);
  });

  testWidgets('the OP carries the thread score, tappable into the reviews', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Scored',
      score: const ThreadScore(rating: 4.3, votes: 233, reviewsUrl: 'https://example.com/threads/scored.1/br-reviews/'),
      posts: const [
        ForumPost(
          postId: 1,
          number: 1,
          author: 'A',
          blocks: [
            ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('the game post')]),
          ],
        ),
        ForumPost(
          postId: 2,
          number: 2,
          author: 'B',
          blocks: [
            ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('a reply')]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/scored.1/',
          title: 'Scored',
          fetchPosts: (url, {page = 1}) async => postsPage,
          fetchReviews: (url, {int page = 1}) async => const ThreadReviewsPage(
            reviews: [
              ThreadReview(reviewId: 1, author: 'Reviewer', rating: 5, pieces: [RichPiece.text('a review')]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One score strip, on the OP only.
    expect(find.byType(StarBar), findsOneWidget);
    expect(tester.widget<StarBar>(find.byType(StarBar)).rating, 4.3);
    expect(find.text('4.3'), findsOneWidget);
    expect(find.textContaining('233'), findsOneWidget);

    await tester.tap(find.text('4.3'));
    await tester.pumpAndSettle();

    expect(find.byType(ThreadReviewsScreen), findsOneWidget);
    expect(find.text('Reviewer'), findsOneWidget);
  });

  testWidgets('an unrated but reviewable thread invites the first review', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Fresh',
      score: const ThreadScore(rating: 0, votes: 0, reviewsUrl: 'https://example.com/threads/fresh.1/br-reviews/'),
      posts: const [
        ForumPost(
          postId: 1,
          number: 1,
          author: 'A',
          blocks: [
            ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('brand new game')]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/fresh.1/',
          title: 'Fresh',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StarBar), findsOneWidget);
    expect(find.text('No ratings yet'), findsOneWidget);
  });

  testWidgets('a thread without a score shows no star strip', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Unscored',
      posts: const [
        ForumPost(
          postId: 1,
          number: 1,
          author: 'A',
          blocks: [
            ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('just a discussion')]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/unscored.1/',
          title: 'Unscored',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StarBar), findsNothing);
  });

  testWidgets('quoting a post prefills author, post id, and member id', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Quote me',
      replyUrl: 'https://example.com/threads/quote-me.1/add-reply',
      posts: const [
        ForumPost(
          postId: 42,
          number: 1,
          author: 'VoidTraveler',
          authorId: 3590149,
          blocks: [
            ForumPostBlock(
              kind: PostBlockKind.rich,
              pieces: [
                RichPiece.text('hello there'),
                RichPiece.smilie(':love:', asset: 'assets/smilies/love.png'),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/quote-me.1/',
          title: 'Quote me',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Quote'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    // The member id is what makes the site alert the quoted user; smilies
    // come through as their shortcode.
    expect(field.controller!.text, '[QUOTE="VoidTraveler, post: 42, member: 3590149"]\nhello there:love:\n[/QUOTE]\n');
  });

  testWidgets('the post bookmark toggle sends add then remove and flips its state', (tester) async {
    final sent = <(String, String, Map<String, String>)>[];
    final postsPage = ThreadPostsPage(
      title: 'Bookmark me',
      csrfToken: 'tok',
      replyUrl: 'https://example.com/threads/b.1/add-reply',
      posts: const [ForumPost(postId: 42, number: 1, author: 'A', bookmarkUrl: 'https://f95zone.to/posts/42/bookmark')],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/b.1/',
          title: 'Bookmark me',
          fetchPosts: (url, {page = 1}) async => postsPage,
          bookmarkSender: (url, csrf, fields) async => sent.add((url, csrf, fields)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Opens un-bookmarked.
    expect(find.byTooltip('Bookmark'), findsOneWidget);
    // The circle sizes to itself (36), not an M3 48px tap target that would
    // inflate the footer row's height.
    expect(tester.getSize(find.byTooltip('Bookmark')).height, lessThan(40));

    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();
    // A plain POST adds it; the icon flips to the filled remove state.
    expect(sent, hasLength(1));
    expect(sent.single.$1, 'https://f95zone.to/posts/42/bookmark');
    expect(sent.single.$2, 'tok');
    expect(sent.single.$3, isEmpty);
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove bookmark'));
    await tester.pumpAndSettle();
    // Removal carries delete=1, and the toggle returns to Bookmark.
    expect(sent, hasLength(2));
    expect(sent.last.$3, {'delete': '1'});
    expect(find.byTooltip('Bookmark'), findsOneWidget);
  });

  testWidgets('a post the session already bookmarked opens in the remove state', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Saved',
      replyUrl: 'https://example.com/threads/s.1/add-reply',
      posts: const [
        ForumPost(
          postId: 9,
          number: 1,
          author: 'A',
          bookmarkUrl: 'https://f95zone.to/posts/9/bookmark',
          bookmarked: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/s.1/',
          title: 'Saved',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    expect(find.byTooltip('Bookmark'), findsNothing);
  });

  testWidgets('a failed bookmark toggle reverts and surfaces the error', (tester) async {
    final postsPage = ThreadPostsPage(
      title: 'Oops',
      csrfToken: 'tok',
      replyUrl: 'https://example.com/threads/o.1/add-reply',
      posts: const [ForumPost(postId: 5, number: 1, author: 'A', bookmarkUrl: 'https://f95zone.to/posts/5/bookmark')],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/o.1/',
          title: 'Oops',
          fetchPosts: (url, {page = 1}) async => postsPage,
          bookmarkSender: (url, csrf, fields) async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();

    // Reverted to un-bookmarked, error surfaced.
    expect(find.byTooltip('Bookmark'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  // A permalink scrolls its post into view. ensureVisible would park the card
  // flush against the app bar, which reads as stuck to the chrome, so the jump
  // leaves half a post gap above it.
  testWidgets('a permalink lands its post clear of the app bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Enough posts that the target sits well below the fold and well above
    // the end of the list, so the scroll neither starts nor bottoms out on it.
    final postsPage = ThreadPostsPage(
      title: 'Deep thread',
      posts: [
        for (var i = 1; i <= 40; i++)
          ForumPost(
            postId: i,
            number: i,
            author: 'Member$i',
            blocks: [
              ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('body of post $i')]),
            ],
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/deep-thread.1/post-15',
          title: 'Deep thread',
          fetchPosts: (url, {page = 1}) async => postsPage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('body of post 15'), findsOneWidget);

    // The keyed wrapper around the targeted card is the only post padding
    // carrying a key.
    final targetCard = find.byWidgetPredicate(
      (w) => w is Padding && w.key != null && w.padding == const EdgeInsets.only(bottom: 8),
    );
    expect(targetCard, findsOneWidget);

    final gap = tester.getTopLeft(targetCard).dy - tester.getBottomLeft(find.byType(AppBar)).dy;
    expect(gap, closeTo(4, 0.01));
  });

  // Images have no height until they load, so posts above a landed scroll
  // grow and push the target down. The landing holds its place while the page
  // settles. Text scale stands in for the images here: it is content above the
  // target growing after the scroll, which is the shape of the bug.
  group('holding a landed scroll while the page settles', () {
    Future<void> pumpAtScale(WidgetTester tester, double scale) async {
      final postsPage = ThreadPostsPage(
        title: 'Deep thread',
        posts: [
          for (var i = 1; i <= 40; i++)
            ForumPost(
              postId: i,
              number: i,
              author: 'Member$i',
              blocks: [
                ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('body of post $i')]),
              ],
            ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: ForumThreadScreen(
              url: 'https://example.com/threads/deep-thread.1/post-15',
              title: 'Deep thread',
              fetchPosts: (url, {page = 1}) async => postsPage,
            ),
          ),
        ),
      );
    }

    // Enough frames for the step-scroll and its landing animation, but well
    // inside the settle window — pumpAndSettle would run the window out and
    // leave nothing to observe.
    Future<void> land(WidgetTester tester) async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    double gapAboveTarget(WidgetTester tester) {
      final targetCard = find.byWidgetPredicate(
        (w) => w is Padding && w.key != null && w.padding == const EdgeInsets.only(bottom: 8),
      );
      return tester.getTopLeft(targetCard).dy - tester.getBottomLeft(find.byType(AppBar)).dy;
    }

    testWidgets('content growing above the target keeps it in place', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpAtScale(tester, 1);
      await land(tester);
      expect(gapAboveTarget(tester), closeTo(4, 0.01));

      // Everything above the target gets taller, mid-settle.
      await pumpAtScale(tester, 2);
      await tester.pump();
      await tester.pump();

      // Still parked under the app bar rather than shoved down the screen.
      expect(gapAboveTarget(tester), closeTo(4, 0.01));
    });

    testWidgets('the reader taking hold of the scroll ends the correction', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpAtScale(tester, 1);
      await land(tester);

      final controller = tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;
      final landed = controller.offset;

      // A drag inside the settle window must stand: a correction that pulled
      // the reader back to the target would be the app fighting them.
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(controller.offset, closeTo(landed + 200, 1));

      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.offset, closeTo(landed + 200, 1));

      await tester.pumpAndSettle();
    });
  });

  // Tapping a quote jumps to the post it came from. On-page that's a scroll;
  // off-page it pushes, so Back returns to the reply that quoted it.
  group('quote jumps', () {
    ThreadPostsPage deepThread({required int quoteSource}) => ThreadPostsPage(
      title: 'Quoting thread',
      posts: [
        for (var i = 1; i <= 40; i++)
          ForumPost(
            postId: i,
            number: i,
            author: 'Member$i',
            blocks: [
              // The last post quotes; everything else is filler to scroll past.
              if (i == 40)
                ForumPostBlock(
                  kind: PostBlockKind.quote,
                  label: 'Member$quoteSource',
                  sourcePostId: quoteSource,
                  pieces: const [RichPiece.text('the quoted words')],
                ),
              ForumPostBlock(kind: PostBlockKind.rich, pieces: [RichPiece.text('body of post $i')]),
            ],
          ),
      ],
    );

    Future<void> pumpThread(WidgetTester tester, ThreadPostsPage thread) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ForumThreadScreen(
            url: 'https://f95zone.to/threads/quoting-thread.1/post-40',
            title: 'Quoting thread',
            fetchPosts: (url, {page = 1}) async => thread,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a quote of a post on this page scrolls back up to it', (tester) async {
      // Post 5 is far above post 40, so the jump has to search upward
      // through posts the lazy list has already unmounted.
      final thread = deepThread(quoteSource: 5);
      await pumpThread(tester, thread);

      expect(find.text('Member5 said:'), findsOneWidget);
      await tester.tap(find.text('Member5 said:'));
      await tester.pumpAndSettle();

      // Landed on post 5, no new screen pushed.
      expect(find.text('body of post 5'), findsOneWidget);
      expect(find.byType(ForumThreadScreen), findsOneWidget);
    });

    testWidgets('a quote of a post on another page pushes a screen at its permalink', (tester) async {
      // Post 900 is nowhere on this page.
      final thread = deepThread(quoteSource: 900);
      await pumpThread(tester, thread);

      await tester.tap(find.text('Member900 said:'));
      await tester.pumpAndSettle();

      // The permalink shape, which resolves to whichever page holds the post.
      final pushed = tester.widget<ForumThreadScreen>(find.byType(ForumThreadScreen));
      expect(pushed.url, 'https://f95zone.to/posts/900/');

      // The whole point of pushing: Back returns to the reply that quoted it,
      // rather than stranding the reader on a page they never chose.
      await tester.pageBack();
      await tester.pumpAndSettle();
      final back = tester.widget<ForumThreadScreen>(find.byType(ForumThreadScreen));
      expect(back.url, 'https://f95zone.to/threads/quoting-thread.1/post-40');
    });

    testWidgets('a quote the site gave no source for stays inert', (tester) async {
      final thread = ThreadPostsPage(
        title: 'Quoting thread',
        posts: const [
          ForumPost(
            postId: 1,
            number: 1,
            author: 'A',
            blocks: [
              // Hand-typed quote: no sourcePostId.
              ForumPostBlock(kind: PostBlockKind.quote, label: 'Someone', pieces: [RichPiece.text('typed by hand')]),
            ],
          ),
        ],
      );
      await pumpThread(tester, thread);

      await tester.tap(find.text('Someone said:'));
      await tester.pumpAndSettle();

      expect(find.byType(ForumThreadScreen), findsOneWidget);
    });
  });

  // The title bar's only action is an overflow menu; opening the thread in
  // the browser lives inside it (more options will join it later).
  testWidgets('the title-bar overflow opens the thread externally', (tester) async {
    final launched = <Uri>[];
    final postsPage = ThreadPostsPage(
      title: 'Overflow',
      posts: const [ForumPost(postId: 1, number: 1, author: 'A', blocks: [])],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/overflow.1/',
          title: 'Overflow',
          fetchPosts: (url, {page = 1}) async => postsPage,
          urlLauncher: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Thread tools'), findsOneWidget);

    await tester.tap(find.byTooltip('Thread tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(launched, [Uri.parse('https://example.com/threads/overflow.1/')]);
  });

  // "Search thread" opens the search screen scoped to this thread, id taken
  // from the canonical thread URL, with the screen's search plumbing along.
  testWidgets('the overflow opens a thread-scoped search', (tester) async {
    Future<ForumSearchPage> searcher(
      String keywords, {
      bool titleOnly = false,
      String user = '',
      String order = 'relevance',
      int? threadId,
    }) async => const ForumSearchPage(results: []);
    Future<List<UserSuggestion>> userFinder(String query) async => const [];

    final postsPage = ThreadPostsPage(
      title: 'Searchable',
      threadUrl: 'https://example.com/threads/searchable.207754/',
      posts: const [ForumPost(postId: 1, number: 1, author: 'A', blocks: [])],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ForumThreadScreen(
          url: 'https://example.com/threads/searchable.207754/',
          title: 'Searchable',
          fetchPosts: (url, {page = 1}) async => postsPage,
          searcher: searcher,
          userFinder: userFinder,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thread tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search thread'));
    await tester.pumpAndSettle();

    final search = tester.widget<ForumSearchScreen>(find.byType(ForumSearchScreen));
    expect(search.scopeThreadId, 207754);
    expect(search.searcher, same(searcher));
    expect(search.userFinder, same(userFinder));
  });

  // A mid-thread page shows the widest arrangement — 1 … n-1 n n+1 … last.
  // Long page numbers blow that past a phone's width, so the row sheds its
  // adjacent pages and, failing that, scales; either way it never overflows
  // and never drops first, current, or last.
  group('pagination', () {
    Future<void> pumpAt(WidgetTester tester, {required int current, required int total, required double width}) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final postsPage = ThreadPostsPage(
        title: 'Long thread',
        currentPage: current,
        totalPages: total,
        posts: const [ForumPost(postId: 1, number: 1, author: 'A', blocks: [])],
      );

      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('$current/$total@$width'),
          theme: ThemeData.dark(),
          home: ForumThreadScreen(
            url: 'https://example.com/threads/long.1/',
            title: 'Long thread',
            initialPage: current,
            fetchPosts: (url, {page = 1}) async => postsPage,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// How far the pills ended up shrunk; 1.0 means they render full size.
    double pillScale(WidgetTester tester) {
      final fitted = tester.renderObject<RenderBox>(find.byType(FittedBox)) as RenderFittedBox;
      return fitted.size.width / fitted.child!.size.width;
    }

    // Where the row gives up its neighbours depends on the font: the test
    // font draws every glyph a full font-size wide, so clusters measure
    // ~40% wider here than they do in Roboto on a device. Cases near the
    // crossover would therefore prove nothing about the real thing — these
    // stay on whichever side of it both fonts agree on.

    testWidgets('keeps the adjacent pages when they fit', (tester) async {
      await pumpAt(tester, current: 10, total: 20, width: 411);

      expect(tester.takeException(), isNull);
      for (final label in ['1', '9', '10', '11', '20']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('drops the adjacent pages at five digits', (tester) async {
      await pumpAt(tester, current: 10002, total: 20839, width: 360);

      expect(tester.takeException(), isNull);
      expect(find.text('10001'), findsNothing);
      expect(find.text('10003'), findsNothing);
      // The three that carry the navigation survive either way.
      for (final label in ['1', '10002', '20839']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    // The case that started this: five digits shrank the pills to roughly
    // 3mm. Shedding n±1 buys back the width to render them full size.
    testWidgets('a five-digit thread renders its pills unshrunk', (tester) async {
      await pumpAt(tester, current: 10002, total: 20839, width: 411);

      expect(tester.takeException(), isNull);
      expect(pillScale(tester), 1.0);
    });

    // The gap is a pill among pills, so it has to stand the same height as
    // the numbers it separates. Easy to lose: a `height` on its text style
    // shortens the line box without touching the padding.
    testWidgets('the gap pill stands as tall as the page pills', (tester) async {
      await pumpAt(tester, current: 10, total: 20, width: 411);

      double pillHeight(String label) => tester
          .renderObject<RenderBox>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first)
          .size
          .height;

      expect(pillHeight('…'), pillHeight('10'));
      expect(pillHeight('…'), pillHeight('1'));
    });

    // Scaling is the backstop for whatever the fit estimate fails to
    // anticipate — a wider font, a bumped text size, numbers past anything
    // sane. Nothing is allowed to overflow.
    testWidgets('scales rather than overflow when even the short row is too wide', (tester) async {
      await pumpAt(tester, current: 100002, total: 208390, width: 320);

      expect(tester.takeException(), isNull);
      expect(pillScale(tester), lessThan(1.0));
      expect(find.text('100002'), findsOneWidget);
    });

    for (final size in const [320.0, 360.0, 411.0]) {
      for (final total in const [20, 300, 20839]) {
        testWidgets('page ${total ~/ 2} of $total at ${size.toInt()}dp stays in its row', (tester) async {
          await pumpAt(tester, current: total ~/ 2, total: total, width: size);

          expect(tester.takeException(), isNull);
          for (final label in ['1', '${total ~/ 2}', '$total']) {
            expect(find.text(label), findsOneWidget);
          }
        });
      }
    }
  });
}
