import 'package:f95_portal/widgets/sliding_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpReveal(WidgetTester tester, {required bool visible, Widget? child}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlidingReveal(visible: visible, child: child),
        ),
      ),
    );
  }

  testWidgets('mounts the child while visible and drops it after sliding shut', (tester) async {
    await pumpReveal(tester, visible: false, child: const Text('content'));
    expect(find.text('content'), findsNothing);

    await pumpReveal(tester, visible: true, child: const Text('content'));
    expect(find.text('content'), findsOneWidget);
    await tester.pumpAndSettle();

    await pumpReveal(tester, visible: false, child: const Text('content'));
    await tester.pump();
    // Still mounted mid-slide...
    expect(find.text('content'), findsOneWidget);
    await tester.pumpAndSettle();
    // ...gone once the slide-shut settles.
    expect(find.text('content'), findsNothing);
  });

  testWidgets('retains the last child through the slide-shut when the child is withheld', (tester) async {
    // Derived-visibility callers (the suggestion dropdown) pass null while
    // hidden; the previous child must still slide shut.
    await pumpReveal(tester, visible: true, child: const Text('list'));
    await tester.pumpAndSettle();

    await pumpReveal(tester, visible: false, child: null);
    await tester.pump();
    expect(find.text('list'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('list'), findsNothing);
  });

  testWidgets('re-opening mid-slide keeps the child mounted', (tester) async {
    await pumpReveal(tester, visible: true, child: const Text('content'));
    await tester.pumpAndSettle();

    await pumpReveal(tester, visible: false, child: const Text('content'));
    await tester.pump(const Duration(milliseconds: 60));
    await pumpReveal(tester, visible: true, child: const Text('content'));
    await tester.pumpAndSettle();

    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('slides over the shared motion duration', (tester) async {
    await pumpReveal(tester, visible: true, child: const Text('content'));

    final align = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
    expect(align.duration, Motion.duration);
    expect(Motion.duration, greaterThan(Duration.zero));
  });
}
