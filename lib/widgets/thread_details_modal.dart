import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../models/f95_metadata.dart';
import '../models/search_category.dart';
import '../models/thread_page.dart';
import '../models/thread_summary.dart';
import '../screens/forum_thread_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/thread_page_service.dart';
import '../utils/formatters.dart';
import 'engine_tag.dart';
import 'rich_spoiler_text.dart';
import 'screenshot_gallery.dart';
import 'sfw_blur.dart';
import 'sliding_reveal.dart';
import 'version_pill.dart';

/// Popped by the modal when the user picks a tag: tap adds it to the active
/// search, long-press replaces the search with just that tag.
class ThreadTagSelection {
  final int tagId;
  final bool replace;

  const ThreadTagSelection({required this.tagId, required this.replace});
}

typedef UrlLauncher = Future<bool> Function(Uri uri);
typedef FetchThreadPage = Future<ThreadPage> Function(int threadId);
typedef ThreadActionSender = Future<void> Function(String url, String csrfToken, Map<String, String> fields);

class ThreadDetailsModal extends StatefulWidget {
  final ThreadSummary thread;
  final SearchCategory category;
  final UrlLauncher? urlLauncher;
  final FetchThreadPage? fetchThreadPage;
  final ThreadActionSender? actionSender;

  /// Passed to the forum viewer that "Open thread" pushes (tests inject it).
  final FetchThreadPosts? fetchThreadPosts;

  const ThreadDetailsModal({
    super.key,
    required this.thread,
    this.category = SearchCategory.games,
    this.urlLauncher,
    this.fetchThreadPage,
    this.actionSender,
    this.fetchThreadPosts,
  });

  static Future<ThreadTagSelection?> show(
    BuildContext context,
    ThreadSummary thread, {
    SearchCategory category = SearchCategory.games,
    UrlLauncher? urlLauncher,
    FetchThreadPage? fetchThreadPage,
    ThreadActionSender? actionSender,
    FetchThreadPosts? fetchThreadPosts,
  }) {
    return showModalBottomSheet<ThreadTagSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext context) => ThreadDetailsModal(
        thread: thread,
        category: category,
        urlLauncher: urlLauncher,
        fetchThreadPage: fetchThreadPage,
        actionSender: actionSender,
        fetchThreadPosts: fetchThreadPosts,
      ),
    );
  }

  @override
  State<ThreadDetailsModal> createState() => _ThreadDetailsModalState();
}

class _ThreadDetailsModalState extends State<ThreadDetailsModal> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  ThreadPage? _page;
  bool _loadingPage = true;
  String? _pageError;
  bool _liked = false;
  bool _watched = false;
  bool _overviewExpanded = false;
  final Set<int> _expandedSpoilers = {};

  /// Selected group per download set (sets are independent switchers).
  final Map<int, int> _setGroupIndex = {};

  ThreadSummary get thread => widget.thread;

  Uri get _threadUri => Uri.parse('https://f95zone.to/threads/${thread.threadId}/');

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  /// The top grab band resizes the sheet directly, so the modal can always
  /// be pulled down even when the inner list is scrolled deep into content.
  void _onBandDragUpdate(DragUpdateDetails details) {
    final height = MediaQuery.of(context).size.height;
    if (height <= 0 || !_sheetController.isAttached) return;
    _sheetController.jumpTo((_sheetController.size - details.delta.dy / height).clamp(0.4, 0.95));
  }

  void _onBandDragEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) return;
    if (_sheetController.size <= 0.41 || details.velocity.pixelsPerSecond.dy > 700) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadPage() async {
    setState(() {
      _loadingPage = true;
      _pageError = null;
    });

    try {
      final fetch = widget.fetchThreadPage ?? ThreadPageService.fetch;
      final page = await fetch(thread.threadId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _liked = page.actions?.liked ?? false;
        _watched = page.actions?.watched ?? false;
        _loadingPage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pageError = e.toString();
        _loadingPage = false;
      });
    }
  }

  Future<void> _launch(Uri uri) async {
    // Guest-rendered pages link spoilers to the login page; route those to
    // the in-app sign-in (which captures the session) and refresh after.
    if (uri.host.endsWith('f95zone.to') && (uri.path.startsWith('/login') || uri.path.startsWith('/register'))) {
      final success = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
      if (success == true && mounted) {
        ThreadPageService.invalidate(thread.threadId);
        await _loadPage();
      }
      return;
    }

    final launch =
        widget.urlLauncher ?? ((uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication));
    await launch(uri);
  }

  void _shareThread() {
    // Link only; receivers' rich link previews supply the title/art.
    SharePlus.instance.share(ShareParams(text: '$_threadUri'));
  }

  /// Opens the thread in the in-app forum viewer (which keeps its own
  /// open-in-browser action for the external escape hatch).
  void _openThread() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadScreen(url: '$_threadUri', title: thread.title, fetchPosts: widget.fetchThreadPosts),
      ),
    );
  }

  /// Optimistically toggles like/watch, reverting on failure. The page cache
  /// is invalidated so a reopened modal refetches the real state.
  Future<void> _toggleAction({required bool isLike}) async {
    final actions = _page?.actions;
    final url = isLike ? actions?.reactUrl : actions?.watchUrl;
    if (actions == null || url == null) return;

    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in from the Profile tab to like and bookmark threads.')));
      return;
    }

    HapticFeedback.selectionClick();
    final bool wasActive = isLike ? _liked : _watched;
    setState(() => isLike ? _liked = !wasActive : _watched = !wasActive);

    try {
      final send =
          widget.actionSender ?? (url, csrf, fields) => ThreadPageService.postAction(url, csrf, fields: fields);
      // React toggles on its own; watch needs stop=1 to unwatch.
      await send(url, actions.csrfToken, !isLike && wasActive ? const {'stop': '1'} : const {});
      ThreadPageService.invalidate(thread.threadId);
    } catch (e) {
      if (!mounted) return;
      setState(() => isLike ? _liked = wasActive : _watched = wasActive);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        // Same glass treatment as the search modal: blur + translucent
        // surface, or a near-opaque solid when glass effects are disabled.
        final bool glass = SettingsService.instance.settings.glassEffects;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: _maybeBlur(
            glass,
            child: Container(
              decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
              child: Column(
                children: [
                  GestureDetector(
                    key: const Key('modal-drag-band'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _onBandDragUpdate,
                    onVerticalDragEnd: _onBandDragEnd,
                    child: SizedBox(
                      height: 36,
                      width: double.infinity,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).viewPadding.bottom),
                      children: [
                        _buildCoverHeader(context),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                thread.title,
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text('by ${thread.creator}', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                            ],
                          ),
                        ),
                        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _buildStatsRow(colorScheme)),
                        if (thread.screens.isNotEmpty) ...[
                          _buildSectionLabel('Screenshots'),
                          SizedBox(
                            height: 96,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: thread.screens.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, index) => _buildScreenshotThumb(context, index),
                            ),
                          ),
                        ],
                        if (thread.tags.isNotEmpty) ...[
                          _buildSectionLabel('Tags', hint: 'tap to add to search · hold to replace'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildTagChips(context, colorScheme),
                          ),
                        ],
                        ..._buildPageSections(colorScheme),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _openThread,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  icon: const Icon(Icons.forum_outlined, size: 18),
                                  label: const Text('Open thread'),
                                ),
                              ),
                              if (_page?.actions?.reactUrl != null) ...[
                                const SizedBox(width: 8),
                                IconButton.outlined(
                                  onPressed: () => _toggleAction(isLike: true),
                                  tooltip: _liked ? 'Unlike' : 'Like',
                                  icon: Icon(
                                    _liked ? Icons.favorite : Icons.favorite_border,
                                    size: 20,
                                    color: _liked ? colorScheme.primary : null,
                                  ),
                                ),
                              ],
                              if (_page?.actions?.watchUrl != null) ...[
                                const SizedBox(width: 8),
                                IconButton.outlined(
                                  onPressed: () => _toggleAction(isLike: false),
                                  tooltip: _watched ? 'Remove bookmark' : 'Bookmark',
                                  icon: Icon(
                                    _watched ? Icons.bookmark : Icons.bookmark_border,
                                    size: 20,
                                    color: _watched ? colorScheme.primary : null,
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                onPressed: _shareThread,
                                tooltip: 'Share',
                                // The share glyph's visual weight sits right of
                                // center; nudge it so it reads centered.
                                icon: Transform.translate(
                                  offset: const Offset(-1, 0),
                                  child: const Icon(Icons.share_outlined, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _maybeBlur(bool glass, {required Widget child}) {
    if (!glass) return child;
    return BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: child);
  }

  // --- Scraped page sections -----------------------------------------------

  List<Widget> _buildPageSections(ColorScheme colorScheme) {
    if (_loadingPage) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('Loading thread details…', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
      ];
    }

    if (_pageError != null) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Expanded(
                child: Text("Couldn't load thread details", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ),
              TextButton(onPressed: _loadPage, child: const Text('Retry')),
            ],
          ),
        ),
      ];
    }

    final page = _page;
    if (page == null) return const [];

    final metaFields = [
      for (final field in page.metaFields)
        if (!{'genre', 'overview'}.contains(field.label.toLowerCase())) field,
    ];
    final spoilers = [
      for (final spoiler in page.spoilers)
        if (spoiler.title.toLowerCase() != 'genre') spoiler,
    ];

    return [
      if (metaFields.isNotEmpty) ...[
        _buildSectionLabel('Info'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildInfoGrid(metaFields)),
      ],
      if (page.overview.isNotEmpty) ...[
        _buildSectionLabel('Overview'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildOverviewCard(colorScheme, page.overview),
        ),
      ],
      if (page.downloads != null && !page.downloads!.isEmpty) ...[
        _buildSectionLabel('Downloads'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildDownloadsCard(colorScheme, page.downloads!),
        ),
      ] else if (!AuthService.instance.isLoggedIn) ...[
        // Guest-rendered pages hide download links, so an absent section
        // almost always means "not signed in" rather than "no downloads".
        _buildSectionLabel('Downloads'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildDownloadsLoginPrompt(colorScheme),
        ),
      ],
      if (page.attachments.isNotEmpty) ...[
        _buildSectionLabel('Attachments'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildHostLinks(colorScheme, page.attachments),
          ),
        ),
      ],
      for (int i = 0; i < spoilers.length; i++)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildSpoilerCard(colorScheme, i, spoilers[i]),
        ),
    ];
  }

  Widget _buildInfoGrid(List<MetaField> fields) {
    final itemWidth = (MediaQuery.of(context).size.width - 48) / 2;
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: [
        for (final field in fields)
          SizedBox(
            width: itemWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                Text(field.value, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOverviewCard(ColorScheme colorScheme, String overview) {
    final style = TextStyle(color: Colors.grey[300], fontSize: 13, height: 1.45);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Overviews that fit the 5-line clamp get no expand affordance and
        // ignore taps; measured at this width so the answer tracks layout.
        final painter = TextPainter(
          text: TextSpan(text: overview, style: style),
          maxLines: 5,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth - 24);
        final bool overflows = painter.didExceedMaxLines;
        painter.dispose();

        return GestureDetector(
          onTap: overflows ? () => setState(() => _overviewExpanded = !_overviewExpanded) : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            // The card glides between the 5-line clamp and the full text.
            // The SizedBox pins the width so only the height animates.
            child: AnimatedSize(
              key: const Key('overview-size'),
              duration: Motion.duration,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      overview,
                      maxLines: _overviewExpanded ? null : 5,
                      overflow: _overviewExpanded ? null : TextOverflow.ellipsis,
                      style: style,
                    ),
                    if (overflows)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Center(
                          child: AnimatedRotation(
                            key: const Key('overview-chevron'),
                            turns: _overviewExpanded ? 0.5 : 0,
                            duration: Motion.duration,
                            curve: Motion.curve,
                            child: Icon(Icons.expand_more, size: 16, color: Colors.grey[500]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadsLoginPrompt(ColorScheme colorScheme) {
    return GestureDetector(
      // Routed through _launch so the f95 login path triggers the in-app
      // sign-in and the page refetch that reveals the real download links.
      onTap: () => _launch(Uri.parse('https://f95zone.to/login/')),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sign in to see download links',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
            ),
            Text('Sign in', style: TextStyle(color: colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadsCard(ColorScheme colorScheme, DownloadsSection downloads) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int setIndex = 0; setIndex < downloads.sets.length; setIndex++) ...[
            if (setIndex > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
              ),
            _buildDownloadSet(colorScheme, setIndex, downloads.sets[setIndex]),
          ],
          if (downloads.extras.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            ),
            Text('Extras', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const SizedBox(height: 6),
            for (final extra in downloads.extras) ...[
              if (extra.label.toLowerCase() != 'extras' && extra.label.toLowerCase() != 'extra')
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(extra.label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ),
              _buildHostLinks(colorScheme, extra.links),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  /// One download set: optional title (alternate versions), a group switcher
  /// when there are multiple groups, and the selected group's host links.
  Widget _buildDownloadSet(ColorScheme colorScheme, int setIndex, DownloadSet set) {
    final groups = set.groups;
    final int selectedIndex = (_setGroupIndex[setIndex] ?? 0).clamp(0, groups.isEmpty ? 0 : groups.length - 1);

    // Long group lists (animation collections) read better as labeled rows
    // than as a 10-way switcher.
    final bool asRows = groups.length > 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (set.title != null) ...[
          Text(
            set.title!,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
        ],
        if (asRows) ...[
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(group.label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ),
            _buildHostLinks(colorScheme, group.links),
            const SizedBox(height: 8),
          ],
        ] else if (groups.length > 1) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < groups.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _setGroupIndex[setIndex] = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: i == selectedIndex ? colorScheme.primary.withValues(alpha: 0.25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: i == selectedIndex
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      groups[i].label,
                      style: TextStyle(
                        fontSize: 12,
                        color: i == selectedIndex ? colorScheme.primary : Colors.grey[400],
                        fontWeight: i == selectedIndex ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _buildHostLinks(colorScheme, groups[selectedIndex].links),
        ] else if (groups.length == 1) ...[
          if (groups.single.label != 'Links') ...[
            Text(groups.single.label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const SizedBox(height: 6),
          ],
          _buildHostLinks(colorScheme, groups.single.links),
        ],
      ],
    );
  }

  Widget _buildHostLinks(ColorScheme colorScheme, List<DownloadLink> links) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final link in links)
          GestureDetector(
            onTap: () => _launch(Uri.parse(link.url)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new, size: 12, color: colorScheme.primary),
                  const SizedBox(width: 5),
                  Text(link.host, style: TextStyle(color: Colors.grey[200], fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSpoilerCard(ColorScheme colorScheme, int index, SpoilerSection spoiler) {
    final bool expanded = _expandedSpoilers.contains(index);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => expanded ? _expandedSpoilers.remove(index) : _expandedSpoilers.add(index)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      spoiler.title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: Motion.duration,
                    curve: Motion.curve,
                    child: Icon(Icons.expand_more, size: 18, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
          SlidingReveal(
            key: Key('spoiler-body-${spoiler.title}'),
            visible: expanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: RichSpoilerText(
                pieces: spoiler.rich.isEmpty ? [RichPiece.text(spoiler.content)] : spoiler.rich,
                onOpenLink: _launch,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Phase-1 sections (unchanged) ----------------------------------------

  Widget _buildCoverHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GestureDetector(
        key: const Key('details-cover'),
        behavior: HitTestBehavior.opaque,
        // Covers are cropped to 3:1 here; tap to see the full image.
        onTap: thread.cover.isEmpty ? null : () => ScreenshotGallery.show(context, [thread.cover]),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 3.0,
                child: thread.cover.isEmpty
                    ? Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(Icons.image_outlined, color: Color(0xFF666666), size: 48),
                      )
                    : SfwBlur(
                        child: CachedNetworkImage(
                          imageUrl: thread.cover,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.image_outlined, color: Color(0xFF666666), size: 48),
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: EngineTag(engines: ThreadUtils.getEnginesFromThread(thread.prefixes, category: widget.category)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: VersionPill(
                version: thread.version,
                isCompleted: thread.isCompleted,
                isAbandoned: thread.isAbandoned,
                isOnhold: thread.isOnhold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(ColorScheme colorScheme) {
    Widget stat(IconData icon, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: Colors.grey[400]),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        stat(Icons.star_outline, thread.rating > 0 ? thread.rating.toStringAsFixed(1) : '-'),
        const SizedBox(width: 6),
        stat(Icons.favorite_outline, NumberFormatter.formatNumber(thread.likes)),
        const SizedBox(width: 6),
        stat(Icons.visibility_outlined, NumberFormatter.formatNumber(thread.views)),
        const SizedBox(width: 6),
        stat(Icons.schedule, thread.date),
      ],
    );
  }

  Widget _buildSectionLabel(String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScreenshotThumb(BuildContext context, int index) {
    return GestureDetector(
      onTap: () => ScreenshotGallery.show(context, thread.screens, initialIndex: index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 150,
          child: SfwBlur(
            child: CachedNetworkImage(
              imageUrl: thread.screens[index],
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: const Color(0xFF2A2A2A)),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF2A2A2A),
                child: const Icon(Icons.broken_image_outlined, color: Color(0xFF666666)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagChips(BuildContext context, ColorScheme colorScheme) {
    final metadata = F95Metadata.instance;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tagId in thread.tags)
          GestureDetector(
            onTap: () {
              // selectionClick/vibrate are used (not light/heavyImpact)
              // because Android maps heavyImpact to CONTEXT_CLICK, which
              // feels weaker than lightImpact on many devices.
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(ThreadTagSelection(tagId: tagId, replace: false));
            },
            onLongPress: () {
              HapticFeedback.vibrate();
              Navigator.of(context).pop(ThreadTagSelection(tagId: tagId, replace: true));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Text(
                metadata.tagName(tagId) ?? '#$tagId',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}
