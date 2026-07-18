import 'package:f95_portal/models/account.dart';
import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/screens/settings_screen.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/search_options_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cookie_storage.dart';
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

  testWidgets('text size selector round-trips to the service', (tester) async {
    await pumpSettings(tester);

    expect(service.settings.fontSize, FontSizeOption.medium);

    // The selector uses the app's segmented-track radio design.
    expect(find.byKey(const Key('segment-highlight')), findsOneWidget);

    await tester.ensureVisible(find.text('Large'));
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    expect(service.settings.fontSize, FontSizeOption.large);
  });

  testWidgets('edit defaults opens the search sheet and persists the result', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Edit defaults'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchOptionsSheet), findsOneWidget);

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

  testWidgets('dismissing the defaults sheet without saving still persists', (tester) async {
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

    expect(find.byType(SearchOptionsSheet), findsNothing);
    expect(service.settings.defaultQuery.category, SearchCategory.comics);
  });

  group('alerts pop-up preference tile', () {
    const tileTitle = 'Alerts pop-up skips mark read';
    late AuthService previousAuth;

    setUp(() async {
      previousAuth = AuthService.instance;
      AuthService.instance = AuthService(InMemoryCookieStorage());
      await AuthService.instance.saveCookies({'xf_user': '123,token'});
    });

    tearDown(() {
      AuthService.instance = previousAuth;
    });

    Future<void> pumpTile(WidgetTester tester, {required AlertPrefsLoader loader, required AlertPrefsSaver saver}) {
      return tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: SettingsScreen(alertPrefsLoader: loader, alertPrefsSaver: saver),
        ),
      );
    }

    testWidgets('hidden while logged out', (tester) async {
      await AuthService.instance.logout();
      await pumpSettings(tester);
      expect(find.text(tileTitle), findsNothing);
    });

    testWidgets('loads the account value and saves a toggle to the site', (tester) async {
      final saved = <bool>[];
      await pumpTile(
        tester,
        loader: () async => const AlertPreferences(popupSkipsMarkRead: true),
        saver: (value) async => saved.add(value),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.widgetWithText(SwitchListTile, tileTitle);
      await tester.scrollUntilVisible(tileFinder, 200);
      expect(tester.widget<SwitchListTile>(tileFinder).value, isTrue);

      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      expect(saved, [false]);
      expect(tester.widget<SwitchListTile>(tileFinder).value, isFalse);
    });

    testWidgets('a failed save reverts the switch', (tester) async {
      await pumpTile(
        tester,
        loader: () async => const AlertPreferences(popupSkipsMarkRead: false),
        saver: (value) async => throw Exception('offline'),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.widgetWithText(SwitchListTile, tileTitle);
      await tester.scrollUntilVisible(tileFinder, 200);
      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tileFinder).value, isFalse);
    });

    testWidgets('the switch stays disabled when the account load fails', (tester) async {
      await pumpTile(
        tester,
        loader: () async => throw Exception('offline'),
        saver: (value) async {},
      );
      await tester.pumpAndSettle();

      final tileFinder = find.widgetWithText(SwitchListTile, tileTitle);
      await tester.scrollUntilVisible(tileFinder, 200);
      expect(tester.widget<SwitchListTile>(tileFinder).onChanged, isNull);
    });
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
