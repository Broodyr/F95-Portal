import 'dart:io';

import 'package:f95_portal/models/account.dart';
import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/services/forum_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('parseForumIndex', () {
    late ForumIndex index;

    setUpAll(() => index = parseForumIndex(fixture('forum_home.htm')));

    test('finds every category in order', () {
      expect(index.categories.map((c) => c.title).toList(), [
        'Announcements',
        'Private Forums',
        'Adult Games',
        'Adult Comics & Animations',
        'Development',
        'Discussion',
        'Site Feedback',
      ]);
    });

    test('parses forum nodes with id, url, and unread state', () {
      final first = index.categories.first.forums.first;
      expect(first.id, 19);
      expect(first.title, 'Site Rules, News & Announcements');
      expect(first.url, 'https://f95zone.to/forums/site-rules-news-announcements.19/');
      expect(first.unread, isTrue);
    });

    test('captures inline subforum links under a node', () {
      final games = index.categories.expand((c) => c.forums).firstWhere((f) => f.id == 2);
      expect(games.title, 'Games');
      final sub = games.subforums.firstWhere((s) => s.id == 114);
      expect(sub.title, 'Trending Games');
      expect(sub.isLink, isTrue);
    });
  });

  group('parseForumPage', () {
    late ForumPage page;

    setUpAll(() => page = parseForumPage(fixture('forum_gd.htm')));

    test('parses the forum title and pagination', () {
      expect(page.title, 'General Discussions');
      expect(page.currentPage, 1);
      expect(page.totalPages, 810);
    });

    test('parses the subforum block above the thread list', () {
      expect(page.subforums.map((s) => s.id).toList(), [11, 106, 104]);
      final intro = page.subforums.first;
      expect(intro.title, 'Introduction');
      expect(intro.description, 'Introduce yourself to the rest of the community');
      expect(intro.threads, '4K');
      expect(intro.messages, '19.6K');
      expect(intro.lastPost?.title, 'Hi everyone');
      expect(intro.lastPost?.username, 'Esssa47');
    });

    test('parses sticky rows with stats, dates, and last post', () {
      final row = page.threads.first;
      expect(row.threadId, 17387);
      expect(row.title, 'Post your signatures here');
      expect(row.url, 'https://f95zone.to/threads/post-your-signatures-here.17387/');
      expect(row.sticky, isTrue);
      expect(row.unread, isTrue);
      expect(row.author, 'TCMS');
      expect(row.authorAvatarUrl, endsWith('92_002.jpg'));
      expect(row.startDate, 'Aug 28, 2018');
      expect(row.replies, '4K');
      expect(row.views, '2M');
      expect(row.lastPostDate, 'Today at 4:32 PM');
      expect(row.lastPostUser, 'Asshole Admirer');
      expect(row.lastPage, 225);
    });

    test('parses title prefixes as labels', () {
      final row = page.threads.firstWhere((t) => t.threadId == 45990);
      expect(row.title, 'Bypassing ISP/Government blocking');
      expect(row.prefixes.single.id, 15);
      expect(row.prefixes.single.label, 'README');
    });

    test('keeps every row and marks non-stickies', () {
      expect(page.threads, hasLength(27));
      expect(page.threads.where((t) => t.sticky), hasLength(7));
      final regular = page.threads.firstWhere((t) => t.threadId == 188349);
      expect(regular.sticky, isFalse);
    });
  });

  group('parseThreadPosts', () {
    late ThreadPostsPage page;

    setUpAll(() => page = parseThreadPosts(fixture('thread_renpy_bubbles_page2.htm')));

    test('parses the title, pagination, and every post', () {
      expect(page.title, contains('Bubbles and Babes [v0.162]'));
      expect(page.currentPage, 2);
      expect(page.totalPages, 64);
      expect(page.posts, hasLength(20));
    });

    test('resolves the thread base URL from the canonical link', () {
      // Post-permalink fetches (/posts/N/) redirect to a thread page;
      // pagination must build on this URL, with the page suffix stripped.
      expect(page.threadUrl, 'https://f95zone.to/threads/bubbles-and-babes-v0-162-bubbles-and-babes.207754/');
    });

    test('parses post attribution', () {
      final post = page.posts.first;
      expect(post.postId, 13720617);
      expect(post.number, 21);
      expect(post.author, 'Lerd0');
      expect(post.memberTitle, 'Bussyloader');
      expect(post.date, 'May 12, 2024');
      expect(post.avatarUrl, endsWith('137028_002_iNbu.jpg'));
      expect(post.authorUrl, 'https://f95zone.to/members/lerd0.137028/');
    });

    test('splits the body into quote and rich blocks in order', () {
      final blocks = page.posts.first.blocks;
      expect(blocks.first.kind, PostBlockKind.quote);
      expect(blocks.first.label, 'Bubbles and Sisters');
      expect(blocks.first.pieces.map((p) => p.text).join(), contains("switching to real incest"));

      final rich = blocks[1];
      expect(rich.kind, PostBlockKind.rich);
      // The saved page embeds the full attachment; inline is downgraded to
      // the preview host with the full kept for the viewer.
      final image = rich.pieces.firstWhere(
        (p) => p.imageUrl == 'https://preview.f95zone.to/2024/05/3652583_1715545111474.png',
      );
      expect(image.fullImageUrl, 'https://attachments.f95zone.to/2024/05/3652583_1715545111474.png');
    });

    test('parses the thread watch endpoint and state', () {
      expect(page.watchUrl, 'https://f95zone.to/threads/bubbles-and-babes-v0-162-bubbles-and-babes.207754/watch');
      expect(page.watched, isFalse);
    });

    test('a watched thread reports its state from the Unwatch label', () {
      final watched = parseThreadPosts(fixture('thread_godot_beguiled.htm'));
      expect(watched.watchUrl, 'https://f95zone.to/threads/beguiled-v0-2-2-bad-bucket.297385/watch');
      expect(watched.watched, isTrue);
    });

    test('parses the reaction summary on the OP', () {
      final dik = parseThreadPosts(fixture('thread_renpy_being_a_dik.htm'));
      expect(dik.posts, hasLength(20));

      final op = dik.posts.first;
      expect(op.postId, 1565686);
      expect(op.number, 1);
      expect(op.author, 'N7');

      final reactions = op.reactions;
      expect(reactions, isNotNull);
      expect(reactions!.topReactionIds, [1, 14, 12]);
      expect(reactions.count, 12837);
      expect(reactions.url, 'https://f95zone.to/posts/1565686/reactions');
    });
  });

  group('parseBookmarks', () {
    late BookmarksPage page;

    setUpAll(() => page = parseBookmarks(fixture('account_bookmarks.htm')));

    test('parses every bookmark row with the page CSRF', () {
      expect(page.entries, hasLength(2));
      expect(page.csrfToken, isNotEmpty);
      expect(page.currentPage, 1);
      expect(page.totalPages, 1);
    });

    test('post bookmarks lift the inner title and carry the tools endpoint', () {
      final post = page.entries.first;
      expect(post.isPost, isTrue);
      expect(post.title, '[Secret Flasher Manaka] Custom Missions 1.2.1 & Version 2.2.1');
      expect(post.url, 'https://f95zone.to/posts/19803972/');
      expect(post.snippet, 'Manaka - Custom missions');
      expect(post.author, 'SekiYuri');
      expect(post.date, 'Apr 8, 2026');
      expect(post.bookmarkUrl, 'https://f95zone.to/posts/19803972/bookmark');
    });

    test('thread bookmarks resolve to the thread URL', () {
      final thread = page.entries[1];
      expect(thread.isPost, isFalse);
      expect(thread.title, 'Mousetrap: Theft & Bondage [v0.1.6p2] [Milkshake++]');
      expect(thread.url, 'https://f95zone.to/threads/mousetrap-theft-bondage-v0-1-6p2-milkshake.254486/');
      expect(thread.snippet, contains('Ratalie found herself'));
      expect(thread.author, 'Milkshake++');
      expect(thread.bookmarkUrl, 'https://f95zone.to/posts/16935508/bookmark');
    });
  });

  group('parseAlerts', () {
    late AlertsPage page;

    setUpAll(() => page = parseAlerts(fixture('account_alerts.htm')));

    test('groups alerts under their date headers', () {
      expect([for (final group in page.groups) group.title], ['Today', 'Yesterday', 'Friday']);
      expect(page.groups.fold<int>(0, (n, g) => n + g.alerts.length), 10);
      expect(page.currentPage, 1);
      expect(page.totalPages, 17);
      // Needed to POST the mark-read action.
      expect(page.csrfToken, '1783912232,9d248ff0e3701055def2de9cbe5e0dd0');
      // The nav bell counter: 0 in the fixture even though rows carry
      // unread stars — viewed and read are separate states.
      expect(page.badgeCount, 0);
    });

    test('the bell badge count comes from the nav data-badge', () {
      AlertsPage withBadge(String badge) => parseAlerts('''
        <a href="/account/alerts" class="p-navgroup-link js-badge--alerts badgeContainer" data-badge="$badge"></a>
        <ol class="listPlain"><li>
          <h2 class="block-formSectionHeader">Today</h2>
          <ol class="listPlain"><li data-alert-id="5" class="block-row">
            <div class="contentRow user-alert"><div class="contentRow-main">
              <a href="/members/a.9/" class="username">A</a> replied to
              <a href="/posts/8/" class="fauxBlockLink-blockLink">Hello</a>.
            </div></div>
          </li></ol>
        </li></ol>
      ''');

      expect(withBadge('4').badgeCount, 4);
      // f95 renders exact counts uncapped (the bookmarks fixture carries
      // data-badge="69"), but capped skin variants must still parse.
      expect(withBadge('137').badgeCount, 137);
      expect(withBadge('10+').badgeCount, 10);
    });

    test('parses actor, action, labels, bare title, and unread state', () {
      final first = page.groups.first.alerts.first;
      expect(first.alertId, 2047223592);
      expect(first.username, 'TMakuboss');
      expect(first.action, 'replied to the thread');
      expect(first.labels, ['Unity', 'Completed']);
      expect(first.title, "Mage Kanade's Futanari Dungeon Quest [Final] [Dieselmine]");
      expect(first.url, 'https://f95zone.to/posts/20969203/');
      expect(first.time, '13 minutes ago');
      expect(first.unread, isTrue);
    });

    test('counts unread alerts across groups', () {
      expect(page.unreadCount, greaterThan(0));
      expect(page.unreadCount, lessThanOrEqualTo(10));
    });
  });

  group('parseAlertPreferences', () {
    test('reads the live preferences page', () {
      final prefs = parseAlertPreferences(fixture('account_preferences.htm'));
      // The f95 defaults: the pop-up marks alerts read, the page doesn't.
      expect(prefs.popupSkipsMarkRead, isFalse);
      expect(prefs.pageSkipsMarkRead, isTrue);
    });

    test('reads the checked state of both skip-mark-read checkboxes', () {
      final prefs = parseAlertPreferences('''
        <label><input type="checkbox" name="option[sv_alerts_popup_skips_mark_read]" value="1" /> popup</label>
        <label><input type="checkbox" name="option[sv_alerts_page_skips_mark_read]" value="1" checked="checked" /> page</label>
      ''');
      expect(prefs.popupSkipsMarkRead, isFalse);
      expect(prefs.pageSkipsMarkRead, isTrue);
    });

    test('missing markup reads as unchecked, the f95 default', () {
      final prefs = parseAlertPreferences('<html><body><p>login required</p></body></html>');
      expect(prefs.popupSkipsMarkRead, isFalse);
      expect(prefs.pageSkipsMarkRead, isFalse);
    });
  });

  group('relative URLs', () {
    // Saved-page fixtures have browser-absolutized hrefs; the live site
    // emits relative ones, so the parsers must absolutize themselves.
    test('forum page URLs are absolutized', () {
      final page = parseForumPage('''
        <div class="node node--id9 node--depth2 node--forum">
          <h3 class="node-title"><a href="/forums/general-discussions.9/">General Discussions</a></h3>
          <div class="node-extra">
            <a href="/threads/hi.1/unread" class="node-extra-title" title="Hi">Hi</a>
          </div>
        </div>
        <div class="structItem structItem--thread js-threadListItem-42">
          <div class="structItem-cell structItem-cell--icon">
            <a class="avatar"><img src="/data/avatars/s/0/92.jpg"></a>
          </div>
          <div class="structItem-title"><a href="/threads/some-thread.42/unread">Some thread</a></div>
        </div>
      ''');

      expect(page.subforums.single.url, 'https://f95zone.to/forums/general-discussions.9/');
      expect(page.subforums.single.lastPost?.url, 'https://f95zone.to/threads/hi.1/unread');
      expect(page.threads.single.url, 'https://f95zone.to/threads/some-thread.42/');
      expect(page.threads.single.authorAvatarUrl, 'https://f95zone.to/data/avatars/s/0/92.jpg');
    });

    test('bookmark and alert URLs are absolutized', () {
      final bookmarks = parseBookmarks('''
        <li class="block-row">
          <div class="contentRow">
            <div class="contentRow-main">
              <div class="contentRow-extra">
                <a href="/posts/7/bookmark">Edit</a>
                <a href="/posts/7/bookmark?delete=1">Delete</a>
              </div>
              <div class="contentRow-title"><a href="/posts/7/">Post in thread 'Hi'</a></div>
            </div>
          </div>
        </li>
      ''');
      expect(bookmarks.entries.single.url, 'https://f95zone.to/posts/7/');
      expect(bookmarks.entries.single.bookmarkUrl, 'https://f95zone.to/posts/7/bookmark');

      final alerts = parseAlerts('''
        <ol class="listPlain"><li>
          <h2 class="block-formSectionHeader">Today</h2>
          <ol class="listPlain">
            <li data-alert-id="5" class="block-row">
              <div class="contentRow user-alert"><div class="contentRow-main">
                <a href="/members/a.9/" class="username">A</a> reacted to your message
                <a href="/posts/8/" class="fauxBlockLink-blockLink">Hello there</a>.
              </div></div>
            </li>
          </ol>
        </li></ol>
      ''');
      final alert = alerts.groups.single.alerts.single;
      expect(alert.url, 'https://f95zone.to/posts/8/');
      expect(alert.action, 'reacted to your message');
      expect(alert.title, 'Hello there');
      expect(alert.unread, isFalse);
    });

    test('watch URL is absolutized and the Unwatch label marks state', () {
      final page = parseThreadPosts('''
        <a href="/threads/9/watch" data-sk-watch="Watch" data-sk-unwatch="Unwatch">
          <span class="button-text">Unwatch</span>
        </a>
        <article class="message message--post" data-content="post-7">
          <div class="message-body"><div class="bbWrapper">hello</div></div>
        </article>
      ''');

      expect(page.watchUrl, 'https://f95zone.to/threads/9/watch');
      expect(page.watched, isTrue);
    });

    test('post reaction and avatar URLs are absolutized', () {
      final page = parseThreadPosts('''
        <article class="message message--post" data-author="A" data-content="post-7">
          <div class="message-avatar"><a href="/members/a.9/"><img src="/data/avatars/m/0/7.jpg"></a></div>
          <div class="message-body"><div class="bbWrapper">hello</div></div>
          <div class="reactionsBar">
            <a class="reactionsBar-link" href="/posts/7/reactions"><bdi>B</bdi></a>
          </div>
        </article>
      ''');

      final post = page.posts.single;
      expect(post.avatarUrl, 'https://f95zone.to/data/avatars/m/0/7.jpg');
      expect(post.authorUrl, 'https://f95zone.to/members/a.9/');
      expect(post.reactions?.url, 'https://f95zone.to/posts/7/reactions');
    });
  });

  group('guest-masked links', () {
    // Guests see <div class="messageHide messageHide--link">You must be
    // registered to see the links</div> per link (live markup; logged-in
    // fixtures can't contain it).
    test('become a tappable sign-in prompt', () {
      final page = parseThreadPosts('''
        <article class="message message--post" data-author="A" data-content="post-7">
          <div class="message-body"><div class="bbWrapper">
            Grab it here:
            <div class="messageHide messageHide--link">You must be registered to see the links</div>
          </div></div>
        </article>
      ''');

      final pieces = page.posts.single.blocks.single.pieces;
      expect(pieces.map((p) => p.text).join().trim(), 'Grab it here: Sign in to see links');
      final signIn = pieces.firstWhere((p) => p.text == 'Sign in');
      expect(signIn.url, 'https://f95zone.to/login/');
    });

    test('clustered masks collapse into one prompt; distant ones stay', () {
      final page = parseThreadPosts('''
        <article class="message message--post" data-author="A" data-content="post-7">
          <div class="message-body"><div class="bbWrapper">
            <b>Win</b>:
            <div class="messageHide messageHide--link">You must be registered to see the links</div> -
            <div class="messageHide messageHide--link">You must be registered to see the links</div> -
            <div class="messageHide messageHide--link">You must be registered to see the links</div>
            <br>Also check the walkthrough:
            <div class="messageHide messageHide--link">You must be registered to see the links</div>
          </div></div>
        </article>
      ''');

      final text = page.posts.single.blocks.single.pieces.map((p) => p.newline ? '\n' : p.text).join();
      expect('Sign in to see links'.allMatches(text), hasLength(2));
      expect(text, isNot(contains('-')));
      expect(text, contains('walkthrough: Sign in to see links'));
    });
  });

  group('write context', () {
    test('thread pages carry the csrf token and reply-form action', () {
      final page = parseThreadPosts(fixture('thread_renpy_bubbles_page2.htm'));
      expect(page.csrfToken, '1782950895,ebc0cfdc26c3ed20a0ccff7b3285a58f');
      expect(page.replyUrl, 'https://f95zone.to/threads/bubbles-and-babes-v0-162-bubbles-and-babes.207754/add-reply');
    });

    test('guest pages (no quick-reply form) yield a null reply URL', () {
      final page = parseThreadPosts('''
        <html data-csrf="123,abc"><body>
        <article class="message message--post" data-author="A" data-content="post-7">
          <div class="message-body"><div class="bbWrapper">hello</div></div>
        </article>
        </body></html>
      ''');
      expect(page.csrfToken, '123,abc');
      expect(page.replyUrl, isNull);
    });

    test('forum pages carry the post-thread URL and csrf', () {
      final page = parseForumPage(fixture('forum_gd.htm'));
      expect(page.postThreadUrl, 'https://f95zone.to/forums/general-discussions.9/post-thread');
      expect(page.csrfToken, '1781316060,3efe4d931f62f94a6ecbb1ba79338231');
    });
  });

  group('post images', () {
    // Live pages show a `/thumb/` src linked to the full image; saved
    // fixtures instead carry the full URL in data-src, so these use
    // synthetic markup like the other live-only cases.
    ForumPostBlock imageBlock(String bbWrapper) {
      final page = parseThreadPosts(
        '<article class="message message--post" data-author="A" data-content="post-7">'
        '<div class="message-body"><div class="bbWrapper">$bbWrapper</div></div></article>',
      );
      return page.posts.single.blocks.firstWhere((b) => b.pieces.any((p) => p.imageUrl != null));
    }

    test('uses the lightbox anchor as the full image, the img src as thumb', () {
      final img = imageBlock(
        '<a href="https://attachments.f95zone.to/2025/03/4646544_Cover.jpg" target="_blank">'
        '<img src="https://attachments.f95zone.to/2025/03/thumb/4646544_Cover.jpg" class="bbImage"></a>',
      ).pieces.firstWhere((p) => p.imageUrl != null);

      expect(img.imageUrl, 'https://attachments.f95zone.to/2025/03/thumb/4646544_Cover.jpg');
      expect(img.fullImageUrl, 'https://attachments.f95zone.to/2025/03/4646544_Cover.jpg');
    });

    test('falls back to stripping /thumb/ when the image is not anchored', () {
      final img = imageBlock(
        '<img src="https://attachments.f95zone.to/2025/03/thumb/999_x.png" class="bbImage">',
      ).pieces.firstWhere((p) => p.imageUrl != null);

      expect(img.imageUrl, 'https://attachments.f95zone.to/2025/03/thumb/999_x.png');
      expect(img.fullImageUrl, 'https://attachments.f95zone.to/2025/03/999_x.png');
    });

    test('leaves fullImageUrl null when thumbnail and full coincide', () {
      final img = imageBlock('<img src="https://example.com/pic.png" class="bbImage">').pieces.firstWhere(
        (p) => p.imageUrl != null,
      );

      expect(img.imageUrl, 'https://example.com/pic.png');
      expect(img.fullImageUrl, isNull);
    });

    test('downgrades directly-embedded full attachments to the preview host inline', () {
      final img = imageBlock(
        '<img src="https://attachments.f95zone.to/2025/03/777_full.png" class="bbImage">',
      ).pieces.firstWhere((p) => p.imageUrl != null);

      expect(img.imageUrl, 'https://preview.f95zone.to/2025/03/777_full.png');
      expect(img.fullImageUrl, 'https://attachments.f95zone.to/2025/03/777_full.png');
    });

    test('downgrades saved-page data-src full URLs to the preview host inline', () {
      final img = imageBlock(
        '<img src="" data-src="https://attachments.f95zone.to/2025/03/888_saved.png" class="bbImage">',
      ).pieces.firstWhere((p) => p.imageUrl != null);

      expect(img.imageUrl, 'https://preview.f95zone.to/2025/03/888_saved.png');
      expect(img.fullImageUrl, 'https://attachments.f95zone.to/2025/03/888_saved.png');
    });
  });

  group('parseSearchResults', () {
    late ForumSearchPage page;

    setUpAll(() => page = parseSearchResults(fixture('search_results.htm')));

    test('parses rows with title, prefixes, snippet, and attribution', () {
      expect(page.results, hasLength(20));
      final first = page.results.first;
      expect(first.title, 'Corruption of Champions II [v0.9.0] [Savin/Salamander Studios]');
      expect(first.prefixes, ['Others']);
      expect(
        first.url,
        'https://f95zone.to/threads/corruption-of-champions-ii-v0-9-0-savin-salamander-studios.11371/post-20920422',
      );
      expect(first.snippet, contains('might make the player feel powerful'));
      expect(first.author, 'Dragons Are Romance');
      expect(first.date, '5 minutes ago');
      expect(first.forum, 'Games');
    });

    test('lifts engine spans (pre-* classes) into prefixes too', () {
      final mirrored = page.results.firstWhere((r) => r.url.contains('mirrored-act-1'));
      expect(mirrored.title, 'Mirrored [Act 1 Ch.3] [Infinite Drift Studios]');
      expect(mirrored.prefixes, ['VN', "Ren'Py"]);
    });

    test('parses pagination and the GET-able results URL', () {
      expect(page.currentPage, 1);
      expect(page.totalPages, 50);
      expect(page.searchUrl, 'https://f95zone.to/search/649178657/?q=futanari&t=post&o=date');
    });
  });

  group('edit context', () {
    // No fixture has an edit link (own posts only); synthetic markup
    // mirrors XenForo's action bar.
    test('own posts carry their edit URL', () {
      final page = parseThreadPosts('''
        <article class="message message--post" data-author="Me" data-content="post-7">
          <div class="message-body"><div class="bbWrapper">mine</div></div>
          <div class="message-actionBar actionBar">
            <a href="/posts/7/edit" class="actionBar-action actionBar-action--edit js-quickEdit">Edit</a>
          </div>
        </article>
        <article class="message message--post" data-author="Other" data-content="post-8">
          <div class="message-body"><div class="bbWrapper">theirs</div></div>
        </article>
      ''');

      expect(page.posts.first.editUrl, 'https://f95zone.to/posts/7/edit');
      expect(page.posts.last.editUrl, isNull);
    });

    test('parseEditBbcode reads the edit form message', () {
      final bbcode = parseEditBbcode('''
        <form action="/posts/7/edit" method="post">
          <textarea name="message">Original [b]text[/b] &amp; more</textarea>
        </form>
      ''');
      expect(bbcode, 'Original [b]text[/b] & more');
    });

    test('parseEditBbcode finds the noscript BBCode textarea (real editor markup)', () {
      // The live editor macro: a jsOnly textarea holding HTML, with the
      // BBCode fallback inside <noscript> — which package:html parses as
      // raw text, so it needs a fragment re-parse.
      final bbcode = parseEditBbcode('''
        <form action="/posts/7/edit" method="post">
          <textarea name="message_html" class="input js-editor u-jsOnly" data-original-name="message"
            style="display: none;"><p>Original <b>text</b></p></textarea>
          <input type="hidden" value="" data-bb-code="message">
          <noscript>
            <textarea name="message" class="input">Original [b]text[/b] &amp; more</textarea>
          </noscript>
        </form>
      ''');
      expect(bbcode, 'Original [b]text[/b] & more');
    });

    test('parseEditBbcode falls back to the data-bb-code input value', () {
      final bbcode = parseEditBbcode('''
        <form action="/posts/7/edit" method="post">
          <textarea name="message_html" class="input js-editor u-jsOnly"><p>html</p></textarea>
          <input type="hidden" value="Fallback [i]bbcode[/i]" data-bb-code="message">
        </form>
      ''');
      expect(bbcode, 'Fallback [i]bbcode[/i]');
    });
  });

  group('parseReactionsPage', () {
    late ReactionsPage page;

    setUpAll(() => page = parseReactionsPage(fixture('reactions_being_a_dik.htm')));

    test('parses every reaction tab with name and count', () {
      expect(page.tabs, hasLength(13));
      expect(page.tabs.first.id, 0);
      expect(page.tabs.first.name, 'All');
      expect(page.tabs.first.count, 12837);

      final like = page.tabs[1];
      expect(like.id, 1);
      expect(like.name, 'Like');
      expect(like.count, 10546);

      final jizzed = page.tabs.firstWhere((t) => t.id == 13);
      expect(jizzed.name, 'Jizzed my pants');
      expect(jizzed.count, 36);
    });

    test('parses member rows with their reaction', () {
      expect(page.members, hasLength(50));
      final first = page.members.first;
      expect(first.username, 'Supoyev');
      expect(first.reactionId, 1);
      expect(first.memberTitle, 'New Member');
      expect(first.date, 'Yesterday at 2:34 PM');
      expect(first.avatarUrl, isNull);
    });
  });

  group('parseForumPage on the games forum', () {
    test('parses prefix labels on game rows', () {
      final page = parseForumPage(fixture('forum_games.htm'));
      final lost = page.threads.firstWhere((t) => t.threadId == 137266);
      expect(lost.title, 'Lost Media');
      expect(lost.prefixes.single.label, 'README');
    });
  });
}
