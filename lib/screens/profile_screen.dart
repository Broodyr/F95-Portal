import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../constants.dart';
import '../models/profile.dart';
import '../models/thread_page.dart';
import '../services/auth_service.dart';
import '../services/forum_service.dart';
import '../services/profile_service.dart';
import '../services/site_error.dart';
import '../theme/app_colors.dart';
import '../widgets/app_action_sheet.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_view.dart';
import '../widgets/forum_composer.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/image_gallery.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import '../widgets/report_dialog.dart';
import '../widgets/rich_spoiler_text.dart';
import '../widgets/segmented_selector.dart';
import 'forum_thread_screen.dart';
import 'login_screen.dart';

typedef FetchProfile = Future<ProfilePage> Function();

/// Loads the first page of a member's full postings from their "See more"
/// query; [FetchProfilePostingsPage] loads the rest by page number.
typedef FetchProfilePostings = Future<ProfilePostingsPage> Function(String postingsSearchUrl);
typedef FetchProfilePostingsPage = Future<ProfilePostingsPage> Function(String searchUrl, int page);

/// Loads a wall page other than the one the profile arrived on
/// (`/members/<slug>.<id>/page-N`), re-parsing the member page for its feed.
typedef FetchProfileWallPage = Future<ProfilePage> Function(String profileUrl, int page);
typedef FetchProfileAbout = Future<ProfileAbout> Function(String profileUrl);

/// Wall writes: new profile posts and comments share one shape (action URL,
/// page CSRF, message).
typedef ProfileMessagePoster = Future<void> Function(String url, String csrfToken, String message);

/// Deletes a viewer-owned wall post through its delete action.
typedef ProfilePostDeleter = Future<void> Function(String deleteUrl, String csrfToken);

/// The permalink shapes a member's wall serves: a root post
/// (`/profile-posts/N`) or a reply (`/profile-posts/comments/N`). Postings and
/// search rows can carry either, and both belong on the wall — a pushed
/// [ProfileScreen] jumps to the post — rather than in the thread viewer, which
/// can't render one. Every other content URL is a thread.
final RegExp _profilePostUrl = RegExp(r'/profile-posts/(?:comments/)?\d+');

bool isProfilePostUrl(String url) => _profilePostUrl.hasMatch(url);

/// A member profile: identity header, then the profile-post wall, recent
/// postings, and About as segmented tabs.
///
/// With no [url] it's the bottom-nav Profile tab showing the signed-in
/// member's own profile (a sign-in gate when logged out; mock data on the
/// web build). With a [url] it's a pushed screen for another member,
/// reached from their posts.
class ProfileScreen extends StatefulWidget {
  /// Member page URL to show; null means the signed-in user's own profile.
  final String? url;

  /// The wall list's controller, passed by MainApp on the own-profile tab
  /// to hide/show the bottom nav and route the nav bar's pass-through
  /// drags here. Pushed member profiles have no bottom nav and omit it.
  final ScrollController? scrollController;

  /// The member's name, shown in the top bar while their page loads.
  final String? username;

  final FetchProfile? fetchProfile;
  final FetchProfilePostings? fetchPostings;
  final FetchProfilePostingsPage? postingsPager;
  final FetchProfileWallPage? wallPager;
  final FetchProfileAbout? fetchAbout;
  final ProfileMessagePoster? messagePoster;
  final EditFetcher? editFetcher;
  final EditSaver? editSaver;
  final ProfilePostDeleter? postDeleter;
  final ReportFormFetcher? reportFormFetcher;
  final ReportSender? reportSender;
  final FetchThreadPosts? fetchThreadPosts;
  final FetchReactions? fetchReactions;
  final ReactSender? reactSender;
  final ReplySender? replySender;

  /// Opens a link tapped in a wall post or comment; defaults to the
  /// platform browser. Injected by tests.
  final Future<bool> Function(Uri uri)? urlLauncher;

  const ProfileScreen({
    super.key,
    this.url,
    this.scrollController,
    this.username,
    this.fetchProfile,
    this.fetchPostings,
    this.postingsPager,
    this.wallPager,
    this.fetchAbout,
    this.messagePoster,
    this.editFetcher,
    this.editSaver,
    this.postDeleter,
    this.reportFormFetcher,
    this.reportSender,
    this.fetchThreadPosts,
    this.fetchReactions,
    this.reactSender,
    this.replySender,
    this.urlLauncher,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Vertical gap between wall cards, and how long a landed jump keeps
  /// re-aligning as avatars and inline images above it settle. Both mirror
  /// the thread viewer, which solves the same scroll-to-a-post problem.
  static const double _cardGap = 8;
  static const Duration _settleWindow = Duration(seconds: 2);

  /// The comment block's inset above and below its rail. The fill's left
  /// corners round by this same amount, so the faint fill curves in to meet
  /// the rail's ends instead of overhanging them in a hard square corner.
  static const double _commentBlockPad = 6;

  ProfilePage? _page;
  bool _loading = false;
  String? _error;

  /// The wall's own scroll driver. The own-profile tab hands one down (it
  /// hides the bottom nav on scroll); a pushed member profile passes none, so
  /// one is minted here — a jump to a post needs a controller to move.
  ScrollController? _ownedScrollController;
  ScrollController get _scrollController => widget.scrollController ?? (_ownedScrollController ??= ScrollController());

  /// A profile-post permalink lands the reader on the wall page holding one
  /// post or comment, then scrolls to it — the /profile-posts/N and
  /// /profile-posts/comments/N shapes, parsed from [ProfileScreen.url]. Only
  /// one is ever set. The key rides whichever card is the target.
  final GlobalKey _targetKey = GlobalKey();
  int? _targetPostId;
  int? _targetCommentId;
  bool _scrolledToTarget = false;

  /// Set once the reader drags the list, which ends any settling correction
  /// still nudging the target into place.
  bool _readerTookOver = false;
  bool _settling = false;
  Timer? _settleTimer;

  /// Set when [_error] is one the site won't answer differently next time,
  /// to the status it answered with: no retry, and 403 and 404 each get
  /// their own wording. Null for an ordinary, retryable failure.
  int? _errorStatus;

  int _tab = 0;

  /// Set while a wall page other than the loaded one is fetching. The wall
  /// pages a whole member page at a time (unlike the Postings tab's scroll),
  /// so [_page] is swapped wholesale on arrival; the header stays put.
  bool _wallLoading = false;

  /// Postings accumulate across pages as the reader scrolls. [_postingsPage]
  /// holds the last page's pagination (total pages, the GET-able results
  /// URL); null until the first page lands, which is the "not yet loaded"
  /// marker the tab reads.
  final List<ProfilePosting> _postings = [];
  ProfilePostingsPage? _postingsPage;
  int _postingsLoadedPages = 0;
  bool _postingsLoading = false;
  bool _postingsLoadingMore = false;
  String? _postingsError;

  ProfileAbout? _about;
  bool _aboutLoading = false;
  String? _aboutError;

  bool get _isOwnProfile => widget.url == null;

  /// Other members' profiles always render (errors show inline); the own
  /// tab keeps its sign-in gate.
  bool get _showProfile => !_isOwnProfile || kIsWeb || AuthService.instance.isLoggedIn;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    // A comment permalink nests the id under /comments/; check it first so the
    // shared /profile-posts/ prefix doesn't swallow it as a post.
    final url = widget.url ?? '';
    final comment = RegExp(r'/profile-posts/comments/(\d+)').firstMatch(url);
    if (comment != null) {
      _targetCommentId = int.tryParse(comment.group(1)!);
    } else {
      _targetPostId = int.tryParse(RegExp(r'/profile-posts/(\d+)').firstMatch(url)?.group(1) ?? '');
    }
    if (_showProfile) _loadProfile();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    _settleTimer?.cancel();
    _ownedScrollController?.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (_showProfile) {
      if (_page == null && !_loading) _loadProfile();
    } else {
      setState(_resetState);
    }
  }

  void _resetState() {
    _page = null;
    _loading = false;
    _error = null;
    _tab = 0;
    _wallLoading = false;
    _resetPostings();
    _about = null;
    _aboutLoading = false;
    _aboutError = null;
  }

  void _resetPostings() {
    _postings.clear();
    _postingsPage = null;
    _postingsLoadedPages = 0;
    _postingsLoading = false;
    _postingsLoadingMore = false;
    _postingsError = null;
  }

  /// A pushed profile can't load for guests (the site serves member pages
  /// to members only); the build shows a sign-in prompt for that state.
  bool get _needsSignIn => !_isOwnProfile && !kIsWeb && !AuthService.instance.isLoggedIn;

  Future<void> _loadProfile() async {
    if (_needsSignIn) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetch =
          widget.fetchProfile ??
          (_isOwnProfile ? ProfileService.fetchOwnProfile : () => ProfileService.fetchProfile(widget.url!));
      final page = await fetch();
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
      _maybeScrollToTarget();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _errorStatus = e is ContentUnavailableException ? (e.statusCode ?? 403) : null;
        _loading = false;
      });
    }
  }

  /// Pull-to-refresh and post-write reload: refetch the profile and drop
  /// the lazily loaded tabs so they refetch on next open.
  Future<void> _refresh() async {
    _resetPostings();
    _about = null;
    _aboutError = null;
    await _loadProfile();
    if (_tab == 1) _ensurePostings();
    if (_tab == 2) _ensureAbout();
  }

  void _openTab(int index) {
    setState(() => _tab = index);
    if (index == 1) _ensurePostings();
    if (index == 2) _ensureAbout();
  }

  Future<void> _ensurePostings() async {
    final page = _page;
    if (page == null || _postingsPage != null || _postingsLoading) return;

    // No "See more" query means nothing to page through — the empty state
    // stands in, rather than a spinner that never resolves.
    final searchUrl = page.postingsSearchUrl;
    if (searchUrl == null || searchUrl.isEmpty) {
      setState(() => _postingsPage = const ProfilePostingsPage());
      return;
    }

    setState(() {
      _postingsLoading = true;
      _postingsError = null;
    });
    try {
      final fetch = widget.fetchPostings ?? ProfileService.fetchPostings;
      final result = await fetch(searchUrl);
      if (!mounted) return;
      setState(() {
        _postingsPage = result;
        _postings
          ..clear()
          ..addAll(result.postings);
        _postingsLoadedPages = 1;
        _postingsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postingsError = e.toString();
        _postingsLoading = false;
      });
    }
  }

  /// Fetches the next postings page as the reader nears the end. Mirrors the
  /// forum search list: failures stay silent, so scrolling again retries.
  Future<void> _loadMorePostings() async {
    final page = _postingsPage;
    if (page == null || _postingsLoadingMore || _postingsLoadedPages >= page.totalPages || page.searchUrl.isEmpty) {
      return;
    }
    _postingsLoadingMore = true;
    try {
      final fetch = widget.postingsPager ?? ProfileService.fetchPostingsPage;
      final next = await fetch(page.searchUrl, _postingsLoadedPages + 1);
      if (!mounted) return;
      setState(() {
        _postings.addAll(next.postings);
        _postingsLoadedPages++;
      });
    } catch (_) {
      // Silent: scrolling further retries.
    } finally {
      _postingsLoadingMore = false;
    }
  }

  /// Jumps the wall to another page through its page-nav. The member page for
  /// that page carries the same header, so the whole [_page] is swapped and
  /// the identity block above the tabs doesn't flinch. Failures surface as a
  /// toast and leave the current page in place.
  Future<void> _goToWallPage(int page) async {
    final current = _page;
    if (current == null || page == current.wallPage || _wallLoading) return;

    setState(() => _wallLoading = true);
    try {
      final fetch = widget.wallPager ?? ProfileService.fetchProfileWallPage;
      final next = await fetch(current.profileUrl, page);
      if (!mounted) return;
      setState(() {
        _page = next;
        _wallLoading = false;
        // A page the reader picked by hand leaves any jump highlight behind —
        // the targeted post isn't on this page, and its border would mislead.
        _targetPostId = null;
        _targetCommentId = null;
      });
      // Land at the top of the new page.
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _wallLoading = false);
      AppToast.show(context, '$e', error: true);
    }
  }

  // --- Jump to a permalinked post or comment --------------------------------

  bool get _hasTarget => _targetPostId != null || _targetCommentId != null;

  /// True once the landed page actually holds the target — a post by id, or a
  /// comment nested under any post. Guards the scroll so a stale permalink (or
  /// a redirect that missed) is a quiet no-op rather than a scroll to nowhere.
  bool _targetIsPresent(ProfilePage page) {
    if (_targetPostId != null) return page.wallPosts.any((p) => p.id == _targetPostId);
    if (_targetCommentId != null) {
      return page.wallPosts.any((p) => p.comments.any((c) => c.id == _targetCommentId));
    }
    return false;
  }

  /// One-time scroll to the permalink's post or comment after the wall first
  /// renders. Mirrors the thread viewer's jump.
  void _maybeScrollToTarget() {
    final page = _page;
    if (!_hasTarget || _scrolledToTarget || page == null || !_targetIsPresent(page)) return;
    _scrolledToTarget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _stepScrollToTarget());
  }

  /// The list lays out lazily, so the target may not exist until its offset is
  /// reached: step down until it mounts, then align it. Permalinks open at the
  /// top and search downward.
  Future<void> _stepScrollToTarget() async {
    while (mounted &&
        _targetKey.currentContext == null &&
        _scrollController.hasClients &&
        _scrollController.offset < _scrollController.position.maxScrollExtent) {
      final position = _scrollController.position;
      _scrollController.jumpTo(
        (_scrollController.offset + 600).clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    final targetContext = _targetKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(targetContext, duration: Motion.duration, curve: Motion.curve);
      _alignTarget();
      await _holdTargetWhileSettling();
    }
  }

  /// Where the scroll must sit for the target to rest just below the tabs,
  /// backed off half a card gap so it doesn't touch the chrome. Null once the
  /// target leaves the tree.
  double? _targetOffset() {
    final targetContext = _targetKey.currentContext;
    if (targetContext == null || !targetContext.mounted) return null;
    final box = targetContext.findRenderObject();
    if (box == null || !box.attached || !_scrollController.hasClients) return null;
    final reveal = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset - _cardGap / 2;
    final position = _scrollController.position;
    return reveal.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Puts the target where [_targetOffset] says it belongs if it has drifted.
  /// Instant, not animated: this is a correction, and easing it would read as
  /// the page moving on its own.
  bool _alignTarget() {
    final desired = _targetOffset();
    if (desired == null || (desired - _scrollController.offset).abs() <= 0.5) return false;
    _scrollController.jumpTo(desired);
    return true;
  }

  /// Avatars and inline images carry no height until they load, so cards above
  /// the target grow after the scroll lands and push it down. Hold it in place
  /// while the page settles; the reader taking hold ends this at once.
  Future<void> _holdTargetWhileSettling() async {
    _readerTookOver = false;
    _settleTimer?.cancel();
    _settling = true;
    _settleTimer = Timer(_settleWindow, () => _settling = false);
    while (mounted && _settling && !_readerTookOver) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _readerTookOver || !_scrollController.hasClients) break;
      _alignTarget();
    }
    _settleTimer?.cancel();
    _settleTimer = null;
    _settling = false;
  }

  Future<void> _ensureAbout() async {
    final page = _page;
    if (page == null || _about != null || _aboutLoading) return;

    setState(() {
      _aboutLoading = true;
      _aboutError = null;
    });
    try {
      final fetch = widget.fetchAbout ?? ProfileService.fetchAbout;
      final about = await fetch(page.profileUrl);
      if (!mounted) return;
      setState(() {
        _about = about;
        _aboutLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aboutError = e.toString();
        _aboutLoading = false;
      });
    }
  }

  Future<void> _composeMessage({required String heading, required String actionUrl}) async {
    final page = _page;
    if (page == null) return;
    final poster = widget.messagePoster ?? ProfileService.postWallMessage;
    final posted = await ForumComposer.show(
      context,
      heading: heading,
      // The action URL already tells a profile's wall apart from the comment
      // box on one of its posts, so drafts for the two don't collide.
      draftKey: actionUrl,
      onSubmit: (_, message) => poster(actionUrl, page.csrfToken, message),
    );
    if (posted && mounted) _refresh();
  }

  /// Fetches a post's or comment's BBCode, then reopens it in the composer —
  /// the same flow the thread viewer uses for forum posts.
  Future<void> _editViaComposer(String editUrl) async {
    final page = _page;
    if (page == null) return;

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
    if (posted && mounted) _refresh();
  }

  Future<void> _deleteWithConfirm(String deleteUrl, {required String title, required String message}) async {
    final page = _page;
    if (page == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: Text(title),
        content: Text(message),
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
      final delete = widget.postDeleter ?? ProfileService.deleteProfilePost;
      await delete(deleteUrl, page.csrfToken);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '$e', error: true);
      return;
    }
    if (mounted) _refresh();
  }

  /// Opens another member's profile; taps on the profile currently shown
  /// (the owner commenting on their own wall) go nowhere.
  void _openMember(String? url, String author) {
    if (url == null || url == _page?.profileUrl) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(url: url, username: author),
      ),
    );
  }

  void _openPosting(ProfilePosting posting) {
    // A profile-post row opens the member's wall jumped to that post, not the
    // thread viewer; the wall page is resolved by the permalink's redirect.
    if (isProfilePostUrl(posting.url)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(url: posting.url)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadScreen(
          // Postings link to the exact post; the viewer scrolls to it.
          url: posting.url,
          title: posting.title,
          fetchPosts: widget.fetchThreadPosts,
          fetchReactions: widget.fetchReactions,
          reactSender: widget.reactSender,
          replySender: widget.replySender,
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (kIsWeb) {
      AppToast.show(context, 'Sign-in is not available in the web build.');
      return;
    }

    final success = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));

    if (success == true && mounted) {
      AppToast.show(context, 'Signed in — API requests now use your account.');
    }
  }

  Future<void> _signOut() async {
    await AuthService.instance.logout();
    // Also clear the webview's cookie jar so the next sign-in starts fresh.
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      debugPrint('Webview cookie cleanup skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: ListenableBuilder(
        listenable: AuthService.instance,
        builder: (context, _) {
          if (!_showProfile) return _buildSignInGate(colorScheme);
          return SafeArea(bottom: false, child: _buildProfile(colorScheme));
        },
      ),
    );
  }

  Widget _buildSignInGate(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: AppColors.of(context).mutedForeground),
            const SizedBox(height: 16),
            Text(
              'Not signed in',
              style: TextStyle(color: AppColors.of(context).brightText, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Anonymous browsing is limited, including the omission of download links.\nSign in to lift the limit and see your profile.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _signIn,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                textStyle: AppButtons.ctaTextStyle,
              ),
              icon: const Icon(Icons.login, size: AppButtons.ctaIconSize),
              label: const Text('Sign in to F95Zone'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(ColorScheme colorScheme) {
    final page = _page;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(_isOwnProfile ? 16 : 6, 14, 8, 6),
          child: Row(
            children: [
              if (_isOwnProfile) ...[
                Text(
                  'Profile',
                  style: TextStyle(color: AppColors.of(context).brightText, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text('f95zone.to', style: TextStyle(color: AppColors.of(context).hintText, fontSize: 11)),
                const Spacer(),
                if (AuthService.instance.isLoggedIn)
                  IconButton(
                    tooltip: 'Sign out',
                    icon: Icon(Icons.logout, size: 20, color: AppColors.of(context).iconDefault),
                    onPressed: _signOut,
                  ),
              ] else ...[
                IconButton(
                  tooltip: 'Back',
                  // Hand-rolled header rather than an AppBar, so it doesn't
                  // inherit appBarTheme — match its back arrow by hand.
                  icon: Icon(Icons.arrow_back, size: 22, color: AppColors.of(context).brightText),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    _page?.username ?? widget.username ?? 'Profile',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.of(context).brightText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_needsSignIn)
          Expanded(child: _buildSignInPrompt(colorScheme))
        else if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: _errorStatus != null ? _buildUnavailable(_error!) : _buildError(_error!, _loadProfile))
        else if (page != null)
          Expanded(
            // The whole profile scrolls as one list; the Postings tab pages in
            // more as it nears the end, the same 600px lead the search list
            // uses. Guarded on the tab so the wall and About don't trip it.
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (_tab == 1 && notification.metrics.extentAfter < 600) _loadMorePostings();
                // A drag is the reader taking over, which ends a jump's
                // settling correction; a programmatic align carries no drag.
                if (notification is ScrollStartNotification && notification.dragDetails != null) {
                  _readerTookOver = true;
                }
                return false;
              },
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: colorScheme.primary,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                  children: [
                    _buildHeader(page),
                    const SizedBox(height: 14),
                    _buildTabBar(colorScheme),
                    const SizedBox(height: 12),
                    ..._buildTabContent(colorScheme, page),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The header avatar opens full size, which the small ones in the wall and
  /// comments can't: those are already the tap target for the member's page,
  /// and at 17-22px they are too fiddly to carry a second meaning anyway.
  Widget _buildHeaderAvatar(ProfilePage page) {
    final avatar = ForumAvatar(username: page.username, avatarUrl: page.avatarUrl, size: 48);
    // With nothing uploaded the avatar is a drawn letter tile, so there is no
    // image to open — the tap target would only ever disappoint.
    final full = page.avatarFullUrl ?? page.avatarUrl;
    if (full == null || full.isEmpty) return avatar;
    return GestureDetector(
      onTap: () => ImageGallery.show(context, [full]),
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );
  }

  Widget _buildHeader(ProfilePage page) {
    final meta = [
      if (page.messages.isNotEmpty) '${page.messages} messages',
      if (page.joined.isNotEmpty) 'Joined ${page.joined}',
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildHeaderAvatar(page),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      page.username,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.of(context).brightText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (page.memberTitle.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.of(context).chipSurface,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        page.memberTitle,
                        style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 10.5),
                      ),
                    ),
                  ],
                ],
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(meta, style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11.5)),
                ),
              if (page.lastSeen.isNotEmpty)
                Text(
                  'Last seen ${page.lastSeen}',
                  style: TextStyle(color: AppColors.of(context).hintText, fontSize: 11.5),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(ColorScheme colorScheme) {
    return SegmentedSelector<int>(
      values: const [0, 1, 2],
      isSelected: (index) => _tab == index,
      label: (index) => const ['Profile posts', 'Postings', 'About'][index],
      onSelect: _openTab,
    );
  }

  List<Widget> _buildTabContent(ColorScheme colorScheme, ProfilePage page) {
    switch (_tab) {
      case 1:
        return _buildPostingsTab(colorScheme);
      case 2:
        return _buildAboutTab(colorScheme);
      default:
        return _buildWallTab(colorScheme, page);
    }
  }

  // --- Profile posts (wall) -------------------------------------------------

  List<Widget> _buildWallTab(ColorScheme colorScheme, ProfilePage page) {
    // A page jump swaps the whole member page; hold a spinner under the tabs
    // meanwhile, the same as the Postings and About tabs' first load.
    if (_wallLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    return [
      if (page.wallPostUrl != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _composeMessage(heading: 'New profile post', actionUrl: page.wallPostUrl!),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 15, color: AppColors.of(context).hintText),
                  const SizedBox(width: 7),
                  Text('Write something…', style: TextStyle(color: AppColors.of(context).hintText, fontSize: 12.5)),
                ],
              ),
            ),
          ),
        ),
      if (page.wallPosts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              _isOwnProfile ? 'No messages on your profile yet.' : 'No messages on this profile yet.',
              style: TextStyle(color: AppColors.of(context).hintText, fontSize: 13),
            ),
          ),
        )
      else
        for (final post in page.wallPosts) _buildWallPost(colorScheme, post),
      // The wall's own page-nav, the shared pill bar the thread and reviews
      // pages use. Only when the feed runs past one page.
      if (page.wallTotalPages > 1)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PaginationBar(page: page.wallPage, totalPages: page.wallTotalPages, onSelect: _goToWallPage),
        ),
    ];
  }

  /// Profile posts are their own XenForo content type, so the report overlay
  /// hangs off /profile-posts/N rather than the /posts/N the thread uses.
  /// Both shapes are confirmed against the saved fixtures' own report links.
  Future<void> _reportWallPost(ProfilePost post) {
    return ReportDialog.show(
      context,
      contentUrl: 'https://f95zone.to/profile-posts/${post.id}',
      fetchForm: widget.reportFormFetcher,
      sendReport: widget.reportSender,
    );
  }

  /// A comment is addressed under its own path rather than its parent's —
  /// /profile-posts/comments/N, not /profile-posts/N.
  Future<void> _reportComment(ProfileComment comment) {
    return ReportDialog.show(
      context,
      contentUrl: 'https://f95zone.to/profile-posts/comments/${comment.id}',
      fetchForm: widget.reportFormFetcher,
      sendReport: widget.reportSender,
    );
  }

  /// Header-row overflow, sized by its padding via `child` — see the note on
  /// the bookmark card's version for why `icon` can't be used.
  /// [dense] is for a comment's header, whose text is 11.5px against a wall
  /// post's 12.5 — at the post's size this control set the row height and
  /// pushed the card taller.
  Widget _buildOverflow(List<AppSheetAction> actions, {bool dense = false}) {
    return AppOverflowButton(
      tooltip: 'Post tools',
      actions: actions,
      padding: dense ? const EdgeInsets.fromLTRB(8, 0, 0, 0) : const EdgeInsets.fromLTRB(8, 4, 2, 4),
      iconSize: dense ? 14 : 16,
    );
  }

  Widget _buildWallPost(ColorScheme colorScheme, ProfilePost post) {
    final hasActions = post.editUrl != null || post.deleteUrl != null || post.commentUrl != null;
    // A post a permalink jumped to: the whole card takes a primary outline,
    // the same mark the thread viewer puts on a jumped-to post. A comment
    // target leaves the card plain — its own rail segment carries the accent.
    final bool isTarget = post.id == _targetPostId;
    return Container(
      key: isTarget ? _targetKey : null,
      margin: const EdgeInsets.only(bottom: 8),
      // No bottom padding under the footer row: its buttons are 48pt tap
      // targets around ~16pt of label, so they already carry a matching band
      // of slack above and below. Padding on top of that only lands below
      // them, leaving the row visibly closer to the content above it than to
      // the card edge. Posts without a footer still need the real padding.
      padding: EdgeInsets.fromLTRB(12, 10, 12, hasActions ? 0 : 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isTarget
            ? Border.all(color: colorScheme.primary.withValues(alpha: AppAlphas.outlineEdge), width: 2.0)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openMember(post.authorUrl, post.author),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      ForumAvatar(username: post.author, avatarUrl: post.avatarUrl, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          post.author,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.of(context).brightText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(post.date, style: TextStyle(color: AppColors.of(context).hintText, fontSize: 11)),
              // Same header-row overflow as a thread post and a bookmark card.
              // Edit and Delete stay in the footer row here: a wall post has
              // room for them, and they are the actions its own author reaches
              // for. Only report, which anyone may want, is tucked away.
              if (post.id > 0)
                _buildOverflow([
                  AppSheetAction(icon: Icons.outlined_flag, label: 'Report…', onTap: () => _reportWallPost(post)),
                ]),
            ],
          ),
          const SizedBox(height: 6),
          DefaultTextStyle.merge(
            style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 12.5, height: 1.45),
            child: RichSpoilerText(pieces: _piecesOf(post.rich, post.body), onOpenLink: _launch),
          ),
          if (post.comments.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              // Horizontal padding drops to zero: the rail — the thread
              // viewer's nested-block treatment, a faint fill behind a left
              // line — now rides each comment so a jumped-to one can light its
              // own segment, and the side insets move onto the comments so that
              // segment's wash spans the block's full width, edge to edge.
              padding: const EdgeInsets.fromLTRB(0, _commentBlockPad, 0, _commentBlockPad),
              // Round only the left corners, by the inset, so the fill tucks in
              // to where the rail starts and stops rather than squaring off past
              // it. The open right side stays square.
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.04),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(_commentBlockPad),
                  bottomLeft: Radius.circular(_commentBlockPad),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final comment in post.comments) _buildComment(colorScheme, comment)],
              ),
            ),
          if (hasActions)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Edit/Delete gate on the per-post action links, which the
                // site only renders on the viewer's own posts.
                if (post.editUrl != null)
                  _buildWallAction(Icons.edit_outlined, 'Edit', () => _editViaComposer(post.editUrl!)),
                if (post.deleteUrl != null)
                  _buildWallAction(
                    Icons.delete_outline,
                    'Delete',
                    () => _deleteWithConfirm(
                      post.deleteUrl!,
                      title: 'Delete profile post?',
                      message: 'The post and its comments will be removed.',
                    ),
                  ),
                if (post.commentUrl != null)
                  _buildWallAction(
                    Icons.mode_comment_outlined,
                    'Comment',
                    () => _composeMessage(heading: 'Comment', actionUrl: post.commentUrl!),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Pitched to match the thread viewer's react/quote/edit row, which is the
  /// same kind of control: a [bodyText] label with its icon a step under.
  /// Both sat a tier lower here for no reason beyond being written apart.
  Widget _buildWallAction(IconData icon, String label, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
        foregroundColor: AppColors.of(context).bodyText,
      ),
      icon: Icon(icon, size: 13, color: AppColors.of(context).subtleText),
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
    );
  }

  Widget _buildComment(ColorScheme colorScheme, ProfileComment comment) {
    // The rail runs the height of every comment; a jumped-to one turns its
    // own segment primary — the one accent that marks the reply a permalink
    // pointed at — with a faint wash so the row itself reads as the target.
    final bool isTarget = comment.id == _targetCommentId;
    return Container(
      key: isTarget ? _targetKey : null,
      // Both side insets ride the comment (9 past the rail, 8 before the edge)
      // rather than the block, so a target comment's wash fills the block width
      // instead of stopping short of a right padding.
      padding: const EdgeInsets.only(left: 9, right: 8),
      decoration: BoxDecoration(
        color: isTarget ? colorScheme.primary.withValues(alpha: AppAlphas.highlightWash) : null,
        border: Border(
          left: BorderSide(
            color: isTarget ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: AppAlphas.subtleEdge),
            width: 1.5,
          ),
        ),
      ),
      child: Padding(
        // Symmetric so replies aren't packed shoulder to shoulder, and — since
        // it sits inside the rail — the bottom half gives a jumped-to comment
        // somewhere empty to land: the scroll backs off half a root-card gap
        // (4px), which would otherwise slice the reply above where comments
        // abut. 6 clears that back-off with room to spare.
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openMember(comment.authorUrl, comment.author),
              behavior: HitTestBehavior.opaque,
              child: ForumAvatar(username: comment.author, avatarUrl: comment.avatarUrl, size: 17),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openMember(comment.authorUrl, comment.author),
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            comment.author,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.of(context).brightText,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      // Same colour as a top-level post's date; the smaller size
                      // already sets a comment apart without darkening it too.
                      Text(comment.date, style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10)),
                      // One overflow rather than a row of glyphs. A comment's
                      // header is already tight, and adding report to the icons
                      // would have put three controls beside an 11px name —
                      // where the post above it gets one. Edit and Delete come
                      // along, still gated on the per-comment links.
                      if (comment.id > 0)
                        _buildOverflow([
                          if (comment.editUrl != null)
                            AppSheetAction(
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                              onTap: () => _editViaComposer(comment.editUrl!),
                            ),
                          if (comment.deleteUrl != null)
                            AppSheetAction(
                              icon: Icons.delete_outline,
                              label: 'Delete',
                              destructive: true,
                              onTap: () => _deleteWithConfirm(
                                comment.deleteUrl!,
                                title: 'Delete comment?',
                                message: 'The comment will be removed.',
                              ),
                            ),
                          AppSheetAction(
                            icon: Icons.outlined_flag,
                            label: 'Report…',
                            onTap: () => _reportComment(comment),
                          ),
                        ], dense: true),
                    ],
                  ),
                  DefaultTextStyle.merge(
                    style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 11.5, height: 1.4),
                    child: RichSpoilerText(pieces: _piecesOf(comment.rich, comment.body), onOpenLink: _launch),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Postings ---------------------------------------------------------------

  List<Widget> _buildPostingsTab(ColorScheme colorScheme) {
    if (_postingsLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_postingsError != null) return [_buildError(_postingsError!, _ensurePostings)];
    final page = _postingsPage;
    if (page == null) return const [];
    if (_postings.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text('No postings yet.', style: TextStyle(color: AppColors.of(context).hintText, fontSize: 13)),
          ),
        ),
      ];
    }
    return [
      for (final posting in _postings) _buildPosting(colorScheme, posting),
      if (_postingsLoadedPages < page.totalPages)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
    ];
  }

  Widget _buildPosting(ColorScheme colorScheme, ProfilePosting posting) {
    final footer = [
      if (posting.postInfo.isNotEmpty) posting.postInfo,
      if (posting.date.isNotEmpty) posting.date,
      if (posting.replies.isNotEmpty) 'Replies: ${posting.replies}',
      if (posting.forum.isNotEmpty) posting.forum,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openPosting(posting),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    for (final prefix in posting.prefixes)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: AppAlphas.labelChip),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(prefix, style: TextStyle(color: colorScheme.primary, fontSize: 9.5)),
                          ),
                        ),
                      ),
                    TextSpan(
                      text: posting.title,
                      style: TextStyle(
                        color: AppColors.of(context).brightText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (posting.snippet.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    posting.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11.5, height: 1.35),
                  ),
                ),
              if (footer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(footer, style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- About ------------------------------------------------------------------

  List<Widget> _buildAboutTab(ColorScheme colorScheme) {
    if (_aboutLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_aboutError != null) return [_buildError(_aboutError!, _ensureAbout)];
    final about = _about;
    if (about == null) return const [];
    if (about.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text('Nothing here yet.', style: TextStyle(color: AppColors.of(context).hintText, fontSize: 13)),
          ),
        ),
      ];
    }

    final details = [
      if (about.birthday.isNotEmpty) (Icons.cake_outlined, 'Birthday', about.birthday),
      if (about.website.isNotEmpty) (Icons.link, 'Website', about.website),
      if (about.location.isNotEmpty) (Icons.place_outlined, 'Location', about.location),
    ];

    return [
      if (details.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final (icon, label, value) in details)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(icon, size: 15, color: AppColors.of(context).hintText),
                      const SizedBox(width: 9),
                      Text(label, style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12)),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: AppColors.of(context).brightText, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (about.bio.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(about.bio, style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 12.5, height: 1.5)),
        ),
    ];
  }

  /// Guests can't fetch member pages: one sentence whose "Sign in" opens
  /// the login flow; the profile loads on its own once the session lands.
  Widget _buildSignInPrompt(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: _signIn,
                  child: Text(
                    'Sign in',
                    style: TextStyle(color: colorScheme.primary, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              TextSpan(
                text: ' to view member profiles.',
                style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 13.5),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Falls back to the plain body for anything built by hand — mock data,
  /// tests — which carries no pieces.
  List<RichPiece> _piecesOf(List<RichPiece> rich, String body) => rich.isNotEmpty ? rich : [RichPiece.text(body)];

  Future<void> _launch(Uri uri) async {
    final launch =
        widget.urlLauncher ?? ((uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication));
    await launch(uri);
  }

  /// The profile isn't coming, and won't on a second ask. A 403 is the
  /// member shutting the viewer out, a 404 is no such member — different
  /// enough to say differently. The site's own wording carries the detail,
  /// and neither offers a retry.
  Widget _buildUnavailable(String message) {
    final missing = _errorStatus == 404;
    return ErrorView(
      icon: missing ? Icons.person_off_outlined : Icons.lock_outline,
      headline: missing ? 'Member not found' : 'Profile is private',
      detail: message,
    );
  }

  Widget _buildError(String message, Future<void> Function() retry) {
    return ErrorView(headline: "Couldn't load this profile", detail: message, onRetry: retry);
  }
}
