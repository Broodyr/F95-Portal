import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/forum.dart';
import '../services/auth_service.dart';
import '../services/forum_service.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import '../widgets/segmented_selector.dart';
import 'forum_thread_screen.dart';
import 'login_screen.dart';

typedef ForumSearcher = Future<ForumSearchPage> Function(String keywords, {bool titleOnly, String user, String order});
typedef ForumSearchPager = Future<ForumSearchPage> Function(String searchUrl, int page);

/// Forum search: keyword field with titles-only and sort options, post-level
/// results (snippet + attribution), load-more pagination, results open in
/// the thread viewer.
class ForumSearchScreen extends StatefulWidget {
  final ForumSearcher? searcher;
  final ForumSearchPager? searchPager;
  final FetchThreadPosts? fetchThreadPosts;
  final FetchReactions? fetchReactions;
  final ReactSender? reactSender;
  final ReplySender? replySender;

  const ForumSearchScreen({
    super.key,
    this.searcher,
    this.searchPager,
    this.fetchThreadPosts,
    this.fetchReactions,
    this.reactSender,
    this.replySender,
  });

  @override
  State<ForumSearchScreen> createState() => _ForumSearchScreenState();
}

class _ForumSearchScreenState extends State<ForumSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _titleOnly = false;
  String _order = 'relevance';

  ForumSearchPage? _page;
  final List<ForumSearchResult> _results = [];
  int _loadedPages = 0;
  bool _searching = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keywords = _controller.text.trim();
    if (keywords.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final run = widget.searcher ?? ForumService.search;
      final page = await run(keywords, titleOnly: _titleOnly, user: '', order: _order);
      if (!mounted) return;
      setState(() {
        _page = page;
        _results
          ..clear()
          ..addAll(page.results);
        _loadedPages = 1;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _searching = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (_scrollController.hasClients && _scrollController.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    final page = _page;
    if (page == null || _loadingMore || _loadedPages >= page.totalPages || page.searchUrl.isEmpty) return;
    _loadingMore = true;
    try {
      final run = widget.searchPager ?? ForumService.searchPage;
      final next = await run(page.searchUrl, _loadedPages + 1);
      if (!mounted) return;
      setState(() {
        _results.addAll(next.results);
        _loadedPages++;
      });
    } catch (_) {
      // Silent: scrolling further retries.
    } finally {
      _loadingMore = false;
    }
  }

  void _openResult(ForumSearchResult result) {
    // Result URLs carry a /post-N permalink; the viewer resolves it to the
    // right page and scrolls to the matched post.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadScreen(
          url: result.url,
          title: result.title,
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('forum-search-field'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search the forum…',
            hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
            border: InputBorder.none,
          ),
        ),
        actions: [IconButton(tooltip: 'Search', icon: const Icon(Icons.search, size: 20), onPressed: _search)],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                _buildToggle(colorScheme, 'Titles only', _titleOnly, () => setState(() => _titleOnly = !_titleOnly)),
                Container(
                  width: 1,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  color: Colors.grey[800],
                ),
                SegmentedSelector<String>(
                  dense: true,
                  shrinkWrap: true,
                  values: const ['relevance', 'date'],
                  isSelected: (order) => _order == order,
                  label: (order) => order == 'date' ? 'Newest' : 'Relevance',
                  onSelect: (order) => setState(() => _order = order),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildToggle(ColorScheme colorScheme, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.duration,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: AppAlphas.chipFill),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: selected ? colorScheme.primary : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: selected ? colorScheme.primary : Colors.grey[400],
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    // Guests can't search on f95 (the endpoint 403s outright); prompt for
    // the same in-app sign-in the rest of the forum uses.
    if (!AuthService.instance.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 32, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text('Searching requires an account', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            TextButton(
              onPressed: () async {
                final success = await Navigator.of(
                  context,
                ).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
                if (success == true && mounted) setState(() {});
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }
    if (_searching) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 32, color: Colors.grey[600]),
              const SizedBox(height: 8),
              Text("Couldn't search", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              const SizedBox(height: 4),
              // The underlying message distinguishes which stage failed.
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700], fontSize: 11),
              ),
              TextButton(onPressed: _search, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final page = _page;
    if (page == null) {
      return Center(
        child: Text('Search threads and posts', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('No results', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        for (final result in _results) _buildResultRow(colorScheme, result),
        if (_loadedPages < page.totalPages)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
      ],
    );
  }

  Widget _buildResultRow(ColorScheme colorScheme, ForumSearchResult result) {
    return InkWell(
      onTap: () => _openResult(result),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ForumAvatar(username: result.author, size: 26),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final prefix in result.prefixes)
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
                                child: Text(prefix, style: TextStyle(color: colorScheme.primary, fontSize: 9.5)),
                              ),
                            ),
                          ),
                        TextSpan(
                          text: result.title,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.snippet.isNotEmpty)
                    Text(
                      result.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11.5, height: 1.35),
                    ),
                  Text(
                    [
                      if (result.author.isNotEmpty) result.author,
                      if (result.date.isNotEmpty) result.date,
                      if (result.forum.isNotEmpty) result.forum,
                    ].join(' · '),
                    style: TextStyle(color: Colors.grey[600], fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
