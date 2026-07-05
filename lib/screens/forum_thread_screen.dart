import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../models/forum.dart';
import '../services/forum_service.dart';
import 'login_screen.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import '../widgets/rich_spoiler_text.dart';
import '../widgets/sliding_reveal.dart';

typedef FetchThreadPosts = Future<ThreadPostsPage> Function(String url, {int page});

/// Full-screen light thread viewer: the post loop as-is (author, avatar,
/// body with quotes/spoilers, reaction summary) with page pills at the
/// bottom. Read-only for now; react/reply actions come later.
class ForumThreadScreen extends StatefulWidget {
  final String url;
  final String title;
  final int initialPage;
  final FetchThreadPosts? fetchPosts;
  final FetchReactions? fetchReactions;
  final Future<bool> Function(Uri uri)? urlLauncher;

  const ForumThreadScreen({
    super.key,
    required this.url,
    required this.title,
    this.initialPage = 1,
    this.fetchPosts,
    this.fetchReactions,
    this.urlLauncher,
  });

  @override
  State<ForumThreadScreen> createState() => _ForumThreadScreenState();
}

class _ForumThreadScreenState extends State<ForumThreadScreen> {
  final ScrollController _scrollController = ScrollController();
  ThreadPostsPage? _page;
  int _pageNumber = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pageNumber = widget.initialPage;
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetch = widget.fetchPosts ?? ForumService.fetchThreadPosts;
      final page = await fetch(widget.url, page: _pageNumber);
      if (!mounted) return;
      setState(() {
        _page = page;
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

  void _goToPage(int page) {
    if (page == _pageNumber || page < 1) return;
    setState(() => _pageNumber = page);
    _load();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _launch(Uri uri) async {
    // Guest-rendered pages route masked links to the login page; open the
    // in-app sign-in (same flow as the thread modal) and reload after.
    // The auth change already clears ForumService's cache.
    if (uri.host.endsWith('f95zone.to') && (uri.path.startsWith('/login') || uri.path.startsWith('/register'))) {
      final success = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
      if (success == true && mounted) await _load();
      return;
    }

    final launch =
        widget.urlLauncher ?? ((uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication));
    await launch(uri);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final page = _page;
    final title = (page?.title.isNotEmpty ?? false) ? page!.title : widget.title;
    final int totalPages = page?.totalPages ?? 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            if (totalPages > 1)
              Text('page $_pageNumber of $totalPages', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () => _launch(Uri.parse(widget.url)),
          ),
        ],
      ),
      body: _buildBody(colorScheme, page, totalPages),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, ThreadPostsPage? page, int totalPages) {
    if (_loading) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null || page == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 32, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text("Couldn't load the thread", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        for (final post in page.posts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PostCard(
              post: post,
              onOpenLink: _launch,
              fetchReactions: widget.fetchReactions ?? ForumService.fetchReactions,
            ),
          ),
        if (totalPages > 1) _buildPagination(colorScheme, totalPages),
      ],
    );
  }

  /// Chevrons plus a compact pill neighborhood: first, around current, last.
  Widget _buildPagination(ColorScheme colorScheme, int totalPages) {
    final pages = <int>{
      1,
      if (_pageNumber > 1) _pageNumber - 1,
      _pageNumber,
      if (_pageNumber < totalPages) _pageNumber + 1,
      totalPages,
    }.where((p) => p >= 1 && p <= totalPages).toList()..sort();

    final items = <Widget>[
      IconButton(
        onPressed: _pageNumber > 1 ? () => _goToPage(_pageNumber - 1) : null,
        icon: const Icon(Icons.chevron_left, size: 18),
        tooltip: 'Previous page',
        color: Colors.grey[400],
      ),
    ];
    int? previous;
    for (final page in pages) {
      if (previous != null && page - previous > 1) {
        items.add(Text('…', style: TextStyle(color: Colors.grey[500], fontSize: 12)));
      }
      items.add(_buildPagePill(colorScheme, page));
      previous = page;
    }
    items.add(
      IconButton(
        onPressed: _pageNumber < totalPages ? () => _goToPage(_pageNumber + 1) : null,
        icon: const Icon(Icons.chevron_right, size: 18),
        tooltip: 'Next page',
        color: Colors.grey[400],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: items),
    );
  }

  Widget _buildPagePill(ColorScheme colorScheme, int page) {
    final bool current = page == _pageNumber;
    return GestureDetector(
      onTap: () => _goToPage(page),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: current ? colorScheme.primary.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: current ? colorScheme.primary : Colors.transparent),
        ),
        child: Text(
          '$page',
          style: TextStyle(
            fontSize: 12,
            color: current ? Colors.white : Colors.grey[400],
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatefulWidget {
  final ForumPost post;
  final void Function(Uri uri) onOpenLink;
  final FetchReactions fetchReactions;

  const _PostCard({required this.post, required this.onOpenLink, required this.fetchReactions});

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  final Set<int> _expandedSpoilers = {};

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final post = widget.post;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ForumAvatar(username: post.author, avatarUrl: post.avatarUrl),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [if (post.memberTitle.isNotEmpty) post.memberTitle, if (post.date.isNotEmpty) post.date]
                          .join(' · '),
                      style: TextStyle(color: Colors.grey[600], fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              if (post.number > 0) Text('#${post.number}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < post.blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _buildBlock(colorScheme, i, post.blocks[i]),
          ],
          if (post.reactions != null && post.reactions!.count > 0) ...[
            const SizedBox(height: 9),
            _buildReactionChip(colorScheme, post.reactions!),
          ],
        ],
      ),
    );
  }

  Widget _buildBlock(ColorScheme colorScheme, int index, ForumPostBlock block) {
    switch (block.kind) {
      case PostBlockKind.rich:
        return RichSpoilerText(pieces: block.pieces, onOpenLink: widget.onOpenLink);
      case PostBlockKind.quote:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            border: Border(left: BorderSide(color: colorScheme.primary.withValues(alpha: 0.6), width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('${block.label} said:', style: TextStyle(color: Colors.grey[500], fontSize: 10.5)),
                ),
              RichSpoilerText(pieces: block.pieces, onOpenLink: widget.onOpenLink),
            ],
          ),
        );
      case PostBlockKind.spoiler:
        final bool expanded = _expandedSpoilers.contains(index);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    setState(() => expanded ? _expandedSpoilers.remove(index) : _expandedSpoilers.add(index)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          block.label,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: Motion.duration,
                        curve: Motion.curve,
                        child: Icon(Icons.expand_more, size: 16, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ),
              SlidingReveal(
                visible: expanded,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: RichSpoilerText(pieces: block.pieces, onOpenLink: widget.onOpenLink),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildReactionChip(ColorScheme colorScheme, PostReactionSummary reactions) {
    return GestureDetector(
      key: Key('reaction-chip-${widget.post.postId}'),
      onTap: () => ReactionsSheet.show(
        context,
        url: reactions.url,
        postNumber: widget.post.number,
        fetchReactions: widget.fetchReactions,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 3, 9, 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Overlapping cluster: each badge after the first occupies 70%
            // of its width and right-aligns within that box, so it overlaps
            // only leftward into its predecessor. This keeps the advance
            // between every badge constant (unlike centered overflow, which
            // spills both sides and unevens the gaps) and the cluster bounded.
            for (int i = 0; i < reactions.topReactionIds.length; i++)
              Align(
                widthFactor: i == 0 ? 1 : 0.7,
                alignment: Alignment.centerRight,
                child: ReactionBadge(reactionId: reactions.topReactionIds[i]),
              ),
            const SizedBox(width: 6),
            Text(
              '${reactions.count}',
              style: TextStyle(color: Colors.grey[300], fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
