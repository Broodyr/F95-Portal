import 'dart:async';

import 'package:f95_portal/services/image_save.dart';
import 'package:f95_portal/widgets/image_gallery.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads every image on open, nearest to the opened one first', (tester) async {
    final fetched = <String>[];
    final original = ImageGallery.downloadBytes;
    ImageGallery.downloadBytes = (url) async => fetched.add(url);
    addTearDown(() => ImageGallery.downloadBytes = original);

    await tester.pumpWidget(
      const MaterialApp(
        home: ImageGallery(
          urls: [
            'https://example.com/a.png',
            'https://example.com/b.png',
            'https://example.com/c.png',
            'https://example.com/d.png',
          ],
          initialIndex: 2,
        ),
      ),
    );
    await tester.pump();

    expect(fetched, [
      'https://example.com/c.png',
      'https://example.com/d.png',
      'https://example.com/b.png',
      'https://example.com/a.png',
    ]);

    // Let cached_network_image's internal timers expire before teardown.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('prefetch never runs more than a few downloads at once', (tester) async {
    final started = <String>[];
    final completers = <String, Completer<void>>{};
    final original = ImageGallery.downloadBytes;
    ImageGallery.downloadBytes = (url) {
      started.add(url);
      return (completers[url] = Completer<void>()).future;
    };
    addTearDown(() => ImageGallery.downloadBytes = original);

    await tester.pumpWidget(
      MaterialApp(home: ImageGallery(urls: [for (var i = 0; i < 6; i++) 'https://example.com/$i.png'])),
    );
    await tester.pump();

    // A burst of simultaneous requests is what gets the first images
    // rejected by the CDN; only a small window may be in flight.
    expect(started, ['https://example.com/0.png', 'https://example.com/1.png', 'https://example.com/2.png']);

    // Finishing one download frees its slot for the next queued URL.
    completers['https://example.com/1.png']!.complete();
    await tester.pump();
    expect(started.last, 'https://example.com/3.png');
    expect(started.length, 4);

    completers['https://example.com/0.png']!.complete();
    await tester.pump();
    expect(started.last, 'https://example.com/4.png');
    expect(started.length, 5);

    // Let cached_network_image's internal timers expire before teardown.
    await tester.pump(const Duration(minutes: 1));
  });

  Future<void> pumpGallery(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ImageGallery(urls: ['https://example.com/a.png', 'https://example.com/b.png'])),
    );
    await tester.pump();
  }

  PageView pageView(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView));

  testWidgets('a second finger disables page swiping so pinch zoom wins', (tester) async {
    await pumpGallery(tester);

    expect(pageView(tester).physics, isNot(isA<NeverScrollableScrollPhysics>()));

    final firstFinger = await tester.startGesture(const Offset(300, 300));
    final secondFinger = await tester.startGesture(const Offset(500, 300));
    await tester.pump();

    expect(pageView(tester).physics, isA<NeverScrollableScrollPhysics>());

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();

    expect(pageView(tester).physics, isNot(isA<NeverScrollableScrollPhysics>()));

    // Let cached_network_image's internal timers expire before teardown.
    await tester.pump(const Duration(minutes: 1));
  });

  Future<void> pumpPushedGallery(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  ImageGallery.show(context, const ['https://example.com/a.png', 'https://example.com/b.png']),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('swiping down closes the viewer', (tester) async {
    await pumpPushedGallery(tester);

    await tester.dragFrom(tester.getCenter(find.byType(PageView)), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ImageGallery), findsNothing);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('swiping up closes the viewer', (tester) async {
    await pumpPushedGallery(tester);

    await tester.dragFrom(tester.getCenter(find.byType(PageView)), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ImageGallery), findsNothing);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a small slow vertical drag snaps back instead of closing', (tester) async {
    await pumpPushedGallery(tester);

    await tester.timedDragFrom(
      tester.getCenter(find.byType(PageView)),
      const Offset(0, 60),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ImageGallery), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('backdrop fades with drag distance and the route shows through', (tester) async {
    await pumpPushedGallery(tester);

    // The screen behind must stay in the tree (transparent route) for the
    // fade to reveal anything.
    expect(find.text('open', skipOffstage: false), findsOneWidget);

    Color backdropColor() => (tester.widget<ColoredBox>(find.byKey(const ValueKey('gallery-backdrop'))).color);

    expect(backdropColor().a, 1.0);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PageView)));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final midDragAlpha = backdropColor().a;
    expect(midDragAlpha, lessThan(1.0));

    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(backdropColor().a, lessThan(midDragAlpha));

    // Releasing below the dismiss threshold restores full black.
    await gesture.moveBy(const Offset(0, -190));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(backdropColor().a, 1.0);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('horizontal swiping still changes pages', (tester) async {
    await pumpPushedGallery(tester);

    expect(find.text('1 / 2'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ImageGallery), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('vertical drag while zoomed pans instead of closing', (tester) async {
    await pumpPushedGallery(tester);

    final center = tester.getCenter(find.byType(PageView));
    await tester.tapAt(center);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(center);
    await tester.pump();

    await tester.dragFrom(center, const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ImageGallery), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  /// Zooms in and pans hard left so the image sits pinned against its right
  /// edge — the state a swipe-to-next-image has to start from.
  Future<void> zoomToRightEdge(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(PageView));
    await tester.tapAt(center);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.dragFrom(center, const Offset(-700, 0));
    await tester.pump();
  }

  testWidgets('a mostly vertical drag past the edge still flips to the next image', (tester) async {
    await pumpPushedGallery(tester);
    await zoomToRightEdge(tester);

    expect(find.text('1 / 2'), findsOneWidget);

    // A real diagonal swipe wobbles in x from frame to frame; the flip has
    // to survive that rather than be cancelled by the first opposing pixel.
    final gesture = await tester.startGesture(tester.getCenter(find.byType(PageView)));
    var time = Duration.zero;
    for (var i = 0; i < 24; i++) {
      time += const Duration(milliseconds: 16);
      await gesture.moveBy(Offset(i.isEven ? -10 : 2, -12), timeStamp: time);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up(timeStamp: time);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2 / 2'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a quick flick past the edge flips without a full-length drag', (tester) async {
    await pumpPushedGallery(tester);
    await zoomToRightEdge(tester);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PageView)));
    var time = Duration.zero;
    for (var i = 0; i < 6; i++) {
      time += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-9, -18), timeStamp: time);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 54px of pull — well under the deliberate-drag distance, but fast.
    await gesture.up(timeStamp: time);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2 / 2'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a small slow pull past the edge stays on the current image', (tester) async {
    await pumpPushedGallery(tester);
    await zoomToRightEdge(tester);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PageView)));
    var time = Duration.zero;
    for (var i = 0; i < 8; i++) {
      time += const Duration(milliseconds: 50);
      await gesture.moveBy(const Offset(-5, 0), timeStamp: time);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up(timeStamp: time);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1 / 2'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('page swiping stays disabled while zoomed in', (tester) async {
    await pumpGallery(tester);

    final center = tester.getCenter(find.byType(PageView));
    await tester.tap(find.byType(PageView));
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(center);
    await tester.pump();

    expect(pageView(tester).physics, isA<NeverScrollableScrollPhysics>());

    await tester.pump(const Duration(minutes: 1));
  });

  /// Stubs both the prefetch and the save so no test touches the network
  /// or the platform, and returns the list the download button appends to.
  List<String> stubSaving(
    WidgetTester tester, {
    ImageSaveResult result = ImageSaveResult.saved,
    Future<void> Function(String url)? onSave,
  }) {
    final saved = <String>[];
    final originalDownload = ImageGallery.downloadBytes;
    final originalSave = ImageGallery.saveImage;
    ImageGallery.downloadBytes = (_) async {};
    ImageGallery.saveImage = (url) async {
      saved.add(url);
      if (onSave != null) await onSave(url);
      return result;
    };
    addTearDown(() {
      ImageGallery.downloadBytes = originalDownload;
      ImageGallery.saveImage = originalSave;
    });
    return saved;
  }

  final downloadButton = find.byKey(const ValueKey('gallery-download'));

  testWidgets('the download button saves the image being viewed', (tester) async {
    final saved = stubSaving(tester);
    await pumpPushedGallery(tester);

    await tester.tap(downloadButton);
    await tester.pump();

    expect(saved, ['https://example.com/a.png']);

    // After a swipe it saves the new image, not the one it opened on.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(downloadButton);
    await tester.pump();

    expect(saved, ['https://example.com/a.png', 'https://example.com/b.png']);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('repeat taps while a save is in flight are ignored', (tester) async {
    final completer = Completer<void>();
    final saved = stubSaving(tester, onSave: (_) => completer.future);
    await pumpPushedGallery(tester);

    await tester.tap(downloadButton);
    await tester.pump();

    // The share sheet takes a beat to appear and the button stays live
    // behind it; a second tap must not start a second save.
    await tester.tap(downloadButton);
    await tester.pump();
    expect(saved, ['https://example.com/a.png']);

    completer.complete();
    await tester.pump();
    await tester.tap(downloadButton);
    await tester.pump();
    expect(saved.length, 2);

    await tester.pump(const Duration(minutes: 1));
  });

  /// Taps download and settles the toast.
  ///
  /// Toasts are found with findsWidgets, not findsOneWidget: the messenger
  /// puts one in every registered Scaffold, and the gallery's route is
  /// transparent so the screen behind is still one of them. They land on
  /// top of each other, so it reads as a single toast.
  Future<void> tapDownload(WidgetTester tester) async {
    await tester.tap(downloadButton);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a saved image is confirmed — it lands outside the app', (tester) async {
    stubSaving(tester);
    await pumpPushedGallery(tester);

    await tapDownload(tester);

    expect(find.text('Saved to your photos'), findsWidgets);

    await tester.pump(const Duration(minutes: 1));
  });

  // An animated source saves as one frame, because Flutter has no
  // animated format to encode into. Saying plain "saved" would overstate
  // what the user got.
  testWidgets('an animation saved as one frame says so', (tester) async {
    stubSaving(tester, result: ImageSaveResult.savedAsStill);
    await pumpPushedGallery(tester);

    await tapDownload(tester);

    expect(find.text('Saved as a still image'), findsWidgets);
    expect(find.text('Saved to your photos'), findsNothing);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('refusing photo access says so rather than looking broken', (tester) async {
    stubSaving(tester, result: ImageSaveResult.denied);
    await pumpPushedGallery(tester);

    await tapDownload(tester);

    expect(find.text('Photo access is needed to save images'), findsWidgets);
    expect(find.byType(ImageGallery), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a failed save tells the user', (tester) async {
    stubSaving(tester, result: ImageSaveResult.failed);
    await pumpPushedGallery(tester);

    await tapDownload(tester);

    expect(find.text("Couldn't save image"), findsWidgets);
    // The viewer stays put; a failed save is not a reason to lose the image.
    expect(find.byType(ImageGallery), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a save that throws is reported, not swallowed into a crash', (tester) async {
    stubSaving(tester, onSave: (_) async => throw Exception('plugin blew up'));
    await pumpPushedGallery(tester);

    await tapDownload(tester);

    expect(find.text("Couldn't save image"), findsWidgets);
    expect(find.byType(ImageGallery), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });
}
