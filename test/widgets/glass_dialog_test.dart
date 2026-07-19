import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/glass_dialog.dart';

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

  Future<void> pumpDialog(WidgetTester tester, {List<Widget> actions = const []}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    GlassDialog(title: const Text('Go to page'), content: const Text('body'), actions: actions),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('blurs its own panel when glass effects are on', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: true));
    await pumpDialog(tester);

    expect(find.byType(BackdropFilter), findsOneWidget);

    // The blur must cover the dialog panel only. Wrapping an AlertDialog from
    // the outside instead would size the filter to the whole route and smear
    // the entire screen behind the barrier.
    final blurSize = tester.getSize(find.byType(BackdropFilter));
    expect(blurSize.height, lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio));

    // No PhysicalShape may sit above the filter. That is what Material's
    // card/canvas/button types render as, and it is a compositing boundary:
    // the filter would sample that empty layer rather than the page, leaving
    // the panel flat with no visible blur. This is why Dialog is not used.
    expect(find.ancestor(of: find.byType(BackdropFilter), matching: find.byType(PhysicalShape)), findsNothing);
  });

  testWidgets('gives its content a Material ancestor for fields and buttons', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: true));

    // A TextField asserts on a missing Material ancestor; dropping Dialog
    // removed the one that used to come for free.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const GlassDialog(content: TextField()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('skips the blur for a near-opaque fill when glass effects are off', (tester) async {
    await service.update(service.settings.copyWith(glassEffects: false));
    await pumpDialog(tester);

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('takes its title and content styling from the ambient DialogTheme', (tester) async {
    // GlassDialog cannot build on Dialog, so it has to read DialogTheme by
    // hand; if it stops, the call sites silently lose their styling.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          dialogTheme: const DialogThemeData(
            titleTextStyle: TextStyle(color: Color(0xFF00FF00), fontSize: 21),
            contentTextStyle: TextStyle(color: Color(0xFF0000FF), fontSize: 9),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const GlassDialog(title: Text('title'), content: Text('body')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final titleStyle = DefaultTextStyle.of(tester.element(find.text('title'))).style;
    expect(titleStyle.color, const Color(0xFF00FF00));
    expect(titleStyle.fontSize, 21);

    final contentStyle = DefaultTextStyle.of(tester.element(find.text('body'))).style;
    expect(contentStyle.color, const Color(0xFF0000FF));
    expect(contentStyle.fontSize, 9);
  });

  testWidgets('renders title, content, and actions', (tester) async {
    await pumpDialog(
      tester,
      actions: [TextButton(onPressed: () {}, child: const Text('Cancel'))],
    );

    expect(find.text('Go to page'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
