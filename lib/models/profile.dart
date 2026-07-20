// Models for XenForo member profile pages: the header identity block, the
// profile-post wall (with nested comments), the recent-content postings
// list, and the About tab's fields.

class ProfileComment {
  final int id;
  final String author;
  final String? avatarUrl;

  /// The commenter's member page URL; lets the viewer open their profile.
  final String? authorUrl;
  final String body;
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
  final String body;
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

  /// Canonical member URL; base for the recent-content and about fetches.
  final String profileUrl;
  final List<ProfilePost> wallPosts;

  /// Pre-filled only when the postings pane happens to be inline (it lazy
  /// loads on the live site); otherwise fetched separately.
  final List<ProfilePosting> postings;
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
    this.postings = const [],
    this.csrfToken = '',
    this.wallPostUrl,
  });
}
