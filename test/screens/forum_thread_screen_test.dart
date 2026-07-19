import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/widgets/remote_image.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/widgets/screenshot_gallery.dart';
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

    final gallery = tester.widget<ScreenshotGallery>(find.byType(ScreenshotGallery));
    expect(gallery.urls, ['https://example.com/q.jpg', 'https://example.com/a.jpg', 'https://example.com/b.jpg']);
    expect(gallery.initialIndex, 2);

    // cached_network_image leaves pending timers.
    await tester.pump(const Duration(minutes: 1));
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

    await tester.tap(find.text('Quote'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    // The member id is what makes the site alert the quoted user; smilies
    // come through as their shortcode.
    expect(field.controller!.text, '[QUOTE="VoidTraveler, post: 42, member: 3590149"]\nhello there:love:\n[/QUOTE]\n');
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
