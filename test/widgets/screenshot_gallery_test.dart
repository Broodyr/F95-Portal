import 'package:f95_portal/widgets/screenshot_gallery.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads every image on open, nearest to the opened one first', (tester) async {
    final fetched = <String>[];
    final original = ScreenshotGallery.downloadBytes;
    ScreenshotGallery.downloadBytes = (url) async => fetched.add(url);
    addTearDown(() => ScreenshotGallery.downloadBytes = original);

    await tester.pumpWidget(
      const MaterialApp(
        home: ScreenshotGallery(
          urls: ['https://example.com/a.png', 'https://example.com/b.png', 'https://example.com/c.png', 'https://example.com/d.png'],
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

  Future<void> pumpGallery(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ScreenshotGallery(urls: ['https://example.com/a.png', 'https://example.com/b.png'])),
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
              onPressed: () => ScreenshotGallery.show(
                context,
                const ['https://example.com/a.png', 'https://example.com/b.png'],
              ),
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

    expect(find.byType(ScreenshotGallery), findsNothing);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('swiping up closes the viewer', (tester) async {
    await pumpPushedGallery(tester);

    await tester.dragFrom(tester.getCenter(find.byType(PageView)), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScreenshotGallery), findsNothing);

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

    expect(find.byType(ScreenshotGallery), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('backdrop fades with drag distance and the route shows through', (tester) async {
    await pumpPushedGallery(tester);

    // The screen behind must stay in the tree (transparent route) for the
    // fade to reveal anything.
    expect(find.text('open', skipOffstage: false), findsOneWidget);

    Color backdropColor() =>
        (tester.widget<ColoredBox>(find.byKey(const ValueKey('gallery-backdrop'))).color);

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

    expect(find.byType(ScreenshotGallery), findsOneWidget);
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

    expect(find.byType(ScreenshotGallery), findsOneWidget);

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
}
