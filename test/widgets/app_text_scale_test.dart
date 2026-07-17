import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/app_text_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_settings_storage.dart';
import '../helpers/widget_test_utils.dart';

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

  Future<void> pumpSample(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppTextScale(child: Text('sample', style: TextStyle(fontSize: 10))),
      ),
    );
  }

  testWidgets('medium (the default) scales text up', (tester) async {
    await pumpSample(tester);
    expect(effectiveFontSize(tester, find.text('sample')), moreOrLessEquals(10 * FontSizeOption.medium.scale));
  });

  testWidgets('small renders base sizes unchanged', (tester) async {
    await service.update(service.settings.copyWith(fontSize: FontSizeOption.small));
    await pumpSample(tester);
    expect(effectiveFontSize(tester, find.text('sample')), moreOrLessEquals(10));
  });

  testWidgets('changing the setting rescales live', (tester) async {
    await pumpSample(tester);

    await service.update(service.settings.copyWith(fontSize: FontSizeOption.large));
    await tester.pump();

    expect(effectiveFontSize(tester, find.text('sample')), moreOrLessEquals(10 * FontSizeOption.large.scale));
  });

  testWidgets('composes with the OS accessibility scale', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: AppTextScale(child: Text('sample', style: TextStyle(fontSize: 10))),
        ),
      ),
    );
    expect(effectiveFontSize(tester, find.text('sample')), moreOrLessEquals(20 * FontSizeOption.medium.scale));
  });
}
