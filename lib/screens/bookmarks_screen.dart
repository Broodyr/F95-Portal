import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../constants.dart';
import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/forum_service.dart';
import '../services/site_error.dart';
import '../services/thread_page_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_action_sheet.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_view.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import '../widgets/segmented_selector.dart';
import 'forum_thread_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

typedef FetchBookmarks = Future<BookmarksPage> Function({int page});
typedef BookmarkDeleter = Future<void> Function(String bookmarkUrl, String csrfToken);

enum _BookmarkFilter { all, threads, posts }

/// The account bookmarks list: every saved thread/post with its snippet
/// and author, a thread/post filter, load-more pagination, and per-row
/// removal. Rows open in the thread viewer.
class BookmarksScreen extends StatefulWidget {
  final FetchBookmarks? fetchBookmarks;
  final BookmarkDeleter? bookmarkDeleter;
  final FetchThreadPosts? fetchThreadPosts;
  final FetchReactions? fetchReactions;
  final Future<bool> Function(Uri uri)? urlLauncher;

  const BookmarksScreen({
    super.key,
    this.fetchBookmarks,
    this.bookmarkDeleter,
    this.fetchThreadPosts,
    this.fetchReactions,
    this.urlLauncher,
  });

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final ScrollController _scrollController = ScrollController();

  BookmarksPage? _page;
  final List<BookmarkEntry> _entries = [];
  int _loadedPages = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// A 403 or 404 will not change on a second ask, so the view drops Retry.
  bool _errorRetryable = true;
  _BookmarkFilter _filter = _BookmarkFilter.all;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    // The web build runs on mock data without a session.
    if (kIsWeb || AuthService.instance.isLoggedIn) _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Account feeds change out from under the app (a bookmark made moments
    // ago in the details sheet, or on another device): always fetch live.
    ForumService.invalidateAccountPages();
    setState(() {
      _loading = _page == null;
      _error = null;
    });
    try {
      final fetch = widget.fetchBookmarks ?? ForumService.fetchBookmarks;
      final page = await fetch(page: 1);
      if (!mounted) return;
      setState(() {
        _page = page;
        _entries
          ..clear()
          ..addAll(page.entries);
        _loadedPages = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _errorRetryable = e is! ContentUnavailableException;
        _loading = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (_scrollController.hasClients && _scrollController.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    final page = _page;
    if (page == null || _loadingMore || _loadedPages >= page.totalPages) return;
    _loadingMore = true;
    try {
      final fetch = widget.fetchBookmarks ?? ForumService.fetchBookmarks;
      final next = await fetch(page: _loadedPages + 1);
      if (!mounted) return;
      setState(() {
        _entries.addAll(next.entries);
        _loadedPages++;
      });
    } catch (_) {
      // Silent: scrolling further retries.
    } finally {
      _loadingMore = false;
    }
  }

  /// The row's long-press menu — the list has no visible per-row control now,
  /// the way the alerts feed works. Opening externally and removal both live
  /// here; a bookmark can also be cleared from the post it points at.
  Future<void> _showRowMenu(BookmarkEntry entry, BuildContext rowContext) async {
    HapticFeedback.vibrate();
    await showAppActionSheet(
      rowContext,
      anchorRect: menuAnchorRect(rowContext),
      anchorRadius: BorderRadius.circular(12),
      actions: [
        if (entry.url.isNotEmpty)
          AppSheetAction(icon: Icons.open_in_browser, label: 'Open in browser', onTap: () => _openInBrowser(entry)),
        if (entry.bookmarkUrl.isNotEmpty)
          AppSheetAction(
            icon: Icons.bookmark_remove_outlined,
            label: 'Remove bookmark',
            destructive: true,
            onTap: () => _delete(entry),
          ),
      ],
    );
  }

  Future<void> _openInBrowser(BookmarkEntry entry) async {
    if (entry.url.isEmpty) return;
    final launch =
        widget.urlLauncher ?? (uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    await launch(Uri.parse(entry.url));
  }

  /// Removes the row optimistically and defers the actual delete until the
  /// undo toast closes, so Undo takes it back with nothing having been sent.
  /// A failed delete restores the row with an error toast.
  void _delete(BookmarkEntry entry) {
    final page = _page;
    if (page == null || entry.bookmarkUrl.isEmpty) return;

    final int index = _entries.indexOf(entry);
    if (index < 0) return;
    setState(() => _entries.remove(entry));

    bool undone = false;
    final controller = AppToast.show(
      context,
      'Bookmark removed',
      actionLabel: 'Undo',
      onAction: () {
        undone = true;
        if (mounted) setState(() => _entries.insert(index.clamp(0, _entries.length), entry));
      },
    );

    controller.closed.then((_) async {
      if (undone) return;
      try {
        final delete =
            widget.bookmarkDeleter ??
            (url, csrf) => ThreadPageService.postAction(url, csrf, fields: const {'delete': '1'});
        await delete(entry.bookmarkUrl, page.csrfToken);
        ForumService.clearCache();
      } catch (e) {
        if (!mounted) return;
        setState(() => _entries.insert(index.clamp(0, _entries.length), entry));
        AppToast.show(context, '$e', error: true);
      }
    });
  }

  void _openEntry(BookmarkEntry entry) {
    // A bookmarked profile post opens the member's wall jumped to it, not the
    // thread viewer; the permalink's redirect resolves which wall page it's on.
    if (isProfilePostUrl(entry.url)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(url: entry.url)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadScreen(
          url: entry.url,
          title: entry.title,
          fetchPosts: widget.fetchThreadPosts,
          fetchReactions: widget.fetchReactions,
        ),
      ),
    );
  }

  List<BookmarkEntry> get _visibleEntries => [
    for (final entry in _entries)
      if (_filter == _BookmarkFilter.all || (_filter == _BookmarkFilter.posts ? entry.isPost : !entry.isPost)) entry,
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks', style: TextStyle(fontSize: 16))),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                SegmentedSelector<_BookmarkFilter>(
                  dense: true,
                  shrinkWrap: true,
                  values: _BookmarkFilter.values,
                  isSelected: (filter) => _filter == filter,
                  label: (filter) => switch (filter) {
                    _BookmarkFilter.all => 'All',
                    _BookmarkFilter.threads => 'Threads',
                    _BookmarkFilter.posts => 'Posts',
                  },
                  onSelect: (filter) => setState(() => _filter = filter),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (!kIsWeb && !AuthService.instance.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 32, color: AppColors.of(context).mutedForeground),
            const SizedBox(height: 8),
            Text(
              'Bookmarks require an account',
              style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 13),
            ),
            TextButton(
              onPressed: () async {
                final success = await Navigator.of(
                  context,
                ).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
                if (success == true && mounted) await _load();
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return ErrorView(headline: "Couldn't load bookmarks", detail: _error, onRetry: _errorRetryable ? _load : null);
    }

    final entries = _visibleEntries;
    if (entries.isEmpty) {
      return Center(
        child: Text('No bookmarks yet', style: TextStyle(color: AppColors.of(context).hintText, fontSize: 13)),
      );
    }

    final page = _page;
    return RefreshIndicator(
      onRefresh: _load,
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          for (final entry in entries) _buildRow(colorScheme, entry),
          if (page != null && _loadedPages < page.totalPages)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(ColorScheme colorScheme, BookmarkEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // A Builder so the long-press menu can anchor its highlight to the row.
      child: Builder(
        builder: (rowContext) => InkWell(
          onTap: () => _openEntry(entry),
          onLongPress: () => _showRowMenu(entry, rowContext),
          // The menu fires its own haptic; the InkWell's would double it.
          enableFeedback: false,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: AppAlphas.chipFill),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ForumAvatar(username: entry.author, avatarUrl: entry.avatarUrl, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Just the kind badge now: removal and open-externally
                      // moved to the row's long-press menu, freeing the width the
                      // overflow used to reserve.
                      Row(
                        children: [
                          Icon(
                            entry.isPost ? Icons.subdirectory_arrow_right : Icons.forum_outlined,
                            size: 12,
                            color: AppColors.of(context).hintText,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            entry.isPost ? 'POST' : 'THREAD',
                            style: TextStyle(color: AppColors.of(context).hintText, fontSize: 9.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.of(context).brightText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (entry.snippet.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            entry.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11.5, height: 1.35),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (entry.author.isNotEmpty) entry.author,
                            if (entry.date.isNotEmpty) 'bookmarked ${entry.date}',
                          ].join(' · '),
                          style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
