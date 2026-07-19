import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/widgets/remote_image.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/widgets/screenshot_gallery.dart';
import 'package:flutter/material.dart';
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

  // A mid-thread page shows the widest arrangement — 1 … n-1 n n+1 … last —
  // and at three digits it runs ~100px past a phone's width. The number
  // cluster scales to fit instead of overflowing, so no page is ever clipped.
  group('pagination fits the row', () {
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

    for (final size in const [360.0, 411.0]) {
      for (final pages in const [[10, 20], [150, 300]]) {
        testWidgets('page ${pages[0]} of ${pages[1]} at ${size.toInt()}dp', (tester) async {
          await pumpAt(tester, current: pages[0], total: pages[1], width: size);

          expect(tester.takeException(), isNull);
          // Every pill in the neighborhood survives the squeeze.
          for (final label in ['1', '${pages[0] - 1}', '${pages[0]}', '${pages[0] + 1}', '${pages[1]}']) {
            expect(find.text(label), findsOneWidget);
          }
        });
      }
    }
  });
}
