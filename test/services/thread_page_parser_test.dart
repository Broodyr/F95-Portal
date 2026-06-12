import 'dart:io';

import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/services/thread_page_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadPage parseFixture(String name) => parseThreadPage(File('test/fixtures/$name').readAsStringSync(), threadId: 1);

List<DownloadGroup> allGroups(ThreadPage page) => [for (final set in page.downloads!.sets) ...set.groups];

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

    test('groups downloads per platform in a single untitled set', () {
      final sets = page.downloads!.sets;
      expect(sets, hasLength(1));
      expect(sets.single.title, isNull);
      expect([for (final g in sets.single.groups) g.label], ['Win', 'Linux', 'Mac']);
      final winHosts = [for (final l in sets.single.groups.first.links) l.host];
      expect(winHosts, contains('PIXELDRAIN'));
    });

    test('collects labeled extras but not gallery or credit links', () {
      final extras = page.downloads!.extras;
      expect(extras, hasLength(1));
      expect(extras.single.label, 'Extras');
      expect(extras.single.links.single.host, 'Blender Files for Animation');
    });

    test('caps runaway spoiler content', () {
      final changelog = page.spoilers.firstWhere((s) => s.title == 'Changelog');
      expect(changelog.content.length, lessThanOrEqualTo(8200));
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
      expect([for (final g in allGroups(page)) g.label], ['Win', 'Linux', 'Mac', 'Android']);
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
      expect(allGroups(page).single.label, 'Win');
      expect(page.downloads!.extras, isEmpty);
    });
  });

  group('parseThreadPage on Bubbles and Babes (alternate version set)', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_renpy_bubbles.htm'));

    test('splits the downloads into a main and a titled alternate set', () {
      final sets = page.downloads!.sets;
      expect(sets.length, greaterThanOrEqualTo(2));
      expect(sets[0].title, isNull);
      expect([for (final g in sets[0].groups) g.label], ['Win/Linux', 'Mac', 'Android']);
      expect(sets[1].title, 'Incest Version (v0.15)');
      expect([for (final g in sets[1].groups) g.label.split(' ').first], contains('Win/Linux'));
    });

    test('developer meta falls back to the first link label only', () {
      expect(page.metaValue('Developer'), 'Bubbles and Sisters');
    });

    test('developer notes spoiler carries inline images', () {
      final notes = page.spoilers.firstWhere((s) => s.title == 'Developer Notes');
      expect(notes.rich.any((p) => p.imageUrl != null), isTrue);
    });
  });

  group('parseThreadPage on Elasid (animation collection, non-bold labels)', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_anim_elasid.htm'));

    test('plain-text "Label:" lines become download groups, not extras', () {
      final labels = [for (final g in allGroups(page)) g.label];
      expect(labels.first, 'Collection');
      expect(labels, contains("Rachnera's Reprise"));
      expect(page.downloads!.extras, isEmpty);
    });
  });

  group('parseThreadPage on Doberman (torrent + attachment)', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_anim_doberman.htm'));

    test('standalone torrent link becomes a download group', () {
      final torrent = allGroups(page).firstWhere((g) => g.label == 'Torrent');
      expect(torrent.links.single.url, contains('.torrent'));
    });

    test('magnet hash spoiler is preserved', () {
      final magnet = page.spoilers.firstWhere((s) => s.title == 'magnet hash');
      expect(magnet.content, matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    test('first-post attachments are collected', () {
      expect(page.attachments, hasLength(1));
      expect(page.attachments.single.host, contains('.torrent'));
      expect(page.attachments.single.url, startsWith('https://attachments.f95zone.to/'));
    });
  });

  group('parseThreadPage on the Blender asset (no platform labels)', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_asset_blender_ela.htm'));

    test('bare host rows become a Links group instead of vanishing', () {
      final group = allGroups(page).single;
      expect(group.label, 'Links');
      expect([for (final l in group.links) l.host], contains('MEGA'));
      expect(page.downloads!.extras, isEmpty);
    });

    test('overview without a colon still parses', () {
      expect(page.overview, contains('3D Blender Model of Ela Bosak'));
    });
  });

  group('parseThreadPage on Something Unlimited (spoilered demo, big extras)', () {
    late ThreadPage page;

    setUpAll(() => page = parseFixture('thread_unity_something_unlimited.htm'));

    test('platform groups unaffected by spoilered demo downloads', () {
      expect([for (final g in allGroups(page)) g.label], ['Win', 'Mac', 'Android']);
    });

    test('extras keep their full host list', () {
      final extras = page.downloads!.extras.single;
      expect(extras.links.length, greaterThan(10));
    });

    test('spoilers carry tappable links in their rich content', () {
      final android = page.spoilers.firstWhere((s) => s.title == 'Something Unlimited Android');
      expect(android.rich.any((p) => p.url != null), isTrue);
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
      expect(page.attachments, isEmpty);
    });
  });
}
