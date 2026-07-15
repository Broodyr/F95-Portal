import 'package:f95_portal/widgets/bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(ScrollController controller, double width, {void Function(int)? onTap}) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: CustomBottomNavigation(currentIndex: 0, onTap: onTap ?? (_) {}, scrollController: controller),
        ),
      ),
    ),
  );

  testWidgets('renders all four destinations at phone width', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller, 375));

    expect(find.byIcon(Icons.explore), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('tapping a destination reports its index', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final taps = <int>[];

    await tester.pumpWidget(host(controller, 375, onTap: taps.add));
    await tester.tap(find.byIcon(Icons.person_outline));

    expect(taps, [3]);
  });

  testWidgets('a tiny first-frame width lays out without overflow errors', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    // The web build's first frame can measure a sliver of the real window
    // width before it settles (a ~110px window leaves the row ~46px, the
    // constraint from the live repro); the bar must not spam overflow errors.
    await tester.pumpWidget(host(controller, 110));
    expect(tester.takeException(), isNull);

    // Once the real width arrives the items appear as usual.
    await tester.pumpWidget(host(controller, 375));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.explore), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });
}
