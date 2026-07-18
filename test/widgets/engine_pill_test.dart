import 'package:f95_portal/widgets/engine_pill.dart';
import 'package:f95_portal/widgets/segmented_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Corner rounding and segment painting belong to [SegmentedPill] and are
/// covered in its own test; this file covers the engine-specific rules.
void main() {
  Future<void> pumpEnginePill(WidgetTester tester, List<String> engines) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EnginePill(engines: engines)),
      ),
    );
  }

  Finder segments() => find.descendant(of: find.byType(SegmentedPill), matching: find.byType(Container));

  testWidgets('no engines renders nothing', (tester) async {
    await pumpEnginePill(tester, []);

    expect(find.byType(SegmentedPill), findsNothing);
  });

  testWidgets('every engine gets a segment, in order', (tester) async {
    await pumpEnginePill(tester, ['Godot', 'HTML', 'Java']);

    expect(segments(), findsNWidgets(3));
    expect(find.text('Godot'), findsOneWidget);
    expect(find.text('HTML'), findsOneWidget);
    expect(find.text('Java'), findsOneWidget);
  });

  testWidgets('each engine is colored by its own engine color', (tester) async {
    await pumpEnginePill(tester, ['Godot', 'HTML']);

    final decorations = tester.widgetList<Container>(segments()).map((c) => c.decoration! as BoxDecoration);
    expect(decorations.map((d) => d.color).toSet(), hasLength(2));
  });

  testWidgets("'Others' drops out when a real engine is present", (tester) async {
    await pumpEnginePill(tester, ['Others', 'Godot']);

    expect(find.text('Others'), findsNothing);
    expect(segments(), findsOneWidget);
  });

  testWidgets("'Others' alone still renders", (tester) async {
    await pumpEnginePill(tester, ['Others']);

    expect(find.text('Others'), findsOneWidget);
  });
}
