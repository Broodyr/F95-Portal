import 'package:f95_portal/widgets/reaction_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBadge(WidgetTester tester, int reactionId) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: ReactionBadge(reactionId: reactionId)))),
    );
  }

  String? badgeGlyph(WidgetTester tester) => tester.widget<Text>(find.byType(Text)).data;

  testWidgets('reactions render as emoji text, never IconData', (tester) async {
    await pumpBadge(tester, 14); // Heart
    // The point of the emoji migration: no icon-font glyphs (which rendered
    // blank/tofu on some devices) — every badge is a non-empty emoji string.
    expect(find.byType(Icon), findsNothing);
    expect(badgeGlyph(tester) ?? '', isNotEmpty);
  });

  testWidgets('distinct reaction ids map to distinct glyphs', (tester) async {
    await pumpBadge(tester, 8); // Angry
    final angry = badgeGlyph(tester);
    await pumpBadge(tester, 1); // Like
    final like = badgeGlyph(tester);
    expect(angry, isNotEmpty);
    expect(like, isNot(angry));
  });

  testWidgets('unknown reaction ids fall back to a neutral glyph', (tester) async {
    await pumpBadge(tester, 999);
    expect(find.text('\u{2753}'), findsOneWidget);
  });
}
