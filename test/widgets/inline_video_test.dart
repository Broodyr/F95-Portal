import 'package:f95_portal/widgets/inline_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('shows a play placeholder without touching the network', (tester) async {
    await tester.pumpWidget(wrap(const InlineVideo(url: 'https://f95zone.to/data/video/1/1.mp4')));
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('a load that fails degrades to an error state, tappable to retry', (tester) async {
    await tester.pumpWidget(wrap(const InlineVideo(url: 'https://f95zone.to/data/video/1/1.mp4')));
    await tester.pump();

    // No video platform exists under flutter_test, so the load fails; the
    // widget must absorb that rather than crash the post.
    await tester.tap(find.byType(InlineVideo));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);

    // Tapping the error state tries again (and fails again, quietly).
    await tester.tap(find.byType(InlineVideo));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
  });
}
