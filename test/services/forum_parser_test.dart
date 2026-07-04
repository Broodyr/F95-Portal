import 'dart:io';

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

    test('parses post attribution', () {
      final post = page.posts.first;
      expect(post.postId, 13720617);
      expect(post.number, 21);
      expect(post.author, 'Lerd0');
      expect(post.memberTitle, 'Bussyloader');
      expect(post.date, 'May 12, 2024');
      expect(post.avatarUrl, endsWith('137028_002_iNbu.jpg'));
    });

    test('splits the body into quote and rich blocks in order', () {
      final blocks = page.posts.first.blocks;
      expect(blocks.first.kind, PostBlockKind.quote);
      expect(blocks.first.label, 'Bubbles and Sisters');
      expect(blocks.first.pieces.map((p) => p.text).join(), contains("switching to real incest"));

      final rich = blocks[1];
      expect(rich.kind, PostBlockKind.rich);
      expect(
        rich.pieces.map((p) => p.imageUrl).whereType<String>(),
        contains('https://attachments.f95zone.to/2024/05/3652583_1715545111474.png'),
      );
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

    test('post reaction and avatar URLs are absolutized', () {
      final page = parseThreadPosts('''
        <article class="message message--post" data-author="A" data-content="post-7">
          <div class="message-avatar"><img src="/data/avatars/m/0/7.jpg"></div>
          <div class="message-body"><div class="bbWrapper">hello</div></div>
          <div class="reactionsBar">
            <a class="reactionsBar-link" href="/posts/7/reactions"><bdi>B</bdi></a>
          </div>
        </article>
      ''');

      final post = page.posts.single;
      expect(post.avatarUrl, 'https://f95zone.to/data/avatars/m/0/7.jpg');
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
