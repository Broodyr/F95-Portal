import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../constants.dart';
import '../models/forum.dart';
import '../services/forum_service.dart';
import '../services/site_error.dart';
import '../services/thread_page_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_view.dart';
import '../widgets/forum_composer.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/glass_fab.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reaction_picker.dart';
import '../widgets/reactions_sheet.dart';
import '../widgets/report_dialog.dart';
import '../widgets/rich_spoiler_text.dart';
import '../widgets/sliding_reveal.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

typedef FetchThreadPosts = Future<ThreadPostsPage> Function(String url, {int page});
typedef ReactSender = Future<void> Function(int postId, int reactionId, String csrfToken);
typedef ReplySender = Future<void> Function(String replyUrl, String csrfToken, String message);
typedef EditFetcher = Future<String> Function(String editUrl);
typedef EditSaver = Future<void> Function(String editUrl, String csrfToken, String message);
typedef WatchSender = Future<void> Function(String url, String csrfToken, Map<String, String> fields);
typedef PostDeleter = Future<void> Function(String deleteUrl, String csrfToken);

/// The three watch modes the long-press sheet offers.
enum WatchChoice { off, alerts, email }

/// Full-screen light thread viewer: the post loop as-is (author, avatar,
/// body with quotes/spoilers, reaction summary) with page pills at the
/// bottom. React/Quote/Reply appear when the page carries a reply URL
/// (the quick-reply form only renders for members who can post).
class ForumThreadScreen extends StatefulWidget {
  final String url;
  final String title;
  final int initialPage;
  final FetchThreadPosts? fetchPosts;
  final FetchReactions? fetchReactions;
  final ReactSender? reactSender;
  final ReplySender? replySender;
  final EditFetcher? editFetcher;
  final EditSaver? editSaver;
  final WatchSender? watchSender;
  final ReportFormFetcher? reportFormFetcher;
  final ReportSender? reportSender;
  final PostDeleter? deleteSender;
  final Future<bool> Function(Uri uri)? urlLauncher;

  const ForumThreadScreen({
    super.key,
    required this.url,
    required this.title,
    this.initialPage = 1,
    this.fetchPosts,
    this.fetchReactions,
    this.reactSender,
    this.replySender,
    this.editFetcher,
    this.editSaver,
    this.watchSender,
    this.reportFormFetcher,
    this.reportSender,
    this.deleteSender,
    this.urlLauncher,
  });

  @override
  State<ForumThreadScreen> createState() => _ForumThreadScreenState();
}

class _ForumThreadScreenState extends State<ForumThreadScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _targetPostKey = GlobalKey();
  ThreadPostsPage? _page;
  int _pageNumber = 1;
  bool _loading = true;
  bool _watched = false;
  String? _error;

  /// A 403 or 404 will not change on a second ask, so the view drops Retry.
  bool _errorRetryable = true;

  /// The thread's canonical base URL once known; permalink openings
  /// (/posts/N/ from alerts and bookmarks, /threads/x/post-N from search)
  /// can't paginate on their own URL.
  String? _resolvedUrl;

  /// The post a permalink URL targets; the first load scrolls to it.
  int? _targetPostId;
  bool _scrolledToTarget = false;

  @override
  void initState() {
    super.initState();
    _pageNumber = widget.initialPage;
    // Both permalink shapes: /posts/N/ (alerts, bookmarks) and
    // /threads/x/post-N (search results). The leading slash keeps slugs
    // like "my-post-77-story" from matching.
    _targetPostId = int.tryParse(RegExp(r'/posts?[/-](\d+)').firstMatch(widget.url)?.group(1) ?? '');
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
      final page = await fetch(_resolvedUrl ?? widget.url, page: _pageNumber);
      if (!mounted) return;
      setState(() {
        _page = page;
        _watched = page.watched;
        // Permalink fetches land wherever the server redirects them; the
        // parsed page is the truth for the counter and pagination.
        _pageNumber = page.currentPage;
        if (page.threadUrl.isNotEmpty) _resolvedUrl = page.threadUrl;
        _loading = false;
      });
      _maybeScrollToTarget();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _errorRetryable = e is! ContentUnavailableException;
        _loading = false;
      });
    }
  }

  /// One-time scroll to the permalink's post after its page first renders.
  void _maybeScrollToTarget() {
    if (_targetPostId == null || _scrolledToTarget) return;
    if (!(_page?.posts.any((post) => post.postId == _targetPostId) ?? false)) return;
    _scrolledToTarget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _stepScrollToTarget());
  }

  /// The list builds lazily, so the target's element doesn't exist until
  /// its offset is reached: step toward it until it mounts, then align it.
  Future<void> _stepScrollToTarget() async {
    while (mounted &&
        _targetPostKey.currentContext == null &&
        _scrollController.hasClients &&
        _scrollController.offset < _scrollController.position.maxScrollExtent) {
      _scrollController.jumpTo((_scrollController.offset + 600).clamp(0.0, _scrollController.position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    final targetContext = _targetPostKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(targetContext, duration: Motion.duration, curve: Motion.curve);
    }
  }

  void _goToPage(int page) {
    if (page == _pageNumber || page < 1) return;
    setState(() => _pageNumber = page);
    _load();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// Refetches the current (or given) page bypassing the cache, so a just
  /// sent write is reflected.
  Future<void> _reload({int? page}) async {
    ForumService.clearCache();
    if (page != null) _pageNumber = page;
    await _load();
  }

  /// Confirms, then deletes. XenForo's own delete is an overlay with a reason
  /// field; posting the action bare does the same thing, so this asks in the
  /// app's dialog rather than sending the user through a webview.
  Future<void> _deletePost(ForumPost post) async {
    final page = _page;
    final deleteUrl = post.deleteUrl;
    if (page == null || deleteUrl == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: const Text('Delete post?', style: TextStyle(fontSize: 16)),
        content: const Text('The post will be removed from the thread.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: GlassDialog.cancelStyle(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: GlassDialog.confirmStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final send = widget.deleteSender ?? (url, csrf) => ThreadPageService.postAction(url, csrf);
      await send(deleteUrl, page.csrfToken);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, "Couldn't delete the post: $e", error: true);
      return;
    }
    if (mounted) await _reload();
  }

  Future<void> _reportPost(ForumPost post) {
    return ReportDialog.show(
      context,
      contentUrl: 'https://f95zone.to/posts/${post.postId}',
      fetchForm: widget.reportFormFetcher,
      sendReport: widget.reportSender,
    );
  }

  void _openProfile(ForumPost post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(url: post.authorUrl!, username: post.author),
      ),
    );
  }

  /// Optimistically toggles the thread watch (without email notifications),
  /// reverting on failure. Watched threads are what feed reply alerts, so
  /// this replaces the old sheet-side watch action.
  Future<void> _toggleWatch() async {
    HapticFeedback.selectionClick();
    await _applyWatchChoice(_watched ? WatchChoice.off : WatchChoice.alerts);
  }

  /// Long-press: the full three-way choice. The site never reports whether
  /// an existing watch emails (its watch overlay is just an unwatch
  /// confirm), so a watched thread preselects nothing; re-posting a watch
  /// mode simply updates the subscription.
  Future<void> _showWatchOptions() async {
    if (_page?.watchUrl == null) return;

    HapticFeedback.vibrate();
    final WatchChoice? current = _watched ? null : WatchChoice.off;
    final choice = await _WatchOptionsSheet.show(context, current: current);
    if (choice == null || choice == current || !mounted) return;
    await _applyWatchChoice(choice);
  }

  Future<void> _applyWatchChoice(WatchChoice choice) async {
    final page = _page;
    final url = page?.watchUrl;
    if (page == null || url == null) return;
    if (choice == WatchChoice.off && !_watched) return;

    final bool wasWatched = _watched;
    setState(() => _watched = choice != WatchChoice.off);

    try {
      final send = widget.watchSender ?? (url, csrf, fields) => ThreadPageService.postAction(url, csrf, fields: fields);
      // Bare POST watches without email; email_subscribe=1 adds email (and
      // updates an existing watch); stop=1 unwatches.
      final fields = switch (choice) {
        WatchChoice.off => const {'stop': '1'},
        WatchChoice.alerts => const <String, String>{},
        WatchChoice.email => const {'email_subscribe': '1'},
      };
      await send(url, page.csrfToken, fields);
      ForumService.clearCache();
    } catch (e) {
      if (!mounted) return;
      setState(() => _watched = wasWatched);
      AppToast.show(context, '$e', error: true);
    }
  }

  Future<void> _react(ForumPost post) async {
    final page = _page;
    if (page == null) return;
    final reactionId = await ReactionPicker.show(context);
    if (reactionId == null || !mounted) return;
    try {
      final send = widget.reactSender ?? ForumService.react;
      await send(post.postId, reactionId, page.csrfToken);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '$e', error: true);
    }
  }

  Future<void> _openComposer({String initialMessage = ''}) async {
    final page = _page;
    final replyUrl = page?.replyUrl;
    if (page == null || replyUrl == null) return;

    final posted = await ForumComposer.show(
      context,
      heading: 'Reply',
      submitLabel: 'Post reply',
      initialMessage: initialMessage,
      onSubmit: (_, message) {
        final send = widget.replySender ?? ForumService.sendReply;
        return send(replyUrl, page.csrfToken, message);
      },
    );
    // New replies land at the thread's end; jump there (the reloaded page
    // may reveal a fresh final page — one tap away, acceptable).
    if (posted && mounted) await _reload(page: page.totalPages);
  }

  Future<void> _editPost(ForumPost post) async {
    final page = _page;
    final editUrl = post.editUrl;
    if (page == null || editUrl == null) return;

    final String bbcode;
    try {
      final fetch = widget.editFetcher ?? ForumService.fetchEditBbcode;
      bbcode = await fetch(editUrl);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '$e', error: true);
      return;
    }
    if (!mounted) return;

    final posted = await ForumComposer.show(
      context,
      heading: 'Edit post',
      submitLabel: 'Save',
      initialMessage: bbcode,
      onSubmit: (_, message) {
        final save = widget.editSaver ?? ForumService.saveEdit;
        return save(editUrl, page.csrfToken, message);
      },
    );
    if (posted && mounted) await _reload();
  }

  /// BBCode quote of a post's own words (nested quotes/spoilers omitted).
  String _quoteBbcode(ForumPost post) {
    final buffer = StringBuffer();
    for (final block in post.blocks) {
      if (block.kind != PostBlockKind.rich) continue;
      for (final piece in block.pieces) {
        buffer.write(piece.newline ? '\n' : (piece.imageUrl == null ? piece.text : ''));
      }
      buffer.write('\n');
    }
    // `member:` is what makes the site alert the quoted user.
    final member = post.authorId == 0 ? '' : ', member: ${post.authorId}';
    return '[QUOTE="${post.author}, post: ${post.postId}$member"]\n${buffer.toString().trim()}\n[/QUOTE]\n';
  }

  Future<void> _launch(Uri uri) async {
    // Guest-rendered pages route masked links to the login page; open the
    // in-app sign-in (same flow as the details sheet) and reload after.
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
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            if (totalPages > 1)
              Text(
                'page $_pageNumber of $totalPages',
                style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11),
              ),
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
      body: Stack(
        children: [
          _buildBody(colorScheme, page, totalPages),
          // The browse tab's search FAB spot (the bottom nav never shows on
          // pushed screens), lifted a row higher: at 24 the FAB sat on top
          // of the page pills once scrolled to the end of the thread.
          if (page?.replyUrl != null)
            Positioned(
              right: 32,
              bottom: MediaQuery.of(context).padding.bottom + 88,
              child: GlassFab(
                icon: Icons.reply,
                tooltip: 'Reply',
                scrollController: _scrollController,
                onPressed: () => _openComposer(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, ThreadPostsPage? page, int totalPages) {
    if (_loading) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null || page == null) {
      return ErrorView(headline: "Couldn't load the thread", detail: _error, onRetry: _errorRetryable ? _load : null);
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        for (final post in page.posts)
          Padding(
            key: post.postId == _targetPostId ? _targetPostKey : null,
            padding: const EdgeInsets.only(bottom: 8),
            child: _PostCard(
              post: post,
              highlighted: post.postId == _targetPostId,
              onOpenLink: _launch,
              fetchReactions: widget.fetchReactions ?? ForumService.fetchReactions,
              onAuthorTap: post.authorUrl == null ? null : () => _openProfile(post),
              // Watch sits at the OP's top-right so it's reachable without
              // scrolling the post; the anchor only renders for members.
              // Tap toggles alerts-only watching, hold picks email mode.
              watched: _watched,
              onWatchToggle: page.watchUrl != null && _pageNumber == 1 && identical(post, page.posts.first)
                  ? _toggleWatch
                  : null,
              onWatchLongPress: _showWatchOptions,
              // Writes gate on the reply URL: the quick-reply form only
              // renders for members who can post here. Edit gates on the
              // per-post edit link (own posts only).
              onReact: page.replyUrl == null ? null : () => _react(post),
              onQuote: page.replyUrl == null ? null : () => _openComposer(initialMessage: _quoteBbcode(post)),
              onEdit: post.editUrl == null ? null : () => _editPost(post),
              onDelete: post.deleteUrl == null ? null : () => _deletePost(post),
              // Unlike the others this needs no per-post link: the report
              // overlay hangs off the permalink, which every real post has.
              onReport: post.postId > 0 ? () => _reportPost(post) : null,
            ),
          ),
        if (totalPages > 1) _buildPagination(colorScheme, totalPages),
      ],
    );
  }

  // Pill metrics, shared by the widgets below and the width estimate that
  // decides how many of them fit — the two must not drift apart.
  static const double _chevronWidth = 34;
  static const double _pillFontSize = 12;
  static const double _pillHMargin = 2;
  static const double _pillHPadding = 11;
  static const double _gapHPadding = 9;
  static const double _pillVPadding = 5;

  // Both pills centre on the line box, which leaves their glyphs a shade off
  // centre — a digit rides about 0.16px high (no descender to fill the space
  // under it), an ellipsis sits a few px low (it hugs the baseline). Both are
  // deliberate.
  //
  // The digit case was corrected once and reverted. The correction has to
  // come from ascent, cap height and descent, which are the font's, so it
  // only holds for Roboto: under SF Pro, which is what Flutter's Material
  // typography uses on iOS, the same numbers overshoot by roughly 7x and tip
  // the digits low instead. A sub-pixel gain is not worth pinning the layout
  // to one platform's font, especially as correcting the geometry exactly
  // still did not read as centred — what is left is optical, and optical
  // tuning against one device is how this gets worse everywhere else.
  //
  // The ellipsis stays low on purpose too: it should read as punctuation. A
  // vertically centred triple dot is a menu glyph, and the app now has real
  // ones — the overflow buttons on posts and bookmark cards.

  /// Chevrons plus a compact pill neighborhood: first, around current, last.
  Widget _buildPagination(ColorScheme colorScheme, int totalPages) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adjacent pages are what the row sheds first when it runs out of
        // width. They carry the longest numbers, so they're the widest pills
        // going — and the least worth their width, since telling 10001 from
        // 10003 means reading five digits and diffing the last one. The
        // chevrons already do ±1, and do it without any reading at all.
        //
        // The bar is a plain fit, not some allowance to shrink into: a pill
        // is only ~23dp tall to begin with, which is already under a
        // comfortable touch target on a phone, so there's no headroom to
        // trade. Width goes to keeping the remaining pills full size.
        final double available = constraints.maxWidth - _chevronWidth * 2;
        List<int> pages = _pageWindow(totalPages, neighbours: true);
        if (_clusterWidth(context, pages) > available) {
          pages = _pageWindow(totalPages, neighbours: false);
        }

        final pills = <Widget>[];
        int? previous;
        for (final page in pages) {
          if (previous != null && page - previous > 1) {
            // Tappable gap: jump straight to a typed page number. Styled as a
            // pill like its neighbors so it reads as tappable, with a dotted
            // outline instead of a fill to keep it subordinate to real pages.
            pills.add(
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _promptForPage(totalPages),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: _pillHMargin),
                  padding: const EdgeInsets.symmetric(horizontal: _gapHPadding, vertical: _pillVPadding),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.18)),
                  ),
                  child: Text(
                    '…',
                    // No explicit `height`: it would shorten this pill's line
                    // box while the digits beside it keep the font's own, and
                    // the padding is already the same, so the gap would sit
                    // 4px shorter than every pill it separates.
                    style: TextStyle(
                      color: AppColors.of(context).bodyText,
                      fontSize: _pillFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }
          pills.add(_buildPagePill(colorScheme, page));
          previous = page;
        }

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPageChevron(Icons.chevron_left, 'Previous page', _pageNumber - 1, totalPages),
              // Dropping n±1 buys a lot of width but can't guarantee a fit on
              // its own — five digits on a small phone still run long. Scale
              // as the backstop so the row can never overflow, whatever the
              // page count, font, or text scale turns out to be.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: pills),
                ),
              ),
              _buildPageChevron(Icons.chevron_right, 'Next page', _pageNumber + 1, totalPages),
            ],
          ),
        );
      },
    );
  }

  /// The pages worth a pill: first, last, the current one, and optionally the
  /// two either side of it.
  List<int> _pageWindow(int totalPages, {required bool neighbours}) {
    return <int>{
      1,
      if (neighbours && _pageNumber > 1) _pageNumber - 1,
      _pageNumber,
      if (neighbours && _pageNumber < totalPages) _pageNumber + 1,
      totalPages,
    }.where((p) => p >= 1 && p <= totalPages).toList()..sort();
  }

  /// What [pages] would take at full size, gap pills included. Measured
  /// rather than assumed, so it holds up under a different font or a bumped
  /// system text size.
  double _clusterWidth(BuildContext context, List<int> pages) {
    double width = 0;
    int? previous;
    for (final page in pages) {
      if (previous != null && page - previous > 1) {
        width += _labelWidth(context, '…') + (_gapHPadding + _pillHMargin) * 2;
      }
      width += _labelWidth(context, '$page') + (_pillHPadding + _pillHMargin) * 2;
      previous = page;
    }
    return width;
  }

  /// Always measured at w600 — the current page's weight, and the widest a
  /// pill's label ever renders.
  double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: _pillFontSize, fontWeight: FontWeight.w600, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  /// A chevron narrowed from IconButton's 48px default: at full size the pair
  /// ate a quarter of the row, which is what pushed it into overflow. Only the
  /// width gives — shrinkWrap is what lets `constraints` actually apply, and
  /// the 48px height keeps the tap target reachable.
  Widget _buildPageChevron(IconData icon, String tooltip, int target, int totalPages) {
    return IconButton(
      onPressed: target >= 1 && target <= totalPages ? () => _goToPage(target) : null,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: AppColors.of(context).iconDefault,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: _chevronWidth, height: 48),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }

  Future<void> _promptForPage(int totalPages) async {
    // No controller (the field tracks its own text); reading via onChanged
    // avoids disposing a controller while the dialog is still animating out.
    int? entered;
    final page = await showDialog<int>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: const Text('Go to page'),
        content: TextField(
          key: const Key('page-jump-field'),
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (value) => entered = int.tryParse(value.trim()),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(int.tryParse(value.trim())),
          decoration: InputDecoration(
            hintText: '1–$totalPages',
            hintStyle: TextStyle(color: AppColors.of(context).hintText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: GlassDialog.cancelStyle(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(entered),
            style: GlassDialog.confirmStyle(context),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (page != null && mounted) _goToPage(page.clamp(1, totalPages));
  }

  Widget _buildPagePill(ColorScheme colorScheme, int page) {
    final bool current = page == _pageNumber;
    return GestureDetector(
      onTap: () => _goToPage(page),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: _pillHMargin),
        padding: const EdgeInsets.symmetric(horizontal: _pillHPadding, vertical: _pillVPadding),
        decoration: BoxDecoration(
          // Opaque rather than the translucent chipFill chips elsewhere use:
          // those sit on cards, while the pills sit on the page background,
          // where 35% of a near-black surface all but disappears.
          color: current ? colorScheme.primary.withValues(alpha: 0.3) : colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: current ? colorScheme.primary : Colors.transparent),
        ),
        child: Text(
          '$page',
          style: TextStyle(
            fontSize: _pillFontSize,
            color: current ? Colors.white : AppColors.of(context).bodyText,
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the three watch modes; pops the picked [WatchChoice].
/// A null [current] means "watching, mode unknown" — the site's markup
/// never distinguishes email from alerts-only watching.
class _WatchOptionsSheet extends StatelessWidget {
  final WatchChoice? current;

  const _WatchOptionsSheet({required this.current});

  static Future<WatchChoice?> show(BuildContext context, {required WatchChoice? current}) {
    return showModalBottomSheet<WatchChoice>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _WatchOptionsSheet(current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget option(WatchChoice choice, IconData icon, String label, String hint) {
      final bool selected = choice == current;
      return InkWell(
        onTap: () => Navigator.of(context).pop(choice),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 19, color: selected ? colorScheme.primary : AppColors.of(context).subtleText),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        // Selection is carried by the weight and the primary
                        // icon; a brighter label on top of those was 23 points
                        // of difference doing nothing visible.
                        color: AppColors.of(context).brightText,
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    Text(hint, style: TextStyle(color: AppColors.of(context).hintText, fontSize: 11)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check, size: 17, color: colorScheme.primary),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current == null ? 'Watching this thread' : 'Watch thread',
                    style: TextStyle(
                      color: AppColors.of(context).brightText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (current == null)
                    Text(
                      "The site doesn't report whether emails are on; picking a mode sets it.",
                      style: TextStyle(color: AppColors.of(context).hintText, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          option(WatchChoice.off, Icons.notifications_off_outlined, 'Not watching', 'No alerts for new replies'),
          option(WatchChoice.alerts, Icons.notifications_active_outlined, 'Alerts only', 'New replies show in Alerts'),
          option(WatchChoice.email, Icons.mail_outline, 'Alerts + email', 'Also sends email notifications'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PostCard extends StatefulWidget {
  final ForumPost post;
  final void Function(Uri uri) onOpenLink;
  final FetchReactions fetchReactions;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onReact;
  final VoidCallback? onQuote;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final bool watched;
  final VoidCallback? onWatchToggle;
  final VoidCallback? onWatchLongPress;

  /// Marks the post a permalink targeted, so the reader can spot it.
  final bool highlighted;

  const _PostCard({
    required this.post,
    required this.onOpenLink,
    required this.fetchReactions,
    this.onAuthorTap,
    this.onReact,
    this.onQuote,
    this.onEdit,
    this.onDelete,
    this.onReport,
    this.watched = false,
    this.onWatchToggle,
    this.onWatchLongPress,
    this.highlighted = false,
  });

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
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: widget.highlighted ? Border.all(color: colorScheme.primary.withValues(alpha: 0.45)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onAuthorTap,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      ForumAvatar(username: post.author, avatarUrl: post.avatarUrl),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.author,
                              style: TextStyle(
                                color: AppColors.of(context).brightText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              [
                                if (post.memberTitle.isNotEmpty) post.memberTitle,
                                if (post.date.isNotEmpty) post.date,
                              ].join(' · '),
                              style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onWatchToggle != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onWatchToggle,
                  onLongPress: widget.onWatchLongPress,
                  child: Tooltip(
                    // Long-press belongs to the options sheet, not the
                    // tooltip's default trigger.
                    triggerMode: TooltipTriggerMode.manual,
                    message: widget.watched ? 'Unwatch thread' : 'Watch thread',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Icon(
                        widget.watched ? Icons.notifications_active : Icons.notifications_none,
                        size: 17,
                        color: widget.watched
                            ? Theme.of(context).colorScheme.primary
                            : AppColors.of(context).subtleText,
                      ),
                    ),
                  ),
                ),
              if (post.number > 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: 'https://f95zone.to/posts/${post.postId}/'));
                    AppToast.show(context, 'Permalink copied');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      '#${post.number}',
                      style: TextStyle(
                        color: AppColors.of(context).hintText,
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.of(context).hintText,
                      ),
                    ),
                  ),
                ),
              // Overflow rides the header row, as on a bookmark card: report
              // is rare enough that a fifth control in the action row below
              // would cost more than it earns.
              if (widget.onReport != null) _buildOverflow(widget.onReport!),
            ],
          ),
          const SizedBox(height: 8),
          ..._buildBlocks(colorScheme, post),
          if ((post.reactions?.count ?? 0) > 0 ||
              widget.onReact != null ||
              widget.onEdit != null ||
              widget.onDelete != null) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                if ((post.reactions?.count ?? 0) > 0) _buildReactionChip(colorScheme, post.reactions!),
                const Spacer(),
                // Edit and Delete sit here rather than in the overflow, as on
                // a profile wall post: they are the author's own actions on
                // their own post, and both confirm before doing anything.
                if (widget.onEdit != null) ...[
                  _buildFooterAction(Icons.edit_outlined, 'Edit', widget.onEdit!),
                  const SizedBox(width: 14),
                ],
                if (widget.onDelete != null) ...[
                  _buildFooterAction(Icons.delete_outline, 'Delete', widget.onDelete!),
                  const SizedBox(width: 14),
                ],
                if (widget.onReact != null) _buildFooterAction(Icons.add_reaction_outlined, 'React', widget.onReact!),
                if (widget.onQuote != null) ...[
                  const SizedBox(width: 14),
                  _buildFooterAction(Icons.format_quote_outlined, 'Quote', widget.onQuote!),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Sized by its own padding via `child`, not `icon` — an M3 IconButton
  /// won't go under 40x40, which is too tall for a header row of 11px text.
  /// Same shape as the bookmark card's overflow.
  Widget _buildOverflow(VoidCallback onReport) {
    return PopupMenuButton<String>(
      tooltip: 'Post tools',
      padding: EdgeInsets.zero,
      color: AppColors.of(context).chipSurface,
      onSelected: (_) => onReport(),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'report',
          height: 40,
          child: Text('Report…', style: TextStyle(fontSize: 13)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
        child: Icon(Icons.more_vert, size: 16, color: AppColors.of(context).iconDefault),
      ),
    );
  }

  Widget _buildFooterAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.of(context).subtleText),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// Blocks share one gallery spanning the whole post, so tapping any image
  /// pages through every image of the reply (quotes and spoilers included).
  List<Widget> _buildBlocks(ColorScheme colorScheme, ForumPost post) {
    final postGalleryUrls = [
      for (final block in post.blocks)
        for (final piece in block.pieces)
          if (piece.imageUrl != null) piece.fullImageUrl ?? piece.imageUrl!,
    ];

    final widgets = <Widget>[];
    int imageOffset = 0;
    for (int i = 0; i < post.blocks.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 6));
      final block = post.blocks[i];
      widgets.add(_buildBlock(colorScheme, i, block, postGalleryUrls, imageOffset));
      imageOffset += block.pieces.where((p) => p.imageUrl != null).length;
    }
    return widgets;
  }

  Widget _buildBlock(
    ColorScheme colorScheme,
    int index,
    ForumPostBlock block,
    List<String> galleryUrls,
    int galleryIndexOffset,
  ) {
    switch (block.kind) {
      case PostBlockKind.rich:
        return RichSpoilerText(
          pieces: block.pieces,
          onOpenLink: widget.onOpenLink,
          galleryUrls: galleryUrls,
          galleryIndexOffset: galleryIndexOffset,
        );
      case PostBlockKind.quote:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.04),
            border: Border(left: BorderSide(color: colorScheme.primary.withValues(alpha: 0.6), width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${block.label} said:',
                    style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 10.5),
                  ),
                ),
              RichSpoilerText(
                pieces: block.pieces,
                onOpenLink: widget.onOpenLink,
                galleryUrls: galleryUrls,
                galleryIndexOffset: galleryIndexOffset,
              ),
            ],
          ),
        );
      case PostBlockKind.spoiler:
        final bool expanded = _expandedSpoilers.contains(index);
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => expanded ? _expandedSpoilers.remove(index) : _expandedSpoilers.add(index)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          block.label,
                          style: TextStyle(
                            color: AppColors.of(context).brightText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: Motion.duration,
                        curve: Motion.curve,
                        child: Icon(Icons.expand_more, size: 16, color: AppColors.of(context).subtleText),
                      ),
                    ],
                  ),
                ),
              ),
              SlidingReveal(
                visible: expanded,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: RichSpoilerText(
                    pieces: block.pieces,
                    onOpenLink: widget.onOpenLink,
                    galleryUrls: galleryUrls,
                    galleryIndexOffset: galleryIndexOffset,
                  ),
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
          color: colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.12)),
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
                widthFactor: i == 0 ? 1 : 0.8,
                alignment: Alignment.centerRight,
                child: ReactionBadge(reactionId: reactions.topReactionIds[i]),
              ),
            const SizedBox(width: 6),
            Text(
              '${reactions.count}',
              style: TextStyle(color: AppColors.of(context).brightText, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
