import 'package:f95_portal/widgets/version_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The decorated container of the version segment (the one showing the
  /// version text).
  BoxDecoration versionDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('v1.0'), matching: find.byType(Container)).first,
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('version segment border matches its fill color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: VersionPill(version: 'v1.0', isCompleted: false)),
      ),
    );

    final decoration = versionDecoration(tester);
    expect((decoration.border! as Border).top.color, decoration.color);
  });

  testWidgets('version segment border matches its fill alongside a status badge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: VersionPill(version: 'v1.0', isCompleted: true)),
      ),
    );

    expect(find.byIcon(Icons.task_alt), findsOneWidget);
    final decoration = versionDecoration(tester);
    expect((decoration.border! as Border).top.color, decoration.color);
  });
}
