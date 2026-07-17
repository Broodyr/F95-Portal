import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/glass_fab.dart';

import '../helpers/in_memory_settings_storage.dart';

void main() {
  late SettingsService service;
  late SettingsService previous;

  setUp(() {
    previous = SettingsService.instance;
    service = installTestSettings();
  });

  tearDown(() {
    SettingsService.instance = previous;
  });

  Future<ScrollController> pumpFab(WidgetTester tester, {VoidCallback? onPressed}) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                controller: controller,
                children: [for (int i = 0; i < 60; i++) SizedBox(height: 40, child: Text('row $i'))],
              ),
              Positioned(
                right: 32,
                bottom: 24,
                child: GlassFab(
                  icon: Icons.reply,
                  tooltip: 'Reply',
                  scrollController: controller,
                  onPressed: onPressed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('renders 56pt with backdrop blur when glass effects are on', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: true));
    await pumpFab(tester);

    expect(tester.getSize(find.byType(GlassFab)), const Size(56, 56));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('skips the blur for a near-opaque fill when glass effects are off', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: false));
    await pumpFab(tester);

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('tap fires onPressed', (tester) async {
    int taps = 0;
    await pumpFab(tester, onPressed: () => taps++);

    await tester.tap(find.byType(GlassFab));
    expect(taps, 1);
  });

  testWidgets('vertical drags pass through to the list underneath', (tester) async {
    final controller = await pumpFab(tester);

    await tester.drag(find.byType(GlassFab), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });
}
