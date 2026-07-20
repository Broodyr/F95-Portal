import 'package:f95_portal/widgets/forum_node_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ForumNodeRow.iconFor', () {
    test('gives every directory forum its own glyph, bar the generic one', () {
      // Every non-link node the index fixture yields, in page order.
      const directory = [
        'Site Rules, News & Announcements',
        'Contests',
        'Games',
        'Game Requests',
        'Mods',
        'Comics & Stills',
        'Animations & Loops',
        'Comic & Animation Requests',
        'Asset Releases',
        'Asset Requests',
        'Programming, Development & Art',
        'Recruitment & Services',
        'Translation',
        'Cracking',
        'General Discussions',
        'Tools & Tutorials',
        'General Troubleshooting',
        'Features Request',
        'Site Problems',
      ];

      final byIcon = <IconData, List<String>>{};
      for (final title in directory) {
        byIcon.putIfAbsent(ForumNodeRow.iconFor(title), () => []).add(title);
      }

      // The three request forums deliberately share one glyph; nothing else
      // may collide, and only General Discussions falls back to generic.
      expect(byIcon[Icons.add_circle_outline], [
        'Game Requests',
        'Comic & Animation Requests',
        'Asset Requests',
        'Features Request',
      ]);
      expect(byIcon[Icons.forum_outlined], ['General Discussions']);
      expect(byIcon.entries.where((e) => e.value.length > 1 && e.key != Icons.add_circle_outline), isEmpty);
    });

    test('separates a subforum block by status, not by its shared topic', () {
      // Siblings under Features Request, then under Game Requests.
      expect(ForumNodeRow.iconFor('Completed Features'), Icons.check_circle_outline);
      expect(ForumNodeRow.iconFor('Planned Features'), Icons.schedule);
      expect(ForumNodeRow.iconFor('Rejected Features'), Icons.cancel_outlined);
      expect(ForumNodeRow.iconFor('Completed Game Requests'), Icons.check_circle_outline);
      expect(ForumNodeRow.iconFor('Rejected Game Requests'), Icons.cancel_outlined);
      expect(ForumNodeRow.iconFor('Solved'), Icons.check_circle_outline);
    });

    test('reads a topic word ahead of a looser one it contains', () {
      // 'art' is a substring of "… & Art" and "Artwork"; 'mod' of
      // "Translations Mods".
      expect(ForumNodeRow.iconFor('Programming, Development & Art'), Icons.code);
      expect(ForumNodeRow.iconFor('Artwork'), Icons.palette_outlined);
      expect(ForumNodeRow.iconFor('Asset Releases'), Icons.layers_outlined);
      expect(ForumNodeRow.iconFor('Translations Mods'), Icons.translate);
      expect(ForumNodeRow.iconFor('Mods'), Icons.build_outlined);
      expect(ForumNodeRow.iconFor('Dev Tools & Guides'), Icons.handyman_outlined);
      expect(ForumNodeRow.iconFor('Dev Help'), Icons.help_outline);
    });

    test('falls back to the generic forum glyph', () {
      expect(ForumNodeRow.iconFor('Some Forum Nobody Predicted'), Icons.forum_outlined);
    });
  });
}
