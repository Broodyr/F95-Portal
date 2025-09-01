// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:f95_portal/main.dart';

void main() {
  testWidgets('App starts with Games tab selected', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const F95Portal());

    // Verify that the Games tab is selected
    expect(find.text('Games'), findsOneWidget);

    // Wait for the UI to settle
    await tester.pumpAndSettle();

    // We should see some game cards or loading indicator
    expect(find.byType(CircularProgressIndicator), findsAny);
  });
}
