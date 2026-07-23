import 'package:f95_portal/widgets/bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(ScrollController controller, double width, {void Function(int)? onTap, int currentIndex = 0}) =>
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: CustomBottomNavigation(
                currentIndex: currentIndex,
                onTap: onTap ?? (_) {},
                scrollController: controller,
              ),
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

  testWidgets('one shared highlight slides to the selected destination', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final highlight = find.byKey(const Key('nav-highlight'));

    await tester.pumpWidget(host(controller, 375));
    expect(highlight, findsOneWidget);
    expect(tester.widget<AnimatedAlign>(highlight).alignment, const Alignment(-1, 0));

    // Selecting the last tab re-aligns the same highlight rather than
    // lighting up a second one.
    await tester.pumpWidget(host(controller, 375, currentIndex: 3));
    await tester.pumpAndSettle();
    expect(highlight, findsOneWidget);
    expect(tester.widget<AnimatedAlign>(highlight).alignment, const Alignment(1, 0));
  });

  // The 8-bit alpha of the highlight circle's fill, as actually rasterised.
  int highlightAlpha(WidgetTester tester) {
    final circle = find.descendant(of: find.byKey(const Key('nav-highlight')), matching: find.byType(Container));
    final decoration = tester.widget<Container>(circle).decoration! as BoxDecoration;
    return (decoration.color!.a * 255).round();
  }

  // _PulsingHighlightState.restAlpha, which the pulse starts and ends at.
  const restAlpha = 64; // (0.25 * 255).round()

  testWidgets('the pulse never holds one colour long enough to look choppy', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller, 375));
    await tester.pumpWidget(host(controller, 375, currentIndex: 1));

    // Alpha rasterises to 8 bits, so a pulse can only render
    // `(peak - rest) * 255` distinct fills however smooth its curve is. Once
    // that budget runs short the circle holds the same colour across several
    // frames, which is what reads as a stuttering framerate. Sample the sweep
    // at 60Hz and measure that hold directly: the original 0.2..0.3 swing sat
    // on one colour for 10 straight frames (167ms).
    // Bounded to the beat itself; sampling past it would measure the settled
    // highlight sitting still, which is correct rather than choppy.
    final alphas = <int>[];
    for (var elapsed = 0; elapsed <= 600; elapsed += 16) {
      alphas.add(highlightAlpha(tester));
      await tester.pump(const Duration(milliseconds: 16));
    }

    var longestHold = 1;
    var hold = 1;
    for (var i = 1; i < alphas.length; i++) {
      hold = alphas[i] == alphas[i - 1] ? hold + 1 : 1;
      longestHold = hold > longestHold ? hold : longestHold;
    }

    // Currently 2, and only where the raised cosine flattens at a beat's
    // peak or trough; every other frame gets a colour of its own.
    expect(longestHold, lessThanOrEqualTo(3), reason: 'pulse is banding across frames');
  });

  testWidgets('the pulse settles rather than animating forever', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller, 375));
    expect(highlightAlpha(tester), restAlpha, reason: 'should not flourish on launch');

    await tester.pumpWidget(host(controller, 375, currentIndex: 1));
    // 300ms is the crest of the beat; by 600ms it has settled back to rest.
    await tester.pump(const Duration(milliseconds: 300));
    expect(highlightAlpha(tester), greaterThan(restAlpha), reason: 'a tap should flourish');

    // Nothing else in the app animates perpetually, so this settling is what
    // lets the engine stop producing frames — and stop re-rasterising the
    // nav bar's backdrop blur. Against the old repeat() this timed out.
    await tester.pumpAndSettle();
    expect(highlightAlpha(tester), restAlpha);
  });

  testWidgets('reduced motion leaves the highlight at rest', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller, 375));
    await tester.pumpWidget(host(controller, 375, currentIndex: 1));

    // A reduced-motion controller runs at 5% duration rather than stopping,
    // so leaning on that alone would flash both beats across ~7 frames.
    // The pulse has to be skipped outright.
    for (var elapsed = 0; elapsed <= 1200; elapsed += 16) {
      expect(highlightAlpha(tester), restAlpha);
      await tester.pump(const Duration(milliseconds: 16));
    }
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
