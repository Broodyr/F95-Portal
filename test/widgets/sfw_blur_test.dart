import 'package:f95_portal/widgets/cover_image.dart';
import 'package:f95_portal/widgets/sfw_blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_settings_storage.dart';
import '../helpers/widget_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('covers are blurred only while SFW mode is on', (tester) async {
    final service = installTestSettings();

    await pumpTestApp(tester, const CoverImage(imageUrl: 'https://example.com/c.png'));
    await tester.pump();

    expect(find.byType(SfwBlur), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);

    await service.update(service.settings.copyWith(sfwBlur: true));
    await tester.pump();

    expect(find.byType(ImageFiltered), findsOneWidget);

    // Flush cached_network_image's internal timers before teardown.
    await tester.pump(const Duration(minutes: 1));
  });
}
