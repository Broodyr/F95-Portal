/// Parsed account pages: the bookmarks list (`/account/bookmarks`) and the
/// alerts feed (`/account/alerts`). Dates and times stay as the site's own
/// display strings ("Apr 8, 2026", "13 minutes ago") since they're
/// display-only.
library;

/// One saved bookmark: a whole thread or a single post within one.
class BookmarkEntry {
  final String title;

  /// True for "Post in thread '…'" rows, false for "Thread '…'" rows.
  final bool isPost;

  /// The bookmarked content's URL (thread page or post permalink).
  final String url;
  final String snippet;

  /// The bookmarked post's author.
  final String author;
  final String? avatarUrl;

  /// When the bookmark was created ("Apr 8, 2026").
  final String date;

  /// The XenForo bookmark endpoint (`/posts/N/bookmark`); posting delete=1
  /// to it removes the bookmark.
  final String bookmarkUrl;

  const BookmarkEntry({
    required this.title,
    required this.url,
    this.isPost = false,
    this.snippet = '',
    this.author = '',
    this.avatarUrl,
    this.date = '',
    this.bookmarkUrl = '',
  });
}

/// One page of the bookmarks list.
class BookmarksPage {
  final List<BookmarkEntry> entries;
  final int currentPage;
  final int totalPages;

  /// Page-level XenForo CSRF token, needed to delete bookmarks.
  final String csrfToken;

  const BookmarksPage({this.entries = const [], this.currentPage = 1, this.totalPages = 1, this.csrfToken = ''});
}

/// The Alert Improvements read-marking preferences on the account
/// preferences page. Unchecked (the f95 default) means viewing that
/// surface marks its alerts read.
class AlertPreferences {
  final bool popupSkipsMarkRead;
  final bool pageSkipsMarkRead;

  const AlertPreferences({this.popupSkipsMarkRead = false, this.pageSkipsMarkRead = false});
}

/// One alert row: an actor, what they did, and the content it targets.
class AlertEntry {
  final int alertId;
  final String username;
  final String? avatarUrl;

  /// The action sentence between actor and content ("replied to the thread").
  final String action;

  /// The target content's bare title, with its prefix labels lifted out.
  final String title;

  /// Prefix labels rendered inside the content link ("Unity", "Completed").
  final List<String> labels;

  /// The target content's URL (usually a post permalink).
  final String url;
  final String time;
  final bool unread;

  const AlertEntry({
    required this.alertId,
    this.username = '',
    this.avatarUrl,
    this.action = '',
    this.title = '',
    this.labels = const [],
    this.url = '',
    this.time = '',
    this.unread = false,
  });
}

/// Alerts under one of the page's date headers ("Today", "Yesterday").
class AlertGroup {
  final String title;
  final List<AlertEntry> alerts;

  const AlertGroup({this.title = '', this.alerts = const []});
}

/// One page of the alerts feed.
class AlertsPage {
  final List<AlertGroup> groups;
  final int currentPage;
  final int totalPages;

  /// Page-level XenForo CSRF token, needed to POST the mark-read action.
  final String csrfToken;

  /// The server's own bell counter (nav `data-badge`, alerts_unviewed).
  /// This is what the site's bell displays — the row stars encode a
  /// different notion ("unread or new"), so the app's bell shows this.
  final int badgeCount;

  const AlertsPage({
    this.groups = const [],
    this.currentPage = 1,
    this.totalPages = 1,
    this.csrfToken = '',
    this.badgeCount = 0,
  });

  int get unreadCount => [
    for (final group in groups)
      for (final alert in group.alerts)
        if (alert.unread) alert,
  ].length;
}
