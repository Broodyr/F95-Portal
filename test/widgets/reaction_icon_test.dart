import 'dart:io';

import 'package:f95_portal/widgets/reaction_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  Future<void> pumpBadge(WidgetTester tester, int reactionId) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ReactionBadge(reactionId: reactionId)),
        ),
      ),
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

  test('the picker offers reactions in the order the site lists them', () {
    // The site builds its picker from this server-rendered template. It
    // being a <script> makes its markup text to the parser, so it needs a
    // second parse to walk.
    final page = html_parser.parse(File('test/fixtures/thread_renpy_being_a_dik.htm').readAsStringSync());
    final template = page.querySelector('#xfReactTooltipTemplate');
    expect(template, isNotNull, reason: 'the fixture no longer carries the picker template');

    final siteOrder = [
      for (final anchor in html_parser.parse(template!.text).querySelectorAll('a.reaction'))
        int.parse(anchor.attributes['data-reaction-id']!),
    ];
    // Sanity: the fixture really does disagree with an id-sorted list, so
    // this test would have failed before the reorder rather than passing by
    // coincidence.
    expect(siteOrder, isNot(orderedEquals([...siteOrder]..sort())));

    // 15 and 17 are in the template but not offered, so they drop out
    // rather than being asserted absent from a hardcoded list.
    expect(ReactionGlyph.all.keys, orderedEquals(siteOrder.where(ReactionGlyph.all.containsKey)));
  });
}
