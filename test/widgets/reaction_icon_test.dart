import 'package:f95_portal/widgets/reaction_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBadge(WidgetTester tester, int reactionId) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: ReactionBadge(reactionId: reactionId)))),
    );
  }

  testWidgets('reactions render as emoji text, never IconData', (tester) async {
    await pumpBadge(tester, 14); // Heart (f95 reaction id 14)
    // Emoji (not icon fonts) so nothing depends on Material Symbols glyphs,
    // which Impeller blanks selectively on some devices. Single emoji-default
    // codepoints only — no VS16 sequences, which Impeller also mishandles.
    expect(find.byType(Icon), findsNothing);
    expect(find.text('\u{1F496}'), findsOneWidget);
  });

  testWidgets('a known id maps to its emoji', (tester) async {
    await pumpBadge(tester, 8); // Angry
    expect(find.text('\u{1F620}'), findsOneWidget);
  });

  testWidgets('unknown reaction ids fall back to a neutral glyph', (tester) async {
    await pumpBadge(tester, 999);
    expect(find.text('\u{2753}'), findsOneWidget);
  });
}
