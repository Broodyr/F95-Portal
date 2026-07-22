// Models for XenForo member profile pages: the header identity block, the
// profile-post wall (with nested comments), the recent-content postings
// list, and the About tab's fields.

import 'thread_page.dart';

class ProfileComment {
  final int id;
  final String author;
  final String? avatarUrl;

  /// The commenter's member page URL; lets the viewer open their profile.
  final String? authorUrl;

  /// The comment as plain text, for anything that wants a string.
  final String body;

  /// The same content as inline pieces — links, emphasis, line breaks — so
  /// it renders like a forum post rather than as flattened text. Empty only
  /// when built by hand; [body] is the fallback then.
  final List<RichPiece> rich;

  final String date;

  /// Edit action; the site renders it only on the viewer's own comments.
  final String? editUrl;

  /// Delete action; rendered alongside [editUrl] on the viewer's own comments.
  final String? deleteUrl;

  const ProfileComment({
    this.id = 0,
    required this.author,
    this.avatarUrl,
    this.authorUrl,
    required this.body,
    this.rich = const [],
    this.date = '',
    this.editUrl,
    this.deleteUrl,
  });
}

class ProfilePost {
  final int id;
  final String author;
  final String? avatarUrl;

  /// The author's member page URL; lets the viewer open their profile.
  final String? authorUrl;
  final String date;

  /// The post as plain text, for anything that wants a string.
  final String body;

  /// The same content as inline pieces; see [ProfileComment.rich].
  final List<RichPiece> rich;

  final List<ProfileComment> comments;

  /// Add-comment form action; only rendered for viewers who can comment.
  final String? commentUrl;

  /// Edit action; the site renders it only on the viewer's own posts.
  final String? editUrl;

  /// Delete action; rendered alongside [editUrl] on the viewer's own posts.
  final String? deleteUrl;

  const ProfilePost({
    this.id = 0,
    required this.author,
    this.avatarUrl,
    this.authorUrl,
    this.date = '',
    required this.body,
    this.rich = const [],
    this.comments = const [],
    this.commentUrl,
    this.editUrl,
    this.deleteUrl,
  });
}

class ProfilePosting {
  final String title;
  final List<String> prefixes;

  /// Thread URL, usually with a /post-N suffix pointing at the exact post.
  final String url;
  final String snippet;

  /// "Post #29" for replies, "Thread" for threads the member started.
  final String postInfo;

  /// Reply count, only present on "Thread" rows.
  final String replies;
  final String date;
  final String forum;

  const ProfilePosting({
    required this.title,
    this.prefixes = const [],
    required this.url,
    this.snippet = '',
    this.postInfo = '',
    this.replies = '',
    this.date = '',
    this.forum = '',
  });
}

/// One page of a member's full postings, as served by the "See more" query
/// (`/search/member?user_id=N`, which redirects to a normal search results
/// page). Carries the pagination the capped in-profile pane lacks, so the
/// Postings tab can load a page at a time as the reader scrolls.
class ProfilePostingsPage {
  final List<ProfilePosting> postings;
  final int currentPage;
  final int totalPages;

  /// The GET-able results URL (`/search/<id>/?c[users]=...`) further pages
  /// append `&page=N` to. Empty when the page carried no canonical URL.
  final String searchUrl;

  const ProfilePostingsPage({
    this.postings = const [],
    this.currentPage = 1,
    this.totalPages = 1,
    this.searchUrl = '',
  });
}

class ProfileAbout {
  /// The user-set bio as plain text, unparsed.
  final String bio;
  final String birthday;
  final String website;
  final String location;

  const ProfileAbout({this.bio = '', this.birthday = '', this.website = '', this.location = ''});

  bool get isEmpty => bio.isEmpty && birthday.isEmpty && website.isEmpty && location.isEmpty;
}

class ProfilePage {
  final String username;
  final String memberTitle;
  final String? avatarUrl;

  /// The untouched avatar upload behind [avatarUrl]'s downscaled variant,
  /// for opening full size. Null when the member has never set one.
  final String? avatarFullUrl;
  final String messages;
  final String joined;
  final String lastSeen;

  /// Canonical member URL; base for the About tab fetch, and the base the
  /// wall pages off (`<profileUrl>page-N`).
  final String profileUrl;
  final List<ProfilePost> wallPosts;

  /// The profile-post wall's own pagination. The wall pages independently of
  /// the member page — `/members/<slug>.<id>/page-N` serves page N of the
  /// feed — so [wallPosts] is only the page this parse landed on. [wallPage]
  /// is that page; [wallTotalPages] the count the pager offers (1 when the
  /// wall fits on one page and renders no nav).
  final int wallPage;
  final int wallTotalPages;

  /// The member page's own recent-content pane, when rendered inline (it lazy
  /// loads on the live site) — a capped preview. The Postings tab shows the
  /// fuller paginated query at [postingsSearchUrl] instead, so this is mostly
  /// a faithful record of the page rather than what that tab reads.
  final List<ProfilePosting> postings;

  /// The "See more" / "Find all content" query for this member
  /// (`/search/member?user_id=N`); the Postings tab loads its paginated
  /// results rather than the capped in-profile pane. Null when the page
  /// carried no such link (guests, or an unrecognized layout).
  final String? postingsSearchUrl;
  final String csrfToken;

  /// Wall composer form action; only rendered for viewers who can post.
  final String? wallPostUrl;

  const ProfilePage({
    required this.username,
    this.memberTitle = '',
    this.avatarUrl,
    this.avatarFullUrl,
    this.messages = '',
    this.joined = '',
    this.lastSeen = '',
    this.profileUrl = '',
    this.wallPosts = const [],
    this.wallPage = 1,
    this.wallTotalPages = 1,
    this.postings = const [],
    this.postingsSearchUrl,
    this.csrfToken = '',
    this.wallPostUrl,
  });
}
