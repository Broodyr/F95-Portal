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

    test('links the avatar to its full-size original', () {
      // The header img is the downscaled `l` variant; the anchor around it
      // is the site's own link to the untouched upload.
      expect(page.avatarFullUrl, 'https://f95zone.to/data/avatars/o/328/328002.jpg?1777143770');
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

  group('parseProfilePage — wall pagination', () {
    test('reads the wall page-nav on a multi-page wall', () {
      final page = parseProfilePage(fixture('profile_wall_multipage.htm'));
      // The saved page is BaasB's wall page 3 of 4.
      expect(page.wallPage, 3);
      expect(page.wallTotalPages, 4);
    });

    test('a single-page wall reports one page', () {
      final page = parseProfilePage(fixture('profile_invader_incubus.htm'));
      expect(page.wallPosts, isNotEmpty);
      expect(page.wallPage, 1);
      expect(page.wallTotalPages, 1);
    });

    test('an empty wall reports one page', () {
      final page = parseProfilePage(fixture('profile_gugatron.htm'));
      expect(page.wallPage, 1);
      expect(page.wallTotalPages, 1);
    });

    test("does not read a sibling pane's page-nav as the wall's", () {
      // The postings pane paginates on its own; scoping the wall nav to
      // #profile-posts keeps that count from leaking into the wall's.
      const html = '''
<html><body><ul class="tabPanes">
  <li role="tabpanel" id="profile-posts">
    <article class="message--simple" data-content="profile-post-1" data-author="X">
      <article class="message-body">A post</article>
    </article>
    <nav class="pageNavWrapper"><div class="pageNav">
      <ul class="pageNav-main">
        <li class="pageNav-page "><a href="/members/x.1/">1</a></li>
        <li class="pageNav-page pageNav-page--current "><a href="/members/x.1/page-2">2</a></li>
      </ul>
    </div></nav>
  </li>
  <li role="tabpanel" aria-labelledby="recent-content">
    <nav class="pageNavWrapper"><div class="pageNav">
      <ul class="pageNav-main">
        <li class="pageNav-page "><a href="/x?page=8">8</a></li>
        <li class="pageNav-page "><a href="/x?page=9">9</a></li>
      </ul>
    </div></nav>
  </li>
</ul></body></html>
''';
      final page = parseProfilePage(html);
      expect(page.wallPage, 2);
      expect(page.wallTotalPages, 2, reason: "the postings pane's 9 must not count");
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

    test('captures the member-search query the Postings tab pages through', () {
      // The all-content query, not the content=thread (threads-only) variant.
      expect(page.postingsSearchUrl, 'https://f95zone.to/search/member?user_id=328002');
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

  group('parseProfilePostingsPage — member-search results', () {
    late ProfilePostingsPage page;

    setUpAll(() => page = parseProfilePostingsPage(fixture('profile_postings_search.htm')));

    test('parses every result row as a posting', () {
      expect(page.postings, hasLength(20));
    });

    test('reads the pagination the capped in-profile pane lacks', () {
      expect(page.currentPage, 1);
      expect(page.totalPages, 20);
    });

    test('captures the canonical results URL for further pages', () {
      expect(page.searchUrl, 'https://f95zone.to/search/655136415/?c[users]=BaasB&o=date');
    });

    test('keeps the postings the same shape as the in-profile pane', () {
      final reply = page.postings.firstWhere((p) => p.postInfo.startsWith('Post #'));
      expect(reply.title, isNotEmpty);
      expect(reply.url, startsWith('https://f95zone.to/threads/'));
      expect(reply.forum, isNotEmpty);
    });

    // Live pages emit relative hrefs; the saved fixture absolutized them.
    test('absolutizes the results URL on a live-shaped page', () {
      const relative = '''
<html><head><meta property="og:url" content="/search/655136415/?c[users]=BaasB&o=date" /></head>
<body><div class="block-row"><div class="contentRow"><div class="contentRow-main">
  <h3 class="contentRow-title"><a href="/threads/some-game.1/post-77">Some Game</a></h3>
  <div class="contentRow-minor"><ul><li>Post #77</li><li>Forum: <a href="/forums/games.2/">Games</a></li></ul></div>
</div></div></div></body></html>
''';
      final page = parseProfilePostingsPage(relative);
      expect(page.searchUrl, 'https://f95zone.to/search/655136415/?c[users]=BaasB&o=date');
      expect(page.postings.single.url, 'https://f95zone.to/threads/some-game.1/post-77');
    });
  });

  group('parseProfilePage — relative hrefs', () {
    // Live pages emit relative hrefs; browser-saved fixtures absolutize
    // them, so this synthetic page guards the live shape.
    const relativeHtml = '''
<html data-csrf="tok"><body>
<div class="memberHeader">
  <div class="memberHeader-avatar"><a href="/data/avatars/o/328/328002.jpg" class="avatar avatar--l"><img src="/data/avatars/l/328/328002.jpg"></a></div>
  <div class="memberHeader-name"><span class="username">Someone</span></div>
</div>
<a href="/members/someone.99/recent-content" class="tabs-tab" id="recent-content">Postings</a>
<a href="/search/member?user_id=99" class="fauxBlockLink-linkRow u-concealed">3</a>
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
      expect(page.avatarFullUrl, 'https://f95zone.to/data/avatars/o/328/328002.jpg');
      expect(page.profileUrl, 'https://f95zone.to/members/someone.99/');
      expect(page.wallPostUrl, 'https://f95zone.to/members/someone.99/post');
      expect(page.wallPosts.single.comments.single.avatarUrl, 'https://f95zone.to/data/avatars/s/328/328002.jpg');
      expect(page.wallPosts.single.comments.single.authorUrl, 'https://f95zone.to/members/someone.99/');
      expect(page.wallPosts.single.editUrl, 'https://f95zone.to/profile-posts/5/edit');
      expect(page.wallPosts.single.deleteUrl, 'https://f95zone.to/profile-posts/5/delete');
      expect(page.wallPosts.single.comments.single.editUrl, 'https://f95zone.to/profile-posts/comments/9/edit');
      expect(page.wallPosts.single.comments.single.deleteUrl, 'https://f95zone.to/profile-posts/comments/9/delete');
      expect(page.postings.single.url, 'https://f95zone.to/threads/some-game.1/post-77');
      expect(page.postingsSearchUrl, 'https://f95zone.to/search/member?user_id=99');
    });

    test('a default avatar offers no full-size image', () {
      // With nothing uploaded, XenForo aims the same anchor at the member's
      // own page. Opening that in an image viewer would show a broken icon.
      final page = parseProfilePage(
        relativeHtml.replaceAll(
          '<a href="/data/avatars/o/328/328002.jpg" class="avatar avatar--l">',
          '<a href="/members/someone.99/" class="avatar avatar--l avatar--default">',
        ),
      );
      expect(page.avatarFullUrl, isNull);
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

  group('wall bodies parse as rich content', () {
    late ProfilePage page;

    setUpAll(() => page = parseProfilePage(fixture('profile_post_links.htm')));

    test('a comment turns its URL into a link piece', () {
      final comment = page.wallPosts
          .expand((p) => p.comments)
          .firstWhere((c) => c.body.contains('read section 5'));

      final link = comment.rich.firstWhere((p) => p.url != null);
      expect(link.url, 'https://f95zone.to/threads/general-rules-updated-2026-05-07.5589/');
      // The mention beside it stays ordinary text.
      expect(comment.rich.first.text, contains('@angryweedDX'));
    });

    test('a post carries its text as pieces, breaks and all', () {
      final post = page.wallPosts.firstWhere((p) => p.body.startsWith('I want to tell real story'));
      expect(post.rich, isNotEmpty);
      expect(post.rich.where((p) => p.newline), isNotEmpty, reason: 'the post is written in two paragraphs');
      expect(post.rich.map((p) => p.text).join(), contains('I need help/advice'));
    });

    test('the plain body still reads for anything that wants a string', () {
      final post = page.wallPosts.firstWhere((p) => p.body.startsWith('I cannot respond'));
      expect(post.rich.map((p) => p.text).join(), contains('Check your PM settings'));
      expect(post.body, contains('Check your PM settings'));
    });

    test('a body with no markup still yields one text piece', () {
      final posts = parseProfilePage('''
        <div id="profile-posts">
          <article class="message--simple" data-content="profile-post-1" data-author="X">
            <article class="message-body">Just words.</article>
          </article>
        </div>
      ''').wallPosts;
      expect(posts.single.rich.single.text, 'Just words.');
      expect(posts.single.body, 'Just words.');
    });
  });

  group('block text keeps the line breaks the author wrote', () {
    String postBody(String body) => parseProfilePage('''
      <div id="profile-posts">
        <article class="message--simple" data-content="profile-post-1" data-author="X">
          <article class="message-body">$body</article>
        </article>
      </div>
    ''').wallPosts.single.body;

    String commentBody(String body) => parseProfilePage('''
      <div id="profile-posts">
        <article class="message--simple" data-content="profile-post-1" data-author="X">
          <article class="message-body">hi</article>
          <div class="comment" data-content="profile-post-comment-9" data-author="Y">
            <div class="comment-body">$body</div>
          </div>
        </article>
      </div>
    ''').wallPosts.single.comments.single.body;

    String bio(String body) => parseProfileAbout('<div class="block-row"><div class="bbWrapper">$body</div></div>').bio;

    // The source newlines are the point: XenForo emits them between the
    // <br/>s, and hard-wraps its markup besides.
    const paragraphs = 'Line one.<br />\n<br />\nLine two.';

    test('a wall post keeps a paragraph break', () {
      expect(postBody(paragraphs), 'Line one.\n\nLine two.');
    });

    test('a wall post keeps a single break single', () {
      expect(postBody('Line one.<br />\nLine two.'), 'Line one.\nLine two.');
    });

    test('a comment keeps a paragraph break', () {
      expect(commentBody(paragraphs), 'Line one.\n\nLine two.');
    });

    test('a bio keeps a paragraph break', () {
      expect(bio(paragraphs), 'Line one.\n\nLine two.');
    });

    test('a run of breaks caps at one blank line', () {
      expect(postBody('One.<br /><br /><br /><br />Two.'), 'One.\n\nTwo.');
    });

    test('a break at either end leaves no blank line behind', () {
      expect(postBody('<br /><br />Only.<br /><br />'), 'Only.');
    });

    // The trap the old bio helper fell into: it split on raw newlines, so
    // markup wrapped across source lines came out as separate lines.
    test('source wrapping is whitespace, not a break', () {
      expect(postBody('A sentence the site\n  wrapped across lines.'), 'A sentence the site wrapped across lines.');
      expect(bio('A bio the site\n  wrapped across lines.'), 'A bio the site wrapped across lines.');
    });

    test('a real wall keeps its breaks and joins its wrapped lines', () {
      final posts = parseProfilePage(fixture('profile_invader_incubus.htm')).wallPosts;

      // Hard-wrapped across six source lines, and one paragraph to a reader.
      expect(posts.first.body, startsWith('hey! Invader Incubus! I recently played your game eggomon'));
      expect(posts.first.body, isNot(contains('\n')));

      // This one really did write two lines, and used to arrive as one.
      expect(
        posts.last.body,
        'Will you let me know here when your Subscribestar is approved? =)\n'
            "I'll migrate over there as soon as its up!",
      );
    });
  });
}
