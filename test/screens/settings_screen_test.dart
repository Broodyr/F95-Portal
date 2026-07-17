import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/screens/settings_screen.dart';
import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/search_options_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_settings_storage.dart';
import '../helpers/metadata_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService service;
  late SettingsService previous;

  setUpAll(() {
    loadAndInstallMetadata();
  });

  setUp(() {
    previous = SettingsService.instance;
    service = installTestSettings();
  });

  tearDown(() {
    SettingsService.instance = previous;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const SettingsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('SFW switch round-trips to the service', (tester) async {
    await pumpSettings(tester);

    expect(service.settings.sfwBlur, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'SFW mode'));
    await tester.pumpAndSettle();

    expect(service.settings.sfwBlur, isTrue);
  });

  testWidgets('glass effects switch round-trips to the service', (tester) async {
    await pumpSettings(tester);

    expect(service.settings.glassEffects, isTrue);

    await tester.ensureVisible(find.widgetWithText(SwitchListTile, 'Glass effects'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Glass effects'));
    await tester.pumpAndSettle();

    expect(service.settings.glassEffects, isFalse);
  });

  testWidgets('edit defaults opens the search modal and persists the result', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Edit defaults'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchOptionsModal), findsOneWidget);

    // Sections start collapsed; expand Category first.
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comics'));
    await tester.pumpAndSettle();
    // In the settings context the submit button is relabeled.
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(service.settings.defaultQuery.category, SearchCategory.comics);
  });

  testWidgets('dismissing the defaults modal without saving still persists', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Edit defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comics'));
    await tester.pumpAndSettle();

    // Dismiss without submitting (same pop-with-null path as swipe-down
    // or a barrier tap).
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.byType(SearchOptionsModal), findsNothing);
    expect(service.settings.defaultQuery.category, SearchCategory.comics);
  });

  testWidgets('defaults summary shows tag names and reset restores blank', (tester) async {
    await service.update(
      service.settings.copyWith(
        defaultQuery: const SearchQuery(notags: [258], category: SearchCategory.games),
      ),
    );
    await pumpSettings(tester);

    expect(find.text('netorare'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(service.settings.defaultQuery, const SearchQuery());
    expect(find.text('netorare'), findsNothing);
  });
}
