import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/forum.dart';
import '../services/auth_service.dart';
import '../services/forum_service.dart';
import '../widgets/forum_node_row.dart';
import '../widgets/reactions_sheet.dart';
import 'alerts_screen.dart';
import 'bookmarks_screen.dart';
import 'forum_search_screen.dart';
import 'forum_thread_screen.dart';
import 'forum_threads_screen.dart';

typedef FetchForumIndex = Future<ForumIndex> Function();

/// The Forum tab: the site's forum directory as grouped category sections.
/// Link-forum redirect nodes (Trending Games etc.) are hidden — they don't
/// hold threads.
class ForumScreen extends StatefulWidget {
  /// The directory list's controller; MainApp watches it to hide/show the
  /// bottom nav and route the nav bar's pass-through drags here.
  final ScrollController? scrollController;

  final FetchForumIndex? fetchIndex;
  final FetchForumPage? fetchForumPage;
  final FetchThreadPosts? fetchThreadPosts;
  final FetchReactions? fetchReactions;
  final ThreadPoster? threadPoster;
  final ReactSender? reactSender;
  final ReplySender? replySender;
  final ForumSearcher? searcher;
  final ForumSearchPager? searchPager;
  final FetchBookmarks? fetchBookmarks;
  final BookmarkDeleter? bookmarkDeleter;
  final FetchAlerts? fetchAlerts;
  final AlertsAcknowledger? alertsAcknowledger;

  const ForumScreen({
    super.key,
    this.scrollController,
    this.fetchIndex,
    this.fetchForumPage,
    this.fetchThreadPosts,
    this.fetchReactions,
    this.threadPoster,
    this.reactSender,
    this.replySender,
    this.searcher,
    this.searchPager,
    this.fetchBookmarks,
    this.bookmarkDeleter,
    this.fetchAlerts,
    this.alertsAcknowledger,
  });

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> with WidgetsBindingObserver {
  /// Alerts only exist server-side, so a slow foreground poll keeps the
  /// bell honest during long sessions; login and app-resume cover the
  /// moments that usually matter.
  static const Duration _alertPollInterval = Duration(minutes: 5);

  ForumIndex? _index;
  bool _loading = true;
  String? _error;
  int _unreadAlerts = 0;
  Timer? _alertPollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshAlertCount();
    AuthService.instance.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    _alertPollTimer = Timer.periodic(_alertPollInterval, (_) => _refreshAlertCount(fresh: true));
  }

  @override
  void dispose() {
    _alertPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (AuthService.instance.isLoggedIn) {
      _refreshAlertCount(fresh: true);
    } else {
      setState(() => _unreadAlerts = 0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAlertCount(fresh: true);
  }

  /// Updates the bell badge from the alerts feed's first page; guests have
  /// no feed, and failures just leave the badge hidden.
  Future<void> _refreshAlertCount({bool fresh = false}) async {
    if (!kIsWeb && !AuthService.instance.isLoggedIn) return;
    try {
      if (fresh) ForumService.invalidateAccountPages();
      final fetch = widget.fetchAlerts ?? ForumService.fetchAlerts;
      final alerts = await fetch(page: 1);
      // The server's own counter, not our star count: the stars mean
      // "unread or new" and drift from what the site's bell displays.
      if (mounted) setState(() => _unreadAlerts = alerts.badgeCount);
    } catch (_) {
      // Badge only; the Alerts screen surfaces its own errors.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetch = widget.fetchIndex ?? ForumService.fetchIndex;
      final index = await fetch();
      if (!mounted) return;
      setState(() {
        _index = index;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openForum(ForumNode node) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadsScreen(
          node: node,
          fetchPage: widget.fetchForumPage,
          fetchThreadPosts: widget.fetchThreadPosts,
          fetchReactions: widget.fetchReactions,
          threadPoster: widget.threadPoster,
          reactSender: widget.reactSender,
          replySender: widget.replySender,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Forum',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text('f95zone.to', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Bookmarks',
                    icon: Icon(Icons.bookmark_border, size: 22, color: Colors.grey[400]),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookmarksScreen(
                          fetchBookmarks: widget.fetchBookmarks,
                          bookmarkDeleter: widget.bookmarkDeleter,
                          fetchThreadPosts: widget.fetchThreadPosts,
                          fetchReactions: widget.fetchReactions,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Alerts',
                    icon: Badge(
                      isLabelVisible: _unreadAlerts > 0,
                      label: Text(_unreadAlerts > 99 ? '99+' : '$_unreadAlerts'),
                      backgroundColor: colorScheme.primary,
                      child: Icon(Icons.notifications_none, size: 22, color: Colors.grey[400]),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlertsScreen(
                            fetchAlerts: widget.fetchAlerts,
                            alertsAcknowledger: widget.alertsAcknowledger,
                            fetchThreadPosts: widget.fetchThreadPosts,
                            fetchReactions: widget.fetchReactions,
                          ),
                        ),
                      );
                      // Reading or mark-all-read changes the count.
                      if (mounted) await _refreshAlertCount();
                    },
                  ),
                  IconButton(
                    tooltip: 'Search the forum',
                    icon: Icon(Icons.search, size: 22, color: Colors.grey[400]),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ForumSearchScreen(
                          searcher: widget.searcher,
                          searchPager: widget.searchPager,
                          fetchThreadPosts: widget.fetchThreadPosts,
                          fetchReactions: widget.fetchReactions,
                          reactSender: widget.reactSender,
                          replySender: widget.replySender,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(colorScheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final index = _index;
    if (_error != null || index == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 32, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text("Couldn't load the forum", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final sections = [
      for (final category in index.categories)
        (category: category, forums: category.forums.where((f) => !f.isLink).toList()),
    ].where((s) => s.forums.isNotEmpty).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ForumService.clearCache();
        await _load();
      },
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(12, 0, 12, 100 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
              child: Text(
                section.category.title,
                style: TextStyle(color: Colors.grey[500], fontSize: 11, letterSpacing: 0.4),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < section.forums.length; i++)
                    ForumNodeRow(
                      node: section.forums[i],
                      showDivider: i < section.forums.length - 1,
                      onTap: () => _openForum(section.forums[i]),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
