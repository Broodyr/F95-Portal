import 'package:f95_portal/widgets/screenshot_gallery.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
