import 'package:cached_network_image/cached_network_image.dart';
import 'package:f95_portal/widgets/cover_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/widget_test_utils.dart';

void main() {
  const preview = 'https://preview.f95zone.to/2023/02/2416942_main_menu.png';
  const hd = 'https://attachments.f95zone.to/2023/02/2416942_main_menu.png';

  Iterable<String> imageUrls(WidgetTester tester) =>
      tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).map((w) => w.imageUrl);

  testWidgets('loads the HD variant with the preview as placeholder and fallback', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: preview));
    await tester.pump();

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

  testWidgets('skips the HD upgrade when upgradeToHd is false (reflection copy)', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: preview, upgradeToHd: false));
    await tester.pumpAndSettle();

    expect(imageUrls(tester).toList(), [preview]);
  });

  testWidgets('decodes at the display width instead of the source size', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: preview));
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage).first);
    expect(image.memCacheWidth, isNotNull);
    expect(image.memCacheWidth, greaterThan(0));
  });

  testWidgets('shows the plain placeholder without a URL', (tester) async {
    await pumpTestApp(tester, const CoverImage(imageUrl: null));
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
