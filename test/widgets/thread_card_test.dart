import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/app_text_scale.dart';
import 'package:f95_portal/widgets/thread_card.dart';

import '../helpers/in_memory_settings_storage.dart';
import '../helpers/metadata_test_utils.dart';
import '../helpers/test_data.dart';
import '../helpers/widget_test_utils.dart';

void main() {
  late SettingsService service;
  late SettingsService previous;

  setUpAll(loadAndInstallMetadata);

  setUp(() {
    previous = SettingsService.instance;
    service = installTestSettings();
  });

  tearDown(() {
    SettingsService.instance = previous;
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppTextScale(child: child!),
        home: Scaffold(body: ThreadCard(thread: createThreadSummary())),
      ),
    );
  }

  testWidgets('reflection uses backdrop blur when glass effects are on', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: true));
    await pumpCard(tester);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('reflection skips backdrop blur when glass effects are off', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: false));
    await pumpCard(tester);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('title stays anchored at 18pt (17pt on small) under the app text scale', (tester) async {
    double titleSize() => effectiveFontSize(tester, find.text('Test Thread'));

    await pumpCard(tester);
    expect(titleSize(), moreOrLessEquals(18));

    await service.update(service.settings.copyWith(fontSize: FontSizeOption.large));
    await tester.pump();
    expect(titleSize(), moreOrLessEquals(18));

    await service.update(service.settings.copyWith(fontSize: FontSizeOption.small));
    await tester.pump();
    expect(titleSize(), moreOrLessEquals(17));
  });

  testWidgets('toggling glass effects off removes the blur without a remount', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: true));
    await pumpCard(tester);
    expect(find.byType(BackdropFilter), findsOneWidget);

    await service.update(service.settings.copyWith(glassEffects: false));
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
