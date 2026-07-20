import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/forum.dart';
import '../services/forum_service.dart';
import '../services/site_error.dart';
import '../theme/app_colors.dart';
import '../widgets/error_view.dart';
import '../widgets/forum_composer.dart';
import '../widgets/forum_node_row.dart';
import '../widgets/glass_fab.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import 'forum_thread_screen.dart';

typedef FetchForumPage = Future<ForumPage> Function(String url, {int page});
typedef ThreadPoster =
    Future<void> Function(String url, String csrfToken, {required String title, required String message});

/// One forum's thread list: the subforum block above (same row style as
/// the directory), a splitter, then infinite-scrolling thread rows.
class ForumThreadsScreen extends StatefulWidget {
  final ForumNode node;
  final FetchForumPage? fetchPage;
  final FetchThreadPosts? fetchThreadPosts;
  final FetchReactions? fetchReactions;
  final ThreadPoster? threadPoster;
  final ReactSender? reactSender;
  final ReplySender? replySender;

  const ForumThreadsScreen({
    super.key,
    required this.node,
    this.fetchPage,
    this.fetchThreadPosts,
    this.fetchReactions,
    this.threadPoster,
    this.reactSender,
    this.replySender,
  });

  @override
  State<ForumThreadsScreen> createState() => _ForumThreadsScreenState();
}

class _ForumThreadsScreenState extends State<ForumThreadsScreen> {
  final ScrollController _scrollController = ScrollController();
  ForumPage? _firstPage;
  final List<ForumThreadRow> _threads = [];
  int _loadedPages = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// A 403 or 404 will not change on a second ask, so the view drops Retry.
  bool _errorRetryable = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  FetchForumPage get _fetch => widget.fetchPage ?? ForumService.fetchForumPage;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _fetch(widget.node.url);
      if (!mounted) return;
      setState(() {
        _firstPage = page;
        _threads
          ..clear()
          ..addAll(page.threads);
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
    if (_scrollController.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    final first = _firstPage;
    if (first == null || _loadingMore || _loadedPages >= first.totalPages) return;
    _loadingMore = true;
    try {
      final page = await _fetch(widget.node.url, page: _loadedPages + 1);
      if (!mounted) return;
      setState(() {
        // Sticky rows repeat on every page; only page 1 keeps them.
        _threads.addAll(page.threads.where((t) => !t.sticky));
        _loadedPages++;
      });
    } catch (_) {
      // Silent: scrolling further retries.
    } finally {
      _loadingMore = false;
    }
  }

  void _openThread(ForumThreadRow row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadScreen(
          url: row.url,
          title: row.title,
          fetchPosts: widget.fetchThreadPosts,
          fetchReactions: widget.fetchReactions,
          reactSender: widget.reactSender,
          replySender: widget.replySender,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final page = _firstPage;
    final title = (page?.title.isNotEmpty ?? false) ? page!.title : widget.node.title;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            // Keyed off the node, not [title]: this echoes the row that was
            // tapped, and the page's own title can differ from it. Primary,
            // like that row — the appbar's functional icons are plain white.
            Icon(ForumNodeRow.iconFor(widget.node.title), size: 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                  if (widget.node.threads.isNotEmpty)
                    Text(
                      '${widget.node.threads} threads',
                      style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          _buildBody(colorScheme, page),
          // Same spot as the browse tab's search FAB in its nav-hidden
          // position — the bottom nav never shows on pushed screens.
          if (page?.postThreadUrl != null)
            Positioned(
              right: 32,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: GlassFab(
                icon: Icons.edit,
                tooltip: 'New thread',
                scrollController: _scrollController,
                onPressed: _composeThread,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _composeThread() async {
    final page = _firstPage;
    final postThreadUrl = page?.postThreadUrl;
    if (page == null || postThreadUrl == null) return;

    final posted = await ForumComposer.show(
      context,
      heading: 'New thread',
      submitLabel: 'Post thread',
      withTitle: true,
      onSubmit: (title, message) {
        final send = widget.threadPoster ?? ForumService.postThread;
        return send(postThreadUrl, page.csrfToken, title: title, message: message);
      },
    );
    if (posted && mounted) {
      ForumService.clearCache();
      await _load();
    }
  }

  Widget _buildBody(ColorScheme colorScheme, ForumPage? page) {
    if (_loading) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null || page == null) {
      return ErrorView(headline: "Couldn't load the forum", detail: _error, onRetry: _errorRetryable ? _load : null);
    }

    final subforums = [
      for (final sub in page.subforums)
        if (!sub.isLink) sub,
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ForumService.clearCache();
        await _load();
      },
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(12, 10, 12, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          if (subforums.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: AppAlphas.chipFill),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < subforums.length; i++)
                    ForumNodeRow(
                      node: subforums[i],
                      compact: true,
                      showDivider: i < subforums.length - 1,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ForumThreadsScreen(
                            node: subforums[i],
                            fetchPage: widget.fetchPage,
                            fetchThreadPosts: widget.fetchThreadPosts,
                            fetchReactions: widget.fetchReactions,
                            threadPoster: widget.threadPoster,
                            reactSender: widget.reactSender,
                            replySender: widget.replySender,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Row(
                children: [
                  Text(
                    'Threads',
                    style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11, letterSpacing: 0.4),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(height: 1, color: colorScheme.onSurface.withValues(alpha: 0.08))),
                ],
              ),
            ),
          ],
          for (final row in _threads) _buildThreadRow(colorScheme, row),
          if (_loadedPages < page.totalPages)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
    );
  }

  Widget _buildThreadRow(ColorScheme colorScheme, ForumThreadRow row) {
    return InkWell(
      onTap: () => _openThread(row),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (row.sticky)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.push_pin, size: 15, color: colorScheme.primary),
              )
            else
              ForumAvatar(username: row.author, avatarUrl: row.authorAvatarUrl, size: 26),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final prefix in row.prefixes)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(prefix.label, style: TextStyle(color: colorScheme.primary, fontSize: 9.5)),
                              ),
                            ),
                          ),
                        TextSpan(
                          text: row.title,
                          style: TextStyle(
                            color: row.unread ? AppColors.of(context).brightText : AppColors.of(context).bodyText,
                            fontSize: 12.5,
                            fontWeight: row.unread ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (row.author.isNotEmpty) row.author,
                      if (row.replies.isNotEmpty) '${row.replies} replies',
                      if (row.lastPostDate.isNotEmpty) row.lastPostDate,
                    ].join(' · '),
                    style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            if (row.unread)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
