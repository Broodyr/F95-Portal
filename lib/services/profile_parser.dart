import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/profile.dart';
import 'forum_parser.dart' show liftTitlePrefixes;

/// Parsers for XenForo member profile pages. As with the other parsers,
/// missing or unrecognized markup degrades to empty fields, never a throw.

final RegExp _profilePostIdPattern = RegExp(r'profile-post-(\d+)');
final RegExp _commentIdPattern = RegExp(r'profile-post-comment-(\d+)');

/// Parses a member page (`/members/<slug>.<id>/`): the identity header, the
/// profile-post wall with nested comments, and — when its pane happens to be
/// rendered inline — the recent-content postings list. The same shape also
/// parses a directly fetched `/recent-content` page, which renders the full
/// member view with the postings pane active.
ProfilePage parseProfilePage(String htmlSource) {
  final document = html_parser.parse(htmlSource);

  final header = document.querySelector('.memberHeader');

  String messages = '';
  for (final dl in header?.querySelectorAll('dl') ?? const <Element>[]) {
    if (_clean(dl.querySelector('dt')?.text ?? '').toLowerCase() == 'messages') {
      messages = _clean(dl.querySelector('dd')?.text ?? '');
    }
  }

  String joined = '';
  String lastSeen = '';
  for (final blurb in header?.querySelectorAll('.memberHeader-blurb') ?? const <Element>[]) {
    final text = _clean(blurb.text);
    if (text.startsWith('Joined')) joined = _clean(text.substring('Joined'.length));
    if (text.startsWith('Last seen')) lastSeen = _clean(text.substring('Last seen'.length));
  }

  // The postings tab link carries the canonical member URL as its base.
  String profileUrl = '';
  for (final tab in document.querySelectorAll('a.tabs-tab')) {
    final href = tab.attributes['href'] ?? '';
    if (href.contains('recent-content')) {
      profileUrl = _absoluteUrl(href.replaceFirst(RegExp(r'recent-content/?$'), ''));
      break;
    }
  }

  // The wall composer only renders for viewers who can post on this wall.
  String? wallPostUrl;
  for (final form in document.querySelectorAll('form.message--simple')) {
    final action = form.attributes['action'] ?? '';
    if (action.endsWith('/post')) {
      wallPostUrl = _absoluteUrl(action);
      break;
    }
  }

  return ProfilePage(
    username: _clean(header?.querySelector('.username')?.text ?? ''),
    memberTitle: _clean(header?.querySelector('.userTitle')?.text ?? ''),
    avatarUrl: _absoluteOrNull(header?.querySelector('.memberHeader-avatar img')?.attributes['src']),
    messages: messages,
    joined: joined,
    lastSeen: lastSeen,
    profileUrl: profileUrl,
    wallPosts: _parseWallPosts(document),
    postings: _parsePostings(document),
    csrfToken: document.documentElement?.attributes['data-csrf'] ?? '',
    wallPostUrl: wallPostUrl,
  );
}

/// Parses the About tab's page (`/members/<slug>.<id>/about`): the user-set
/// bio as raw text plus the birthday/website/location detail pairs.
ProfileAbout parseProfileAbout(String htmlSource) {
  final document = html_parser.parse(htmlSource);

  String birthday = '';
  String website = '';
  String location = '';
  for (final dl in document.querySelectorAll('dl.pairs')) {
    final label = _clean(dl.querySelector('dt')?.text ?? '').toLowerCase();
    final value = _clean(dl.querySelector('dd')?.text ?? '');
    if (label == 'birthday') birthday = value;
    if (label == 'website') website = value;
    if (label == 'location') location = value;
  }

  // The bio renders as the first block-row holding a bare bbWrapper: f95
  // omits the stock "About" text header on it, while the other bbWrapper
  // rows (Signature) carry their own header.
  String bio = '';
  for (final row in document.querySelectorAll('.block-row')) {
    if (row.querySelector('h4.block-textHeader') != null) continue;
    final wrapper = row.querySelector('.bbWrapper');
    if (wrapper == null) continue;
    bio = _rawText(wrapper);
    break;
  }

  // Stock XenForo variant: the bio under an "About" text header.
  if (bio.isEmpty) {
    for (final heading in document.querySelectorAll('h4.block-textHeader')) {
      if (_clean(heading.text) != 'About') continue;
      final wrapper = heading.parent?.querySelector('.bbWrapper');
      if (wrapper != null) bio = _rawText(wrapper);
      break;
    }
  }

  return ProfileAbout(bio: bio, birthday: birthday, website: website, location: location);
}

List<ProfilePost> _parseWallPosts(Document document) {
  final pane = document.querySelector('#profile-posts') ?? document.documentElement;

  final posts = <ProfilePost>[];
  for (final article in pane?.querySelectorAll('article.message--simple') ?? const <Element>[]) {
    final id = _idFrom(article.attributes['data-content'] ?? '', _profilePostIdPattern);
    if (id == 0) continue;

    String? commentUrl;
    for (final form in article.querySelectorAll('form')) {
      final action = form.attributes['action'] ?? '';
      if (action.endsWith('/add-comment')) {
        commentUrl = _absoluteUrl(action);
        break;
      }
    }

    // The action bar's edit/delete links only render on the viewer's own
    // posts. Matching on the post's own id keeps nested comment actions
    // (/profile-posts/comments/N/...) from leaking in.
    String? editUrl;
    String? deleteUrl;
    for (final anchor in article.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (href.contains('profile-posts/$id/edit')) editUrl = _absoluteUrl(href);
      if (href.contains('profile-posts/$id/delete')) deleteUrl = _absoluteUrl(href);
    }

    posts.add(
      ProfilePost(
        id: id,
        author: _clean(article.attributes['data-author'] ?? ''),
        avatarUrl: _absoluteOrNull(article.querySelector('.message-avatar img')?.attributes['src']),
        authorUrl: _absoluteOrNull(article.querySelector('.message-avatar a')?.attributes['href']),
        date: _clean(article.querySelector('.message-attribution time')?.text ?? ''),
        body: _clean(article.querySelector('.message-body')?.text ?? ''),
        comments: [
          for (final comment in article.querySelectorAll('.comment'))
            if (_idFrom(comment.attributes['data-content'] ?? '', _commentIdPattern) != 0) _parseComment(comment),
        ],
        commentUrl: commentUrl,
        editUrl: editUrl,
        deleteUrl: deleteUrl,
      ),
    );
  }
  return posts;
}

ProfileComment _parseComment(Element comment) {
  final id = _idFrom(comment.attributes['data-content'] ?? '', _commentIdPattern);

  // Same arrangement as the post's action bar: the edit/delete links only
  // render on the viewer's own comments, and matching on the comment's own
  // id keeps sibling actions out.
  String? editUrl;
  String? deleteUrl;
  for (final anchor in comment.querySelectorAll('a[href]')) {
    final href = anchor.attributes['href'] ?? '';
    if (href.contains('profile-posts/comments/$id/edit')) editUrl = _absoluteUrl(href);
    if (href.contains('profile-posts/comments/$id/delete')) deleteUrl = _absoluteUrl(href);
  }

  return ProfileComment(
    id: id,
    author: _clean(comment.attributes['data-author'] ?? ''),
    avatarUrl: _absoluteOrNull(comment.querySelector('.comment-avatar img')?.attributes['src']),
    authorUrl: _absoluteOrNull(comment.querySelector('.comment-avatar a')?.attributes['href']),
    body: _clean(comment.querySelector('.comment-body')?.text ?? ''),
    date: _clean(comment.querySelector('.comment-footer time')?.text ?? ''),
    editUrl: editUrl,
    deleteUrl: deleteUrl,
  );
}

List<ProfilePosting> _parsePostings(Document document) {
  // Scope to the postings pane: the latest-activity pane renders the same
  // contentRow markup and must not bleed in. The aria-labelledby wiring is
  // added by XenForo's tab JS, so it only exists in browser-saved fixtures;
  // raw server HTML needs the fallback, which takes every contentRow except
  // those under the latest-activity pane (its data-href is server-rendered).
  final pane = document.querySelector('li[aria-labelledby="recent-content"]');
  final rows = pane != null
      ? pane.querySelectorAll('.block-row .contentRow')
      : document.querySelectorAll('.block-row .contentRow').where(_outsideLatestActivity).toList();

  final postings = <ProfilePosting>[];
  for (final row in rows) {
    final link = row.querySelector('.contentRow-title a[href]');
    if (link == null) continue;

    final prefixes = liftTitlePrefixes(link);

    String postInfo = '';
    String replies = '';
    String date = '';
    String forum = '';
    for (final li in row.querySelectorAll('.contentRow-minor li')) {
      final text = _clean(li.text);
      if (text == 'Thread' || text.startsWith('Post #')) postInfo = text;
      if (text.startsWith('Replies:')) replies = _clean(text.substring('Replies:'.length));
      if (text.startsWith('Forum:')) forum = _clean(li.querySelector('a')?.text ?? '');
      if (li.querySelector('time') != null) date = _clean(li.querySelector('time')!.text);
    }

    postings.add(
      ProfilePosting(
        title: _clean(link.text),
        prefixes: prefixes,
        url: _absoluteUrl(link.attributes['href'] ?? ''),
        snippet: _clean(row.querySelector('.contentRow-snippet')?.text ?? ''),
        postInfo: postInfo,
        replies: replies,
        date: date,
        forum: forum,
      ),
    );
  }
  return postings;
}

bool _outsideLatestActivity(Element row) {
  for (Element? el = row.parent; el != null; el = el.parent) {
    if ((el.attributes['data-href'] ?? '').contains('latest-activity')) return false;
    if (el.classes.contains('js-newsFeedTarget')) return false;
  }
  return true;
}

/// Text content with `<br>` respected as line breaks, runs of blank lines
/// collapsed, and per-line whitespace tidied — for "raw" display of user
/// bios without any BBCode handling.
String _rawText(Element element) {
  for (final br in element.querySelectorAll('br')) {
    br.replaceWith(Text('\n'));
  }
  final lines = element.text.split('\n').map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
  return lines.where((line) => line.isNotEmpty).join('\n');
}

int _idFrom(String source, RegExp pattern) => int.tryParse(pattern.firstMatch(source)?.group(1) ?? '') ?? 0;

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Live pages emit relative hrefs (saved fixtures have browser-absolutized
/// ones); everything stored in a model must be fetchable as-is.
String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  return url.startsWith('/') ? 'https://f95zone.to$url' : 'https://f95zone.to/$url';
}

String? _absoluteOrNull(String? url) => url == null ? null : _absoluteUrl(url);
