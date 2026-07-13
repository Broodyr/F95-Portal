/// Parsed forum structures: the directory (index) of categories and
/// forums, a single forum's page (subforums + thread rows), and a
/// thread's posts. Counts stay as the site's own abbreviated strings
/// ("4K", "2M") since they're display-only.
library;

import 'thread_page.dart';

/// The latest-post teaser shown on a forum node ("Hi everyone · Esssa47").
class ForumLastPost {
  final String title;
  final String url;
  final String date;
  final String username;

  const ForumLastPost({required this.title, this.url = '', this.date = '', this.username = ''});
}

/// One forum in the directory or a subforum block. [isLink] marks
/// redirect nodes (`link-forums/`, e.g. Trending Games) that navigate
/// elsewhere instead of holding threads.
class ForumNode {
  final int id;
  final String title;
  final String url;
  final String description;
  final String threads;
  final String messages;
  final bool unread;
  final bool isLink;
  final ForumLastPost? lastPost;
  final List<ForumNode> subforums;

  const ForumNode({
    required this.id,
    required this.title,
    required this.url,
    this.description = '',
    this.threads = '',
    this.messages = '',
    this.unread = false,
    this.isLink = false,
    this.lastPost,
    this.subforums = const [],
  });
}

/// A titled group of forums on the index page ("Adult Games", "Discussion").
class ForumCategory {
  final int id;
  final String title;
  final List<ForumNode> forums;

  const ForumCategory({required this.id, required this.title, this.forums = const []});
}

/// The forum directory: every category with its forums.
class ForumIndex {
  final List<ForumCategory> categories;

  const ForumIndex({this.categories = const []});
}

/// A prefix label on a thread row ("README", "Ren'Py", "Completed").
class ForumThreadPrefix {
  final int id;
  final String label;

  const ForumThreadPrefix({required this.id, required this.label});
}

/// One row in a forum's thread list.
class ForumThreadRow {
  final int threadId;
  final String title;
  final String url;
  final List<ForumThreadPrefix> prefixes;
  final String author;
  final String? authorAvatarUrl;
  final String startDate;
  final bool sticky;
  final bool unread;
  final String replies;
  final String views;
  final String lastPostDate;
  final String lastPostUser;

  /// Highest page number advertised by the row's page-jump links; 1 for
  /// single-page threads.
  final int lastPage;

  const ForumThreadRow({
    required this.threadId,
    required this.title,
    required this.url,
    this.prefixes = const [],
    this.author = '',
    this.authorAvatarUrl,
    this.startDate = '',
    this.sticky = false,
    this.unread = false,
    this.replies = '',
    this.views = '',
    this.lastPostDate = '',
    this.lastPostUser = '',
    this.lastPage = 1,
  });
}

enum PostBlockKind { rich, quote, spoiler }

/// One block of a post body. Quote and spoiler blocks carry their
/// attribution/title in [label]; rich blocks are plain inline content.
class ForumPostBlock {
  final PostBlockKind kind;
  final String label;
  final List<RichPiece> pieces;

  const ForumPostBlock({required this.kind, this.label = '', this.pieces = const []});
}

/// The inline reaction summary on a post: the top reaction ids (at most
/// three, as rendered by the site) and the combined count across all
/// reaction types. Per-reaction counts live behind [url].
class PostReactionSummary {
  final List<int> topReactionIds;
  final int count;
  final String url;

  const PostReactionSummary({this.topReactionIds = const [], this.count = 0, this.url = ''});
}

/// One post in a thread's post loop.
class ForumPost {
  final int postId;

  /// Position in the thread ("#21" → 21); 0 when unparsed.
  final int number;
  final String author;
  final String? avatarUrl;

  /// The author's member page URL; lets the viewer open their profile.
  final String? authorUrl;
  final String memberTitle;
  final String date;
  final List<ForumPostBlock> blocks;
  final PostReactionSummary? reactions;

  /// The action-bar Edit link; present only on the viewer's own posts.
  final String? editUrl;

  const ForumPost({
    required this.postId,
    this.number = 0,
    this.author = '',
    this.avatarUrl,
    this.authorUrl,
    this.memberTitle = '',
    this.date = '',
    this.blocks = const [],
    this.reactions,
    this.editUrl,
  });
}

/// One row of forum search results (post-level, with a snippet).
class ForumSearchResult {
  final String title;
  final List<String> prefixes;

  /// Thread URL, usually with a `/post-N` permalink suffix.
  final String url;
  final String snippet;
  final String author;
  final String date;
  final String forum;

  const ForumSearchResult({
    required this.title,
    required this.url,
    this.prefixes = const [],
    this.snippet = '',
    this.author = '',
    this.date = '',
    this.forum = '',
  });
}

/// A page of search results plus the GET-able URL for further pages.
class ForumSearchPage {
  final List<ForumSearchResult> results;
  final int currentPage;
  final int totalPages;
  final String searchUrl;

  const ForumSearchPage({this.results = const [], this.currentPage = 1, this.totalPages = 1, this.searchUrl = ''});
}

/// One page of a thread's posts.
class ThreadPostsPage {
  final String title;
  final List<ForumPost> posts;
  final int currentPage;
  final int totalPages;

  /// Page-level XenForo CSRF token (`<html data-csrf>`); present for
  /// guests too, but only useful with a session.
  final String csrfToken;

  /// The quick-reply form's action URL; null when the page was rendered
  /// for a guest (or the thread is locked), which is the posting gate.
  final String? replyUrl;

  const ThreadPostsPage({
    this.title = '',
    this.posts = const [],
    this.currentPage = 1,
    this.totalPages = 1,
    this.csrfToken = '',
    this.replyUrl,
  });
}

/// One tab of the reactions overlay: a reaction type and how many members
/// gave it. Id 0 is the synthetic "All" tab.
class ReactionTab {
  final int id;
  final String name;
  final int count;

  const ReactionTab({required this.id, required this.name, required this.count});
}

/// One member row in the reactions overlay.
class ReactionMember {
  final String username;
  final String? avatarUrl;
  final String memberTitle;
  final int reactionId;
  final String date;

  const ReactionMember({
    required this.username,
    this.avatarUrl,
    this.memberTitle = '',
    this.reactionId = 0,
    this.date = '',
  });
}

/// The parsed reactions overlay for one post: per-reaction tabs with
/// counts, and the member list (each row tagged with its reaction so the
/// sheet can filter client-side).
class ReactionsPage {
  final List<ReactionTab> tabs;
  final List<ReactionMember> members;

  const ReactionsPage({this.tabs = const [], this.members = const []});
}

/// A single forum's page: its own title, the subforum block, thread rows,
/// and pagination.
class ForumPage {
  final String title;
  final List<ForumNode> subforums;
  final List<ForumThreadRow> threads;
  final int currentPage;
  final int totalPages;

  /// The "Post thread" button's URL; null when the viewer can't create
  /// threads here.
  final String? postThreadUrl;

  /// Page-level XenForo CSRF token (`<html data-csrf>`).
  final String csrfToken;

  const ForumPage({
    this.title = '',
    this.subforums = const [],
    this.threads = const [],
    this.currentPage = 1,
    this.totalPages = 1,
    this.postThreadUrl,
    this.csrfToken = '',
  });
}
