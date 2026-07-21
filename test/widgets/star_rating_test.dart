import 'package:f95_portal/widgets/star_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, double rating) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: StarBar(rating: rating)),
    ),
  );

  (int, int, int) counts(WidgetTester tester) => (
    tester.widgetList(find.byIcon(Icons.star)).length,
    tester.widgetList(find.byIcon(Icons.star_half)).length,
    tester.widgetList(find.byIcon(Icons.star_border)).length,
  );

  testWidgets('a fractional score rounds to the nearest half-mark', (tester) async {
    await pump(tester, 4.7);
    expect(counts(tester), (4, 1, 0));

    await pump(tester, 3.7);
    expect(counts(tester), (3, 1, 1));

    await pump(tester, 4.2);
    expect(counts(tester), (4, 0, 1));
  });

  testWidgets('whole scores show no half star', (tester) async {
    await pump(tester, 5.0);
    expect(counts(tester), (5, 0, 0));

    await pump(tester, 1.0);
    expect(counts(tester), (1, 0, 4));
  });

  testWidgets('an unrated bar is five empty stars', (tester) async {
    await pump(tester, 0);
    expect(counts(tester), (0, 0, 5));
  });
}
