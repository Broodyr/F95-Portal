import 'package:f95_portal/widgets/reaction_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  Future<void> pumpBadge(WidgetTester tester, int reactionId) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: ReactionBadge(reactionId: reactionId)))),
    );
  }

  testWidgets('icon reactions render a Material Symbols Icon, not text', (tester) async {
    await pumpBadge(tester, 1); // Like
    expect(find.byIcon(Symbols.thumb_up), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('emoji reactions render as text so the icon font stays subsettable', (tester) async {
    await pumpBadge(tester, 4); // Wow → 😮
    // No IconData carries the emoji codepoint (that would break release
    // icon tree-shaking); it renders as a plain emoji string instead.
    expect(find.byType(Icon), findsNothing);
    expect(find.text('\u{1F62E}'), findsOneWidget);
  });

  testWidgets('unknown reaction ids fall back to an icon', (tester) async {
    await pumpBadge(tester, 999);
    expect(find.byIcon(Symbols.add_reaction), findsOneWidget);
  });
}
