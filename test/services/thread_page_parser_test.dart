import 'dart:io';

import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/services/thread_page_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadPage parseFixture(String name) =>
    parseThreadPage(File('test/fixtures/$name').readAsStringSync(), threadId: 1);

void main() {
  group('parseThreadPage on In Heat (Unity, multi-platform)', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_unity_in_heat.htm'));

    test('extracts the template meta fields', () {
      expect(page.metaValue('Developer'), 'MonsterBox');
      expect(page.metaValue('Version'), '0.4.1.3');
      expect(page.metaValue('Censored'), 'No');
      expect(page.metaValue('OS'), 'Windows, Linux, Mac');
    });

    test('captures the overview text', () {
      expect(page.overview, contains('You thought it was a miracle'));
    });

    test('keeps known and one-off spoiler sections in order', () {
      final titles = [for (final s in page.spoilers) s.title];
      expect(titles, containsAllInOrder(['Genre', 'Installation', 'Changelog', 'Developer Notes', 'Old Builds']));
    });

    test('groups downloads per platform with host links', () {
      final platforms = page.downloads!.platforms;
      expect([for (final g in platforms) g.label], ['Win', 'Linux', 'Mac']);
      final winHosts = [for (final l in platforms.first.links) l.host];
      expect(winHosts, contains('PIXELDRAIN'));
      expect(platforms.first.links.every((l) => l.url.startsWith('http')), isTrue);
    });

    test('collects labeled extras but not gallery or credit links', () {
      final extras = page.downloads!.extras;
      expect(extras, hasLength(1));
      expect(extras.single.label, 'Extras');
      expect(extras.single.links.single.host, 'Blender Files for Animation');
    });

    test('caps runaway spoiler content', () {
      final changelog = page.spoilers.firstWhere((s) => s.title == 'Changelog');
      expect(changelog.content.length, lessThanOrEqualTo(8001));
    });
  });

  group('parseThreadPage on Futakin Valley (bold-wrapped overview)', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_unity_futakin_valley.htm'));

    test('bold emphasis inside the overview does not truncate it', () {
      expect(page.overview, startsWith('Futaken Valley is an action platformer-type game.'));
    });

    test('meta values drop the link separators', () {
      expect(page.metaValue('Developer'), 'Mofuland');
    });

    test('one-off spoiler titles survive', () {
      final titles = [for (final s in page.spoilers) s.title];
      expect(titles, contains('Keyboard operation'));
    });

    test('all four platforms found', () {
      expect([for (final g in page.downloads!.platforms) g.label], ['Win', 'Linux', 'Mac', 'Android']);
    });
  });

  group('parseThreadPage on the RPGM completed thread', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_rpgm_completed.htm'));

    test('handles non-ASCII meta values', () {
      expect(page.metaValue('Original Title'), 'フタナリ忍堕落観察');
      expect(page.metaValue('Developer'), 'Food Adherent');
    });

    test('single platform, no extras', () {
      expect(page.downloads!.platforms.single.label, 'Win');
      expect(page.downloads!.extras, isEmpty);
    });
  });

  group('parseThreadPage degradation', () {
    test('returns an empty page for unrecognizable HTML', () {
      final page = parseThreadPage('<html><body><p>nothing here</p></body></html>', threadId: 7);

      expect(page.threadId, 7);
      expect(page.metaFields, isEmpty);
      expect(page.overview, isEmpty);
      expect(page.spoilers, isEmpty);
      expect(page.downloads, isNull);
    });
  });
}
