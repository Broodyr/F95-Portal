import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/widgets/remote_image.dart';
import 'package:f95_portal/widgets/rich_spoiler_text.dart';
import 'package:f95_portal/widgets/image_gallery.dart';
import 'package:f95_portal/widgets/inline_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping an image opens the gallery with every image, positioned there', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RichSpoilerText(
            pieces: const [
              RichPiece.text('Two shots:'),
              RichPiece.image('https://example.com/thumb/a.jpg', fullImageUrl: 'https://example.com/a.jpg'),
              RichPiece.image('https://example.com/thumb/b.jpg', fullImageUrl: 'https://example.com/b.jpg'),
            ],
            onOpenLink: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(RemoteImage).at(1));
    // The gallery's spinner never settles; use fixed pumps.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final gallery = tester.widget<ImageGallery>(find.byType(ImageGallery));
    expect(gallery.urls, ['https://example.com/a.jpg', 'https://example.com/b.jpg']);
    expect(gallery.initialIndex, 1);

    // cached_network_image leaves pending timers.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a caller-provided gallery replaces the block-scoped one, offset applied', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RichSpoilerText(
            pieces: const [
              RichPiece.image('https://example.com/thumb/c.jpg', fullImageUrl: 'https://example.com/c.jpg'),
            ],
            onOpenLink: (_) {},
            galleryUrls: const ['https://example.com/a.jpg', 'https://example.com/b.jpg', 'https://example.com/c.jpg'],
            galleryIndexOffset: 2,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(RemoteImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final gallery = tester.widget<ImageGallery>(find.byType(ImageGallery));
    expect(gallery.urls, ['https://example.com/a.jpg', 'https://example.com/b.jpg', 'https://example.com/c.jpg']);
    expect(gallery.initialIndex, 2);

    // cached_network_image leaves pending timers.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a video piece renders an inline player block', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RichSpoilerText(
            pieces: const [
              RichPiece.text('Watch:'),
              RichPiece.video('https://f95zone.to/data/video/1/1.mp4'),
            ],
            onOpenLink: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final video = tester.widget<InlineVideo>(find.byType(InlineVideo));
    expect(video.url, 'https://f95zone.to/data/video/1/1.mp4');
  });

  testWidgets('smilies render as inline assets, unknown ones as their shortcode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RichSpoilerText(
            pieces: const [
              RichPiece.text('gg '),
              RichPiece.smilie(':love:', asset: 'assets/smilies/love.png'),
              RichPiece.smilie(':lepew:'),
            ],
            onOpenLink: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/smilies/love.png');

    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.textSpan!.toPlainText(), contains(':lepew:'));
  });

  testWidgets('smilie size follows the ambient text scale', (tester) async {
    Future<Image> pumpScaled(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: RichSpoilerText(
                pieces: const [RichPiece.smilie(':love:', asset: 'assets/smilies/love.png')],
                onOpenLink: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.widget<Image>(find.byType(Image));
    }

    final normal = await pumpScaled(1.0);
    final large = await pumpScaled(1.5);
    expect(large.width!, greaterThan(normal.width!));
  });

  // An image with no reserved space grows the post when it lands, shoving
  // whatever the reader was looking at down the screen. Where the markup
  // states a size, the space is held in advance instead.
  group('space held for an image before it loads', () {
    Future<Size> placeholderSize(WidgetTester tester, RichPiece piece, {double width = 400}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: RichSpoilerText(pieces: [piece], onOpenLink: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump();
      // The image never loads in a test, so what stands in its place is the
      // reserved box itself.
      return tester.getSize(find.byType(RemoteImage));
    }

    testWidgets('a stated size is held at the height the image will render', (tester) async {
      // 480x360 fits under the 180 cap by height, so it lands scaled to 180
      // tall and keeps its ratio.
      final size = await placeholderSize(
        tester,
        const RichPiece.image('https://example.com/a.jpg', imageWidth: 480, imageHeight: 360),
      );
      expect(size.height, closeTo(180, 0.01));
      expect(size.width, closeTo(240, 0.01));
    });

    testWidgets('a wide image is held at the height its column allows', (tester) async {
      // 1920x620 in a 400 wide column: the width binds first, so the box is
      // shorter than the cap rather than the full 180.
      final size = await placeholderSize(
        tester,
        const RichPiece.image('https://example.com/a.jpg', imageWidth: 1920, imageHeight: 620),
        width: 400,
      );
      expect(size.width, closeTo(400, 1));
      expect(size.height, closeTo(400 * 620 / 1920, 1));
    });

    testWidgets('an unstated size falls back to the old fixed block', (tester) async {
      final size = await placeholderSize(tester, const RichPiece.image('https://example.com/a.jpg'));
      expect(size, const Size(120, 80));
    });

    testWidgets('a caller-lowered image cap also caps the held space', (tester) async {
      // The signature rendering caps images well below the body's 180.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: RichSpoilerText(
                pieces: const [RichPiece.image('https://example.com/a.jpg', imageWidth: 480, imageHeight: 360)],
                onOpenLink: (_) {},
                maxImageHeight: 80,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final size = tester.getSize(find.byType(RemoteImage));
      expect(size.height, closeTo(80, 0.01));
      expect(size.width, closeTo(80 * 480 / 360, 0.01));
    });
  });

  // The thin crimson is hard to read at body size, so a link is drawn a step
  // heavier than surrounding text — but still under bold, so it never reads as
  // emphasis.
  group('link weight', () {
    TextStyle? spanStyleFor(WidgetTester tester, String text) {
      final root = tester.widget<Text>(find.byType(Text).first).textSpan! as TextSpan;
      TextStyle? found;
      root.visitChildren((span) {
        if (span is TextSpan && span.text == text) {
          found = span.style;
          return false;
        }
        return true;
      });
      return found;
    }

    testWidgets('a link sits between body and bold weight, in the theme primary', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RichSpoilerText(
              pieces: const [
                RichPiece.text('the docs', url: 'https://example.com'),
                RichPiece.text(' now'),
              ],
              onOpenLink: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final link = spanStyleFor(tester, 'the docs')!;
      final body = spanStyleFor(tester, ' now')!;
      expect(link.fontWeight, FontWeight.w500);
      expect(body.fontWeight, isNull); // inherits the body weight
      expect(link.color, ThemeData.dark().colorScheme.primary);
    });

    testWidgets('a bold link keeps bold weight, not the lighter link weight', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RichSpoilerText(
              pieces: const [
                RichPiece.text('boldlink', url: 'https://example.com', bold: true),
              ],
              onOpenLink: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(spanStyleFor(tester, 'boldlink')!.fontWeight, FontWeight.w600);
    });

    testWidgets('a link gets a muted crimson underline; [u] markup keeps its own', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RichSpoilerText(
              pieces: const [
                RichPiece.text('underlined', underline: true),
                RichPiece.text('a link', url: 'https://example.com'),
              ],
              onOpenLink: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final marked = spanStyleFor(tester, 'underlined')!;
      final link = spanStyleFor(tester, 'a link')!;
      expect(marked.decoration!.contains(TextDecoration.underline), isTrue);
      expect(link.decoration!.contains(TextDecoration.underline), isTrue);
      expect(link.decorationColor, ThemeData.dark().colorScheme.primary.withValues(alpha: 0.5));
    });
  });
}
