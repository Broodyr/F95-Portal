import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:f95_portal/widgets/metadata_row.dart';

import '../helpers/widget_test_utils.dart';

void main() {
  testWidgets('displays formatted metadata values', (tester) async {
    await pumpTestApp(tester, const MetadataRow(timeUpdated: '3 days', likes: 1520, views: 2700000, rating: 4.25));

    await tester.pump();

    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('1.5K'), findsOneWidget);
    expect(find.text('2.7M'), findsOneWidget);
    expect(find.byIcon(Icons.access_time), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('shows the score at the right end of the row', (tester) async {
    await pumpTestApp(tester, const MetadataRow(timeUpdated: '3 days', likes: 1520, views: 2700000, rating: 4.25));

    await tester.pump();

    expect(find.text('4.3'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
    // Right-aligned: the score sits after the views value.
    expect(tester.getTopLeft(find.text('4.3')).dx, greaterThan(tester.getTopRight(find.text('2.7M')).dx));
  });

  testWidgets('shows a placeholder for unrated threads', (tester) async {
    await pumpTestApp(tester, const MetadataRow(timeUpdated: '3 days', likes: 1520, views: 2700000, rating: 0.0));

    await tester.pump();

    expect(find.text('—'), findsOneWidget);
  });
}
