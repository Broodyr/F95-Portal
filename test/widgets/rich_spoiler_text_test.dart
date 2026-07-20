import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/widgets/remote_image.dart';
import 'package:f95_portal/widgets/rich_spoiler_text.dart';
import 'package:f95_portal/widgets/image_gallery.dart';
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
}
