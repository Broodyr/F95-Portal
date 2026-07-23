import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/app_action_sheet.dart';

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

  /// Pumps a screen whose one button opens the sheet with [actions], then taps
  /// it open.
  Future<void> pumpSheet(WidgetTester tester, List<AppSheetAction> actions) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppActionSheet(context, actions: actions),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a row per action with its glyph and label', (tester) async {
    await pumpSheet(tester, [
      AppSheetAction(icon: Icons.search, label: 'Search thread', onTap: () {}),
      AppSheetAction(icon: Icons.open_in_browser, label: 'Open in browser', onTap: () {}),
    ]);

    expect(find.text('Search thread'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.open_in_browser), findsOneWidget);
  });

  testWidgets('runs the chosen action and dismisses the sheet', (tester) async {
    var ran = 0;
    await pumpSheet(tester, [
      AppSheetAction(icon: Icons.open_in_browser, label: 'Open in browser', onTap: () => ran++),
    ]);

    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(ran, 1);
    // The callback runs after the sheet is gone, so it is free to push a route
    // or open its own sheet without racing this one's dismissal.
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('dismissing without a choice runs nothing', (tester) async {
    var ran = 0;
    await pumpSheet(tester, [
      AppSheetAction(label: 'Report…', onTap: () => ran++),
    ]);

    // Tap the barrier above the sheet.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(ran, 0);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('an icon-less action shows no leading glyph', (tester) async {
    await pumpSheet(tester, [
      AppSheetAction(label: 'Report…', onTap: () {}),
    ]);

    // The grabber is a Container, not an Icon, so the sheet holds none.
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Icon)), findsNothing);
  });

  testWidgets('a destructive row wears the theme error accent', (tester) async {
    await pumpSheet(tester, [
      AppSheetAction(icon: Icons.delete_outline, label: 'Delete', destructive: true, onTap: () {}),
      AppSheetAction(icon: Icons.outlined_flag, label: 'Report…', onTap: () {}),
    ]);

    final error = ThemeData.dark().colorScheme.error;
    expect(tester.widget<Text>(find.text('Delete')).style?.color, error);
    // A plain row does not borrow the accent.
    expect(tester.widget<Text>(find.text('Report…')).style?.color, isNot(error));
  });

  testWidgets('an anchored sheet lights its trigger through the shade and clears it on close', (tester) async {
    var ran = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppActionSheet(
                  context,
                  anchorRect: menuAnchorRect(context),
                  actions: [AppSheetAction(label: 'Report…', onTap: () => ran++)],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    // No highlight before the menu opens.
    expect(find.byKey(const Key('menu-highlight')), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-highlight')), findsOneWidget);

    await tester.tap(find.text('Report…'));
    await tester.pumpAndSettle();

    expect(ran, 1);
    // The scrim is torn down with the sheet, leaving nothing behind.
    expect(find.byKey(const Key('menu-highlight')), findsNothing);
  });

  testWidgets('a sheet without an anchor draws no highlight', (tester) async {
    await pumpSheet(tester, [
      AppSheetAction(label: 'Report…', onTap: () {}),
    ]);

    expect(find.byKey(const Key('menu-highlight')), findsNothing);
  });

  testWidgets('blurs the sheet when glass effects are on, and skips it when off', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: true));
    await pumpSheet(tester, [
      AppSheetAction(label: 'Report…', onTap: () {}),
    ]);
    expect(find.byType(BackdropFilter), findsOneWidget);

    // Close and reopen with glass off.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    await service.update(service.settings.copyWith(glassEffects: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
