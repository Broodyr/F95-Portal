import 'package:f95_portal/widgets/cover_image.dart';
import 'package:f95_portal/widgets/remote_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/widget_test_utils.dart';

void main() {
  const preview = 'https://preview.f95zone.to/2023/02/2416942_main_menu.png';
  const hd = 'https://attachments.f95zone.to/2023/02/2416942_main_menu.png';

  Iterable<String> imageUrls(WidgetTester tester) =>
      tester.widgetList<RemoteImage>(find.byType(RemoteImage)).map((w) => w.url);

  testWidgets('shows the preview immediately, upgrading to HD only after the delay', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: preview));
    await tester.pump();

    // Before the upgrade delay only the low-res preview is requested, so
    // cards flung past during a fast scroll never start HD work.
    expect(imageUrls(tester).toList(), [preview]);

    await tester.pump(CoverImage.hdUpgradeDelay + const Duration(milliseconds: 50));
    expect(imageUrls(tester), contains(hd));

    // No network in tests: the HD load fails, and the fallback shown in its
    // place is the low-res preview.
    await tester.pumpAndSettle();
    expect(imageUrls(tester), contains(preview));
  });

  testWidgets('uses the URL as-is when no HD variant is known', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: hd));
    await tester.pump();

    expect(imageUrls(tester).toList(), [hd]);
  });

  testWidgets('the preview layer keeps its element when the HD overlay appears', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: preview));
    await tester.pump();

    previewFinder() => find.byWidgetPredicate((w) => w is RemoteImage && w.url == preview);
    final stateBefore = tester.state(previewFinder());

    await tester.pump(CoverImage.hdUpgradeDelay + const Duration(milliseconds: 50));

    // Same State object: the HD flip must not restart the preview's
    // loading pipeline (that's what left bare placeholders mid-scroll).
    expect(tester.state(previewFinder()), same(stateBefore));
    await tester.pumpAndSettle();
  });

  testWidgets('skips the HD upgrade when upgradeToHd is false (reflection copy)', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: preview, upgradeToHd: false));
    await tester.pumpAndSettle();

    expect(imageUrls(tester).toList(), [preview]);
  });

  testWidgets('decodes at the display width instead of the source size', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: preview));
    await tester.pump();

    final image = tester.widget<RemoteImage>(find.byType(RemoteImage).first);
    expect(image.decodeWidth, isNotNull);
    expect(image.decodeWidth, greaterThan(0));
  });

  testWidgets('shows the plain placeholder without a URL', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: null));
    await tester.pump();

    expect(find.byType(RemoteImage), findsNothing);
  });
}
