import 'dart:io';

import 'package:f95_portal/models/profile.dart';
import 'package:f95_portal/services/profile_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('parseProfilePage — header', () {
    late ProfilePage page;

    setUpAll(() => page = parseProfilePage(fixture('profile_gugatron.htm')));

    test('parses the identity block', () {
      expect(page.username, 'Gugatron');
      expect(page.memberTitle, 'Member');
      expect(page.avatarUrl, isNotNull);
      expect(page.messages, '291');
      expect(page.joined, 'Dec 11, 2017');
      expect(page.lastSeen, '11 minutes ago');
    });

    test('resolves the canonical profile URL', () {
      expect(page.profileUrl, 'https://f95zone.to/members/gugatron.328002/');
    });

    test('captures the CSRF token and wall composer action', () {
      expect(page.csrfToken, isNotEmpty);
      expect(page.wallPostUrl, 'https://f95zone.to/members/gugatron.328002/post');
    });

    test('an empty wall parses as no posts', () {
      expect(page.wallPosts, isEmpty);
    });
  });

  group('parseProfilePage — wall posts', () {
    late ProfilePage page;

    setUpAll(() => page = parseProfilePage(fixture('profile_invader_incubus.htm')));

    test('parses every wall post in order', () {
      expect(page.wallPosts.map((p) => p.id).toList(), [142106, 138154, 133869, 88239]);
      expect(page.wallPosts.map((p) => p.author).toList(), [
        'madladthemadlad',
        'Pipura',
        'Kaito Sudzuki',
        'Mister Wake',
      ]);
    });

    test('parses a wall post body and date', () {
      final post = page.wallPosts.first;
      expect(post.date, 'May 14, 2026');
      expect(post.body, startsWith('hey! Invader Incubus! I recently played your game eggomon'));
      expect(post.commentUrl, 'https://f95zone.to/profile-posts/142106/add-comment');
      // The avatar anchor carries the member URL even for initial-letter
      // placeholder avatars.
      expect(post.authorUrl, 'https://f95zone.to/members/madladthemadlad.8830520/');
    });

    test('parses nested comments with author, body, and date', () {
      final comments = page.wallPosts.first.comments;
      expect(comments.length, 3);
      expect(comments[0].id, 166742);
      expect(comments[0].author, 'Jacobsiege');
      expect(comments[0].body, startsWith('I hope this post gets noticed'));
      expect(comments[0].date, 'May 15, 2026');
      // Initial-letter placeholder avatars parse as no avatar.
      expect(comments[0].avatarUrl, isNull);
      expect(comments[0].authorUrl, 'https://f95zone.to/members/jacobsiege.1595023/');
      // The profile owner replies with a real avatar image.
      expect(comments[1].author, 'Invader Incubus');
      expect(comments[1].avatarUrl, isNotNull);
    });

    test('a wall post without comments parses as an empty list', () {
      expect(page.wallPosts.last.comments, isEmpty);
    });

    test('does not leak comment bodies into the wall post body', () {
      expect(page.wallPosts.first.body, isNot(contains('I hope this post gets noticed')));
    });
  });

  group('parseProfilePage — own post actions', () {
    late ProfilePage page;

    setUpAll(() => page = parseProfilePage(fixture('profile_own_post.htm')));

    test('parses edit and delete URLs on the viewer-owned post', () {
      final post = page.wallPosts.singleWhere((p) => p.id == 146954);
      expect(post.author, 'Broodyr');
      expect(post.editUrl, 'https://f95zone.to/profile-posts/146954/edit');
      expect(post.deleteUrl, 'https://f95zone.to/profile-posts/146954/delete');
    });

    test("others' posts parse without edit or delete URLs", () {
      final other = parseProfilePage(fixture('profile_invader_incubus.htm'));
      expect(other.wallPosts, isNotEmpty);
      expect(other.wallPosts.every((p) => p.editUrl == null && p.deleteUrl == null), isTrue);
    });

    test('parses edit and delete URLs on the viewer-owned comment only', () {
      final page = parseProfilePage(fixture('profile_own_comment.htm'));
      final comments = page.wallPosts.singleWhere((p) => p.id == 146954).comments;

      final own = comments.singleWhere((c) => c.id == 173522);
      expect(own.editUrl, 'https://f95zone.to/profile-posts/comments/173522/edit');
      expect(own.deleteUrl, 'https://f95zone.to/profile-posts/comments/173522/delete');

      final other = comments.singleWhere((c) => c.id == 173518);
      expect(other.editUrl, isNull);
      expect(other.deleteUrl, isNull);
    });
  });

  group('parseProfilePage — postings', () {
    late ProfilePage page;

    setUpAll(() => page = parseProfilePage(fixture('profile_gugatron.htm')));

    test('parses every posting from the recent-content pane only', () {
      expect(page.postings.length, 15);
    });

    test('parses a reply row with prefixes, post number, and forum', () {
      final first = page.postings.first;
      expect(first.title, 'Myth of Slayer Walkthrough [Ch 11] (Gugatron)');
      expect(first.prefixes, ["Mod", "Ren'Py"]);
      expect(first.url, 'https://f95zone.to/threads/myth-of-slayer-walkthrough-ch-11-gugatron.276090/post-20908354');
      expect(first.snippet, startsWith("No, I hadn't even heard of this app"));
      expect(first.postInfo, 'Post #29');
      expect(first.replies, '');
      expect(first.date, '21 minutes ago');
      expect(first.forum, 'Mods');
    });

    test('parses a thread row with its reply count', () {
      final thread = page.postings.firstWhere((p) => p.postInfo == 'Thread');
      expect(thread.title, contains('Echoes: The Lies We Tell Ourselves'));
      expect(thread.replies, '1');
      expect(thread.forum, 'Mods');
      expect(thread.date, 'Jun 2, 2026');
    });

    test('a profile without an inline postings pane parses as empty', () {
      final other = parseProfilePage(fixture('profile_invader_incubus.htm'));
      expect(other.postings, isEmpty);
    });

    test('parses a directly fetched recent-content page', () {
      final direct = parseProfilePage(fixture('profile_postings.htm'));
      expect(direct.postings.length, 15);
      expect(direct.postings.first.title, contains('ToxiCity Multi-Mod'));
      expect(direct.postings.first.prefixes, contains('Mod'));
    });

    // The aria-labelledby pane wiring is added by XenForo's tab JS, so it
    // only exists in browser-saved fixtures — raw server HTML (what the
    // app actually fetches) has none. Stripping it simulates that.
    String withoutAria(String name) => fixture(name).replaceAll(RegExp(r'aria-labelledby="[^"]*"'), '');

    test('parses server HTML without aria pane attributes', () {
      final direct = parseProfilePage(withoutAria('profile_postings.htm'));
      expect(direct.postings.length, 15);
      expect(direct.postings.first.title, contains('ToxiCity Multi-Mod'));
    });

    test('still excludes latest-activity rows without aria attributes', () {
      final page = parseProfilePage(withoutAria('profile_gugatron.htm'));
      // The gugatron save also has the latest-activity pane filled with 15
      // lookalike contentRows; only the postings 15 may come through.
      expect(page.postings.length, 15);
      expect(page.postings.every((p) => p.postInfo.isNotEmpty), isTrue);
    });
  });

  group('parseProfilePage — relative hrefs', () {
    // Live pages emit relative hrefs; browser-saved fixtures absolutize
    // them, so this synthetic page guards the live shape.
    const relativeHtml = '''
<html data-csrf="tok"><body>
<div class="memberHeader">
  <div class="memberHeader-avatar"><img src="/data/avatars/l/328/328002.jpg"></div>
  <div class="memberHeader-name"><span class="username">Someone</span></div>
</div>
<a href="/members/someone.99/recent-content" class="tabs-tab" id="recent-content">Postings</a>
<ul class="tabPanes">
  <li role="tabpanel" id="profile-posts" aria-expanded="true">
    <form action="/members/someone.99/post" method="post" class="message message--simple"></form>
    <article class="message message--simple js-inlineModContainer" data-author="visitor" data-content="profile-post-5">
      <header class="message-attribution"><time>Jan 1, 2026</time></header>
      <article class="message-body">Hello there</article>
      <div class="comment" data-author="someone" data-content="profile-post-comment-9">
        <span class="comment-avatar"><a href="/members/someone.99/"><img src="/data/avatars/s/328/328002.jpg"></a></span>
        <article class="comment-body">Hi back</article>
        <a href="/profile-posts/comments/9/edit" class="actionBar-action actionBar-action--edit">Edit</a>
        <a href="/profile-posts/comments/9/delete" class="actionBar-action actionBar-action--delete">Delete</a>
      </div>
      <footer class="message-footer"><div class="message-actionBar actionBar">
        <a href="/profile-posts/5/edit" class="actionBar-action actionBar-action--edit">Edit</a>
        <a href="/profile-posts/5/delete" class="actionBar-action actionBar-action--delete">Delete</a>
      </div></footer>
    </article>
  </li>
  <li role="tabpanel" aria-labelledby="recent-content">
    <div class="block-row"><div class="contentRow">
      <div class="contentRow-main">
        <h3 class="contentRow-title"><a href="/threads/some-game.1/post-77"><span class="label">VN</span><span class="label-append"> </span><span class="pre-renpy">Ren'Py</span><span class="label-append"> </span>Some Game</a></h3>
        <div class="contentRow-snippet">A snippet</div>
        <div class="contentRow-minor"><ul>
          <li><a class="username" href="/members/someone.99/">Someone</a></li>
          <li>Post #77</li>
          <li><time>Jan 2, 2026</time></li>
          <li>Forum: <a href="/forums/games.2/">Games</a></li>
        </ul></div>
      </div>
    </div></div>
  </li>
</ul>
</body></html>
''';

    test('absolutizes every URL in the parsed page', () {
      final page = parseProfilePage(relativeHtml);
      expect(page.avatarUrl, 'https://f95zone.to/data/avatars/l/328/328002.jpg');
      expect(page.profileUrl, 'https://f95zone.to/members/someone.99/');
      expect(page.wallPostUrl, 'https://f95zone.to/members/someone.99/post');
      expect(page.wallPosts.single.comments.single.avatarUrl, 'https://f95zone.to/data/avatars/s/328/328002.jpg');
      expect(page.wallPosts.single.comments.single.authorUrl, 'https://f95zone.to/members/someone.99/');
      expect(page.wallPosts.single.editUrl, 'https://f95zone.to/profile-posts/5/edit');
      expect(page.wallPosts.single.deleteUrl, 'https://f95zone.to/profile-posts/5/delete');
      expect(page.wallPosts.single.comments.single.editUrl, 'https://f95zone.to/profile-posts/comments/9/edit');
      expect(page.wallPosts.single.comments.single.deleteUrl, 'https://f95zone.to/profile-posts/comments/9/delete');
      expect(page.postings.single.url, 'https://f95zone.to/threads/some-game.1/post-77');
    });

    test('comment edit links never become the post edit URL', () {
      // Only the footer's own-id action counts; the nested comment's
      // /profile-posts/comments/9/edit anchor must not be picked up.
      final withoutFooter = relativeHtml.replaceAll(RegExp(r'<footer class="message-footer">[\s\S]*?</footer>'), '');
      final page = parseProfilePage(withoutFooter);
      expect(page.wallPosts.single.editUrl, isNull);
      expect(page.wallPosts.single.deleteUrl, isNull);
    });

    test('lifts engine spans without the label class into prefixes', () {
      final posting = parseProfilePage(relativeHtml).postings.single;
      expect(posting.title, 'Some Game');
      expect(posting.prefixes, ["VN", "Ren'Py"]);
    });
  });

  group('parseProfileAbout — real fixtures', () {
    // The same profile saved two ways: the /about page fetched directly
    // ("discrete", what the service does) and the member page saved after
    // clicking the About tab ("integrated"). Both must parse identically.
    for (final name in ['profile_about_discrete.htm', 'profile_about_integrated.htm']) {
      test('parses the detail pairs from $name', () {
        final about = parseProfileAbout(fixture(name));
        expect(about.birthday, 'July 10');
        expect(about.website, 'https://patreon.com/gugatron');
        expect(about.location, 'Brazil');
      });

      test('parses the headerless bio row, not the signature, from $name', () {
        final about = parseProfileAbout(fixture(name));
        expect(about.bio, startsWith('Just a random guy who likes games.'));
        expect(about.bio, contains('My walkthrough list:'));
        // Line breaks survive as raw text.
        expect(about.bio, contains('ToxiCity\nomiSt'));
      });
    }
  });

  group('parseProfileAbout — synthetic', () {
    // Stock XenForo member_about variant, where the bio sits under an
    // "About" text header; kept as a fallback shape.
    const aboutHtml = '''
<html data-csrf="tok"><body>
<div class="memberHeader">
  <dl class="pairs pairs--rows"><dt>Messages</dt><dd>291</dd></dl>
</div>
<div class="block-container"><div class="block-body">
  <div class="block-row">
    <dl class="pairs pairs--columns pairs--fixedSmall"><dt>Birthday</dt><dd>Jan 28, 1990 (Age: 36)</dd></dl>
    <dl class="pairs pairs--columns pairs--fixedSmall"><dt>Website</dt><dd><a href="https://example.itch.io/">example.itch.io</a></dd></dl>
    <dl class="pairs pairs--columns pairs--fixedSmall"><dt>Location</dt><dd><a href="/misc/location-info?location=Berlin">Berlin</a></dd></dl>
  </div>
  <div class="block-row">
    <h4 class="block-textHeader">About</h4>
    <div class="bbWrapper">Making small games.<br>
Support me on itch!</div>
  </div>
</div></div>
</body></html>
''';

    test('parses the bio and detail pairs', () {
      final about = parseProfileAbout(aboutHtml);
      expect(about.birthday, 'Jan 28, 1990 (Age: 36)');
      expect(about.website, 'example.itch.io');
      expect(about.location, 'Berlin');
      expect(about.bio, 'Making small games.\nSupport me on itch!');
      expect(about.isEmpty, isFalse);
    });

    test('missing fields parse as empty', () {
      final about = parseProfileAbout('<html><body><div class="block-container"></div></body></html>');
      expect(about.isEmpty, isTrue);
    });

    test('ignores unrelated stat pairs like Messages', () {
      final about = parseProfileAbout(aboutHtml);
      expect(about.birthday, isNot(contains('291')));
    });
  });
}
