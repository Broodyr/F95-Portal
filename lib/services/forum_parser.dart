import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/account.dart';
import '../models/forum.dart';
import 'thread_page_parser.dart' show parseRichContent;

/// Parsers for XenForo forum pages. Like the thread-page parser, nothing
/// here is required: unrecognized or missing markup degrades to empty
/// fields rather than failing the parse.

final RegExp _nodeIdPattern = RegExp(r'node--id(\d+)');
final RegExp _categoryIdPattern = RegExp(r'block--category(\d+)');
final RegExp _threadRowIdPattern = RegExp(r'js-threadListItem-(\d+)');
final RegExp _prefixIdPattern = RegExp(r'prefix_id\[0\]=(\d+)');
final RegExp _postIdPattern = RegExp(r'post-(\d+)');
final RegExp _othersPattern = RegExp(r'and (\d+) others');
final RegExp _tabReactionPattern = RegExp(r'tabs-tab--reaction(\d+)');
final RegExp _tabCountPattern = RegExp(r'\((\d+)\)');

/// Parses the forum index (f95zone.to/forum/) into categories of forums.
ForumIndex parseForumIndex(String htmlSource) {
  final document = html_parser.parse(htmlSource);

  final categories = <ForumCategory>[];
  for (final block in document.querySelectorAll('.block--category')) {
    final title = block.querySelector('.uix_categoryTitle') ?? block.querySelector('.block-header a');
    if (title == null) continue;

    categories.add(
      ForumCategory(
        id: _idFrom(block.className, _categoryIdPattern),
        title: _clean(title.text),
        forums: [
          for (final node in block.querySelectorAll('.node--forum'))
            if (node.classes.contains('node--depth2')) _parseNode(node),
        ],
      ),
    );
  }

  return ForumIndex(categories: categories);
}

/// Parses one forum's page: title, subforum block, thread rows, pagination.
ForumPage parseForumPage(String htmlSource) {
  final document = html_parser.parse(htmlSource);

  final (currentPage, totalPages) = _parsePageNav(document);

  // The "Post thread" button link doubles as the create-thread endpoint;
  // absent when the viewer can't post here.
  String? postThreadUrl;
  for (final link in document.querySelectorAll('a[href]')) {
    final href = link.attributes['href'] ?? '';
    if (href.endsWith('/post-thread') && link.classes.contains('button')) {
      postThreadUrl = _absoluteUrl(href);
      break;
    }
  }

  return ForumPage(
    title: _clean(document.querySelector('h1.p-title-value')?.text ?? ''),
    subforums: [for (final node in document.querySelectorAll('.node--forum')) _parseNode(node)],
    threads: [
      for (final row in document.querySelectorAll('.structItem--thread'))
        if (_idFrom(row.className, _threadRowIdPattern) != 0) _parseThreadRow(row),
    ],
    currentPage: currentPage,
    totalPages: totalPages,
    postThreadUrl: postThreadUrl,
    csrfToken: document.documentElement?.attributes['data-csrf'] ?? '',
  );
}

/// Parses a thread page's full post loop for the forum viewer: every post
/// with attribution, body blocks, and reaction summary, plus pagination.
ThreadPostsPage parseThreadPosts(String htmlSource) {
  final document = html_parser.parse(htmlSource);
  final (currentPage, totalPages) = _parsePageNav(document);

  // Prefix labels render inside the h1; only the bare title is wanted.
  final h1 = document.querySelector('h1.p-title-value');
  for (final label in h1?.querySelectorAll('.labelLink, .label') ?? const <Element>[]) {
    label.remove();
  }

  // Write context: page CSRF lives on the html tag; the quick-reply form
  // only renders for members who can post, so its absence gates reply UI.
  final replyAction = document.querySelector('form.js-quickReply')?.attributes['action'];

  // Watch is a member-only anchor; its live label tells the current state.
  final watchAnchor = document.querySelector('a[data-sk-watch]');
  final watchHref = watchAnchor?.attributes['href'];

  // The canonical link names the true thread page even when this HTML was
  // reached through a post-permalink redirect.
  final canonical = document.querySelector('link[rel="canonical"]')?.attributes['href'] ?? '';

  return ThreadPostsPage(
    title: _clean(h1?.text ?? ''),
    posts: [for (final post in document.querySelectorAll('article.message--post')) _parsePost(post)],
    currentPage: currentPage,
    totalPages: totalPages,
    csrfToken: document.documentElement?.attributes['data-csrf'] ?? '',
    replyUrl: replyAction == null ? null : _absoluteUrl(replyAction),
    watchUrl: watchHref == null ? null : _absoluteUrl(watchHref),
    watched: watchAnchor != null && _clean(watchAnchor.text).toLowerCase() == 'unwatch',
    threadUrl: canonical.isEmpty ? '' : _absoluteUrl(canonical.replaceFirst(RegExp(r'page-\d+/?$'), '')),
  );
}

/// Reads the alert read-marking checkboxes from the account preferences
/// page. Missing markup reads as unchecked, matching both the stock
/// behavior and the f95 default.
AlertPreferences parseAlertPreferences(String htmlSource) {
  final document = html_parser.parse(htmlSource);

  bool checked(String option) {
    for (final input in document.querySelectorAll('input[type="checkbox"]')) {
      if (input.attributes['name'] == 'option[$option]') return input.attributes.containsKey('checked');
    }
    return false;
  }

  return AlertPreferences(
    popupSkipsMarkRead: checked('sv_alerts_popup_skips_mark_read'),
    pageSkipsMarkRead: checked('sv_alerts_page_skips_mark_read'),
  );
}

/// Serializes the account preferences form the way a browser submit would:
/// every successful control (unchecked boxes excluded, selected options
/// only) as an ordered (name, value) pair. Returns an empty form when the
/// page has no preferences form (e.g. logged out).
PreferencesForm parsePreferencesForm(String htmlSource) {
  final document = html_parser.parse(htmlSource);
  final form = document.querySelector('form[action*="/account/preferences"]');
  if (form == null) return const PreferencesForm();

  String csrfToken = document.documentElement?.attributes['data-csrf'] ?? '';
  final fields = <(String, String)>[];

  for (final element in form.querySelectorAll('input, select, textarea')) {
    final name = element.attributes['name'] ?? '';
    if (name.isEmpty || element.attributes.containsKey('disabled')) continue;

    if (element.localName == 'select') {
      final options = element.querySelectorAll('option');
      var chosen = [
        for (final option in options)
          if (option.attributes.containsKey('selected')) option,
      ];
      // A single-select with no selected option submits its first option.
      if (chosen.isEmpty && !element.attributes.containsKey('multiple') && options.isNotEmpty) {
        chosen = [options.first];
      }
      for (final option in chosen) {
        fields.add((name, option.attributes['value'] ?? _clean(option.text)));
      }
      continue;
    }
    if (element.localName == 'textarea') {
      fields.add((name, element.text));
      continue;
    }

    final type = (element.attributes['type'] ?? 'text').toLowerCase();
    if (const {'submit', 'button', 'image', 'reset', 'file'}.contains(type)) continue;
    final bool checkable = type == 'checkbox' || type == 'radio';
    if (checkable && !element.attributes.containsKey('checked')) continue;
    final value = element.attributes['value'] ?? (checkable ? 'on' : '');
    if (name == '_xfToken') {
      csrfToken = value;
      continue;
    }
    fields.add((name, value));
  }

  return PreferencesForm(csrfToken: csrfToken, fields: fields);
}

/// Parses the report overlay served for a post or profile post
/// (`/posts/N/report`, `/profile-posts/N/report`).
///
/// The reasons are site configuration rather than anything fixed, so they're
/// read off the form instead of being baked in — a reason added or renamed on
/// the site shows up without a release. Returns an empty form for a page that
/// has none (a guest fetch redirects to login), which the caller reads as
/// "can't report this" through [ReportForm.isAvailable].
ReportForm parseReportForm(String htmlSource) {
  final document = html_parser.parse(htmlSource);
  final form = document.querySelector('form[action*="/report"]');
  if (form == null) return const ReportForm();

  final reasons = <ReportReason>[];
  for (final input in form.querySelectorAll('input[name="reason_id"]')) {
    final id = int.tryParse(input.attributes['value'] ?? '');
    if (id == null) continue;
    // The visible text is a sibling span inside the wrapping <label>; the
    // input itself carries only the id.
    final label = _clean(input.parent?.querySelector('.iconic-label')?.text ?? '');
    if (label.isEmpty) continue;
    reasons.add(ReportReason(id: id, label: label));
  }

  return ReportForm(
    action: _absoluteUrl(form.attributes['action'] ?? ''),
    // The form's own hidden token, falling back to the page's: an overlay
    // fetched on its own carries the input, a full page carries the attribute.
    csrfToken:
        form.querySelector('input[name="_xfToken"]')?.attributes['value'] ??
        document.documentElement?.attributes['data-csrf'] ??
        '',
    reasons: reasons,
  );
}

/// Parses the account bookmarks page (`/account/bookmarks`).
BookmarksPage parseBookmarks(String htmlSource) {
  final document = html_parser.parse(htmlSource);
  final (currentPage, totalPages) = _parsePageNav(document);
  final titlePattern = RegExp(r"^(Post in thread|Thread) '(.*)'$");

  final entries = <BookmarkEntry>[];
  for (final row in document.querySelectorAll('.block-row .contentRow')) {
    final titleLink = row.querySelector('.contentRow-title a[href]');
    if (titleLink == null) continue;

    // Titles render as "Thread '…'" or "Post in thread '…'"; only the
    // inner title is wanted, the wrapper just tells the bookmark kind.
    final rawTitle = _clean(titleLink.text);
    final titleMatch = titlePattern.firstMatch(rawTitle);

    // The row's tools menu holds the bookmark endpoint (its Delete variant
    // is the same URL with ?delete=1).
    String bookmarkUrl = '';
    for (final anchor in row.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (href.endsWith('/bookmark')) {
        bookmarkUrl = _absoluteUrl(href);
        break;
      }
    }

    final avatarSrc = row.querySelector('.contentRow-figure img')?.attributes['src'];
    entries.add(
      BookmarkEntry(
        title: titleMatch?.group(2) ?? rawTitle,
        isPost: titleMatch?.group(1) == 'Post in thread',
        url: _absoluteUrl(titleLink.attributes['href'] ?? ''),
        snippet: _clean(row.querySelector('.contentRow-snippet')?.text ?? ''),
        author: _clean(row.querySelector('.contentRow-minor .username')?.text ?? ''),
        avatarUrl: avatarSrc == null ? null : _absoluteUrl(avatarSrc),
        date: _clean(row.querySelector('.contentRow-minor time')?.text ?? ''),
        bookmarkUrl: bookmarkUrl,
      ),
    );
  }

  return BookmarksPage(
    entries: entries,
    currentPage: currentPage,
    totalPages: totalPages,
    csrfToken: document.documentElement?.attributes['data-csrf'] ?? '',
  );
}

/// Parses the account alerts page (`/account/alerts`) into its date groups.
AlertsPage parseAlerts(String htmlSource) {
  final document = html_parser.parse(htmlSource);
  final (currentPage, totalPages) = _parsePageNav(document);

  // Each date header ("Today", "Yesterday", "Friday") shares a list item
  // with its own inner list of alert rows.
  final groups = <AlertGroup>[];
  for (final header in document.querySelectorAll('h2.block-formSectionHeader')) {
    final rows = header.parent?.querySelectorAll('li[data-alert-id]') ?? const <Element>[];
    if (rows.isEmpty) continue;
    groups.add(AlertGroup(title: _clean(header.text), alerts: [for (final row in rows) _parseAlertRow(row)]));
  }

  // Tolerate a flat page without date headers.
  if (groups.isEmpty) {
    final rows = document.querySelectorAll('li[data-alert-id]');
    if (rows.isNotEmpty) groups.add(AlertGroup(alerts: [for (final row in rows) _parseAlertRow(row)]));
  }

  return AlertsPage(
    groups: groups,
    currentPage: currentPage,
    totalPages: totalPages,
    csrfToken: document.documentElement?.attributes['data-csrf'] ?? '',
    // The nav bell's server-rendered counter; the app's bell mirrors it.
    // f95 renders the exact number ("69"), but tolerate capped forms
    // ("10+") that other XenForo skins emit.
    badgeCount:
        int.tryParse(
          RegExp(
                r'\d+',
              ).firstMatch(document.querySelector('.js-badge--alerts')?.attributes['data-badge'] ?? '')?.group(0) ??
              '',
        ) ??
        0,
  );
}

AlertEntry _parseAlertRow(Element row) {
  final main = row.querySelector('.contentRow-main');
  final content = main?.querySelector('a.fauxBlockLink-blockLink');

  // The action sentence is the loose text between the actor's username
  // anchor and the content link ("replied to the thread").
  String action = '';
  if (main != null) {
    final buffer = StringBuffer();
    for (final node in main.nodes) {
      if (node is Element && (node == content || node.querySelector('a.fauxBlockLink-blockLink') != null)) break;
      if (node is Text) buffer.write(node.text);
    }
    action = _clean(buffer.toString());
  }

  final avatarSrc = row.querySelector('.contentRow-figure img')?.attributes['src'];
  return AlertEntry(
    alertId: int.tryParse(row.attributes['data-alert-id'] ?? '') ?? 0,
    username: _clean(main?.querySelector('a.username')?.text ?? ''),
    avatarUrl: avatarSrc == null ? null : _absoluteUrl(avatarSrc),
    action: action,
    labels: content == null ? const [] : liftTitlePrefixes(content),
    title: _clean(content?.text ?? ''),
    url: _absoluteUrl(content?.attributes['href'] ?? ''),
    time: _clean(row.querySelector('time')?.text ?? ''),
    unread: row.querySelector('.user-alert--newIcon') != null,
  );
}

/// Parses a search results page (`/search/<id>/?q=...`, reachable by GET
/// after the search POST's 303).
ForumSearchPage parseSearchResults(String htmlSource) {
  final document = html_parser.parse(htmlSource);
  final (currentPage, totalPages) = _parsePageNav(document);

  final results = <ForumSearchResult>[];
  for (final row in document.querySelectorAll('.block-row .contentRow')) {
    final titleHeader = row.querySelector('.contentRow-title');
    final link = titleHeader?.querySelector('a[href]');
    if (titleHeader == null || link == null) continue;

    // Prefix labels render inside the title anchor; lift them out.
    final prefixes = liftTitlePrefixes(link);

    String forum = '';
    String date = '';
    for (final li in row.querySelectorAll('.contentRow-minor li')) {
      final text = _clean(li.text);
      if (text.startsWith('Forum:')) forum = _clean(li.querySelector('a')?.text ?? '');
      final time = li.querySelector('time');
      if (time != null) date = _clean(time.text);
    }

    results.add(
      ForumSearchResult(
        title: _clean(link.text),
        prefixes: prefixes,
        url: _absoluteUrl(link.attributes['href'] ?? ''),
        snippet: _clean(row.querySelector('.contentRow-snippet')?.text ?? ''),
        author: _clean(row.querySelector('.contentRow-minor .username')?.text ?? ''),
        date: date,
        forum: forum,
      ),
    );
  }

  return ForumSearchPage(
    results: results,
    currentPage: currentPage,
    totalPages: totalPages,
    searchUrl: _absoluteUrl(document.querySelector('meta[property="og:url"]')?.attributes['content'] ?? ''),
  );
}

/// Extracts the BBCode source from a post's edit page (`/posts/<id>/edit`
/// visited directly renders the full edit form).
///
/// The editor macro puts the BBCode textarea (`name="message"`) inside
/// `<noscript>`, whose content package:html keeps as raw text — so it
/// needs a fragment re-parse. The jsOnly `message_html` textarea holds
/// HTML and is never used.
String parseEditBbcode(String htmlSource) {
  final document = html_parser.parse(htmlSource);

  final direct = document.querySelector('textarea[name="message"]')?.text.trim() ?? '';
  if (direct.isNotEmpty) return direct;

  for (final noscript in document.querySelectorAll('noscript')) {
    final fragment = html_parser.parseFragment(noscript.text);
    final text = fragment.querySelector('textarea[name="message"]')?.text.trim() ?? '';
    if (text.isNotEmpty) return text;
  }

  return document.querySelector('input[data-bb-code]')?.attributes['value']?.trim() ?? '';
}

/// The page-level XenForo CSRF token, needed before POSTing when no parsed
/// page is at hand (e.g. initiating a search).
String parseCsrfToken(String htmlSource) {
  return html_parser.parse(htmlSource).documentElement?.attributes['data-csrf'] ?? '';
}

ForumPost _parsePost(Element post) {
  final source = post.attributes['data-content'] ?? post.attributes['id'] ?? '';

  // The "#21" permalink sits in the attribution header's opposite list.
  int number = 0;
  final header = post.querySelector('.message-attribution') ?? post.querySelector('header');
  for (final link in header?.querySelectorAll('a') ?? const <Element>[]) {
    final text = _clean(link.text);
    if (text.startsWith('#')) {
      number = int.tryParse(text.substring(1).replaceAll(',', '')) ?? 0;
      if (number != 0) break;
    }
  }

  return ForumPost(
    postId: _idFrom(source, _postIdPattern),
    number: number,
    author: _clean(post.attributes['data-author'] ?? ''),
    avatarUrl: _absoluteOrNull(post.querySelector('.message-avatar img')?.attributes['src']),
    authorUrl: _absoluteOrNull(
      post.querySelector('.message-avatar a')?.attributes['href'] ??
          post.querySelector('.message-name a')?.attributes['href'],
    ),
    // Scoped to the user cell: body mentions carry data-user-id too.
    authorId:
        int.tryParse(
          (post.querySelector('.message-name a[data-user-id]') ?? post.querySelector('.message-avatar a[data-user-id]'))
                  ?.attributes['data-user-id'] ??
              '',
        ) ??
        0,
    memberTitle: _clean(post.querySelector('.message-userTitle')?.text ?? ''),
    date: _clean(post.querySelector('.message-attribution-main time')?.text ?? ''),
    blocks: _parsePostBlocks(post.querySelector('.message-body .bbWrapper')),
    reactions: _parseReactionSummary(post.querySelector('.reactionsBar')),
    editUrl: _absoluteOrNull(post.querySelector('a.actionBar-action--edit')?.attributes['href']),
    deleteUrl: _absoluteOrNull(post.querySelector('a.actionBar-action--delete')?.attributes['href']),
  );
}

/// Splits a post body into ordered blocks: quotes and spoilers become
/// their own blocks, everything between them accumulates into rich runs.
List<ForumPostBlock> _parsePostBlocks(Element? body) {
  if (body == null) return const [];

  final blocks = <ForumPostBlock>[];
  final pending = <Node>[];

  void flushRich() {
    if (pending.isEmpty) return;
    final container = Element.tag('div');
    for (final node in pending) {
      container.append(node.clone(true));
    }
    pending.clear();
    final pieces = parseRichContent(container);
    if (pieces.isNotEmpty) blocks.add(ForumPostBlock(kind: PostBlockKind.rich, pieces: pieces));
  }

  for (final node in body.nodes) {
    if (node is Element && node.classes.contains('bbCodeBlock--quote')) {
      flushRich();
      final attribution = _clean(node.querySelector('.bbCodeBlock-title')?.text ?? '');
      final content = node.querySelector('.bbCodeBlock-expandContent') ?? node.querySelector('.bbCodeBlock-content');
      // The attribution link is the only source marker; hand-typed quotes
      // have none. Read the id out of the query so both the relative href
      // the site serves and the absolute one saved pages carry work.
      final jump = node.querySelector('.bbCodeBlock-sourceJump')?.attributes['href'] ?? '';
      blocks.add(
        ForumPostBlock(
          kind: PostBlockKind.quote,
          label: attribution.replaceFirst(RegExp(r' said:$'), ''),
          pieces: content == null ? const [] : parseRichContent(content),
          sourcePostId: int.tryParse(RegExp(r'[?&]id=(\d+)').firstMatch(jump)?.group(1) ?? ''),
        ),
      );
    } else if (node is Element && node.classes.contains('bbCodeSpoiler')) {
      flushRich();
      final title = _clean(node.querySelector('.bbCodeSpoiler-button-title')?.text ?? '');
      final content = node.querySelector('.bbCodeSpoiler-content');
      blocks.add(
        ForumPostBlock(
          kind: PostBlockKind.spoiler,
          label: title.isEmpty ? 'Spoiler' : title,
          pieces: content == null ? const [] : parseRichContent(content),
        ),
      );
    } else {
      pending.add(node);
    }
  }
  flushRich();

  return blocks;
}

PostReactionSummary? _parseReactionSummary(Element? bar) {
  if (bar == null) return null;
  final link = bar.querySelector('.reactionsBar-link');
  if (link == null) return null;

  // "A, B, C and 12,834 others" — combined count is names + others.
  final names = link.querySelectorAll('bdi').length;
  final others = _idFrom(_clean(link.text).replaceAll(',', ''), _othersPattern);

  return PostReactionSummary(
    topReactionIds: [
      for (final reaction in bar.querySelectorAll('.reactionSummary .reaction'))
        if (int.tryParse(reaction.attributes['data-reaction-id'] ?? '') != null)
          int.parse(reaction.attributes['data-reaction-id']!),
    ],
    count: names + others,
    url: _absoluteUrl(link.attributes['href'] ?? ''),
  );
}

/// Parses the reactions overlay (`/posts/<id>/reactions` visited as a
/// page): reaction tabs with counts, and up to 50 member rows.
ReactionsPage parseReactionsPage(String htmlSource) {
  final document = html_parser.parse(htmlSource);

  final tabs = <ReactionTab>[];
  for (final tab in document.querySelectorAll('.tabs-tab')) {
    // Reaction tabs carry tabs-tab--reactionN; other tab strips (the
    // thread's Discussion/Reviews tabs) don't and are skipped.
    final idMatch = _tabReactionPattern.firstMatch(tab.className);
    if (idMatch == null) continue;
    final countMatch = _tabCountPattern.firstMatch(_clean(tab.text).replaceAll(',', ''));
    tabs.add(
      ReactionTab(
        id: int.parse(idMatch.group(1)!),
        name: _clean(tab.querySelector('bdi')?.text ?? ''),
        count: int.tryParse(countMatch?.group(1) ?? '') ?? 0,
      ),
    );
  }

  return ReactionsPage(
    tabs: tabs,
    members: [
      for (final row in document.querySelectorAll('.js-reactionTabPanes .contentRow'))
        ReactionMember(
          username: _clean(row.querySelector('.contentRow-header')?.text ?? ''),
          avatarUrl: _absoluteOrNull(row.querySelector('.contentRow-figure img')?.attributes['src']),
          profileUrl: _absoluteOrNull(row.querySelector('.contentRow-header a')?.attributes['href']),
          memberTitle: _clean(row.querySelector('.userTitle')?.text ?? ''),
          reactionId:
              int.tryParse(row.querySelector('.contentRow-extra .reaction')?.attributes['data-reaction-id'] ?? '') ?? 0,
          date: _clean(row.querySelector('.contentRow-extra time')?.text ?? ''),
        ),
    ],
  );
}

/// Shared by thread and reaction pages too: XenForo's pageNav lists the
/// current page plus a neighborhood and the last page.
(int, int) _parsePageNav(Document document) {
  int current = 1;
  int total = 1;
  for (final li in document.querySelectorAll('.pageNav-page')) {
    final page = int.tryParse(_clean(li.text)) ?? 0;
    if (page <= 0) continue;
    if (total < page) total = page;
    if (li.classes.contains('pageNav-page--current')) current = page;
  }
  return (current, total);
}

ForumNode _parseNode(Element node) {
  final titleLink = node.querySelector('.node-title a');
  final url = _absoluteUrl(titleLink?.attributes['href'] ?? '');

  String threads = '';
  String messages = '';
  final stats = node.querySelector('.node-stats') ?? node.querySelector('.node-statsMeta');
  for (final dl in stats?.querySelectorAll('dl') ?? const <Element>[]) {
    final label = _clean(dl.querySelector('dt')?.text ?? '').toLowerCase();
    final value = _clean(dl.querySelector('dd')?.text ?? '');
    if (label == 'threads') threads = value;
    if (label == 'messages') messages = value;
  }

  ForumLastPost? lastPost;
  final extraTitle = node.querySelector('.node-extra-title');
  if (extraTitle != null) {
    lastPost = ForumLastPost(
      title: _clean(extraTitle.attributes['title'] ?? extraTitle.text),
      url: _absoluteUrl(extraTitle.attributes['href'] ?? ''),
      date: _clean(node.querySelector('.node-extra-date')?.text ?? ''),
      username: _clean(node.querySelector('.node-extra-user')?.text ?? ''),
    );
  }

  return ForumNode(
    id: _idFrom(node.className, _nodeIdPattern),
    title: _clean(titleLink?.text ?? ''),
    url: url,
    description: _clean(node.querySelector('.node-description')?.text ?? ''),
    threads: threads,
    messages: messages,
    unread: node.classes.contains('node--unread'),
    isLink: url.contains('/link-forums/'),
    lastPost: lastPost,
    subforums: [
      for (final sub in node.querySelectorAll('a.subNodeLink'))
        ForumNode(
          id: _idFrom(sub.className, _nodeIdPattern),
          title: _clean(sub.text),
          url: _absoluteUrl(sub.attributes['href'] ?? ''),
          isLink: sub.classes.contains('subNodeLink--link'),
        ),
    ],
  );
}

ForumThreadRow _parseThreadRow(Element row) {
  final titleCell = row.querySelector('.structItem-title');

  final prefixes = <ForumThreadPrefix>[];
  String title = '';
  String url = '';
  for (final link in titleCell?.querySelectorAll('a') ?? const <Element>[]) {
    if (link.classes.contains('labelLink')) {
      final id = _idFrom(link.attributes['href'] ?? '', _prefixIdPattern);
      if (id != 0) prefixes.add(ForumThreadPrefix(id: id, label: _clean(link.text)));
    } else {
      title = _clean(link.text);
      // Unread rows link to /unread; keep the canonical thread URL.
      url = _absoluteUrl((link.attributes['href'] ?? '').replaceFirst(RegExp(r'unread$'), ''));
    }
  }

  String replies = '';
  String views = '';
  for (final dl in row.querySelectorAll('.structItem-cell--meta dl')) {
    final label = _clean(dl.querySelector('dt')?.text ?? '').toLowerCase();
    final value = _clean(dl.querySelector('dd')?.text ?? '');
    if (label == 'replies') replies = value;
    if (label == 'views') views = value;
  }

  int lastPage = 1;
  for (final jump in row.querySelectorAll('.structItem-pageJump a')) {
    final page = int.tryParse(_clean(jump.text)) ?? 0;
    if (page > lastPage) lastPage = page;
  }

  final latest = row.querySelector('.structItem-cell--latest');

  return ForumThreadRow(
    threadId: _idFrom(row.className, _threadRowIdPattern),
    title: title,
    url: url,
    prefixes: prefixes,
    author: _clean(row.attributes['data-author'] ?? ''),
    authorAvatarUrl: _absoluteOrNull(row.querySelector('.structItem-cell--icon .avatar img')?.attributes['src']),
    startDate: _clean(row.querySelector('.structItem-startDate time')?.text ?? ''),
    sticky: row.querySelector('.structItem-status--sticky') != null,
    unread: row.classes.contains('is-unread'),
    replies: replies,
    views: views,
    lastPostDate: _clean(latest?.querySelector('time')?.text ?? ''),
    lastPostUser: _clean(latest?.querySelector('.username')?.text ?? ''),
    lastPage: lastPage,
  );
}

/// Lifts prefix chips out of a contentRow title anchor, mutating it so the
/// remaining text is the bare title. Thread prefixes render as `.label`
/// spans, but engine prefixes (Ren'Py, Unity, …) use bare `pre-*` classes —
/// both count. Shared with the profile parser's postings list.
List<String> liftTitlePrefixes(Element link) {
  final prefixes = <String>[];
  for (final child in link.children.toList()) {
    if (child.classes.contains('label-append')) {
      child.remove();
    } else if (child.classes.contains('label') || child.classes.any((c) => c.startsWith('pre-'))) {
      prefixes.add(_clean(child.text));
      child.remove();
    }
  }
  return prefixes;
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
