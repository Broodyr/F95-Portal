import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/forum_composer.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import 'forum_thread_screen.dart';
import 'login_screen.dart';

typedef FetchProfile = Future<ProfilePage> Function();
typedef FetchProfilePostings = Future<List<ProfilePosting>> Function(String profileUrl);
typedef FetchProfileAbout = Future<ProfileAbout> Function(String profileUrl);

/// Wall writes: new profile posts and comments share one shape (action URL,
/// page CSRF, message).
typedef ProfileMessagePoster = Future<void> Function(String url, String csrfToken, String message);

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
  final FetchProfileAbout? fetchAbout;
  final ProfileMessagePoster? messagePoster;
  final FetchThreadPosts? fetchThreadPosts;
  final FetchReactions? fetchReactions;
  final ReactSender? reactSender;
  final ReplySender? replySender;

  const ProfileScreen({
    super.key,
    this.url,
    this.scrollController,
    this.username,
    this.fetchProfile,
    this.fetchPostings,
    this.fetchAbout,
    this.messagePoster,
    this.fetchThreadPosts,
    this.fetchReactions,
    this.reactSender,
    this.replySender,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _background = Color(0xFF0F0F0F);
  static const Color _card = Color(0xFF1C1C1E);

  ProfilePage? _page;
  bool _loading = false;
  String? _error;

  int _tab = 0;

  List<ProfilePosting>? _postings;
  bool _postingsLoading = false;
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
    if (_showProfile) _loadProfile();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
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
    _postings = null;
    _postingsLoading = false;
    _postingsError = null;
    _about = null;
    _aboutLoading = false;
    _aboutError = null;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Pull-to-refresh and post-write reload: refetch the profile and drop
  /// the lazily loaded tabs so they refetch on next open.
  Future<void> _refresh() async {
    _postings = null;
    _postingsError = null;
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
    if (page == null || _postings != null || _postingsLoading) return;

    // The pane is usually a separate lazy fetch, but use it when inline.
    if (page.postings.isNotEmpty) {
      setState(() => _postings = page.postings);
      return;
    }

    setState(() {
      _postingsLoading = true;
      _postingsError = null;
    });
    try {
      final fetch = widget.fetchPostings ?? ProfileService.fetchPostings;
      final postings = await fetch(page.profileUrl);
      if (!mounted) return;
      setState(() {
        _postings = postings;
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
      onSubmit: (_, message) => poster(actionUrl, page.csrfToken, message),
    );
    if (posted && mounted) _refresh();
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
    // Postings link to the exact post; the viewer wants the thread URL.
    final threadUrl = posting.url.replaceFirst(RegExp(r'post-\d+/?$'), '');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadScreen(
          url: threadUrl,
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
      backgroundColor: _background,
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
            Icon(Icons.person_outline, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            const Text(
              'Not signed in',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Anonymous browsing is limited, including the omission of download links.\nSign in to lift the limit and see your profile.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _signIn,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
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
                const Text(
                  'Profile',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text('f95zone.to', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                const Spacer(),
                if (AuthService.instance.isLoggedIn)
                  IconButton(
                    tooltip: 'Sign out',
                    icon: Icon(Icons.logout, size: 20, color: Colors.grey[400]),
                    onPressed: _signOut,
                  ),
              ] else ...[
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back, size: 22, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    _page?.username ?? widget.username ?? 'Profile',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
          Expanded(child: _buildError(_error!, _loadProfile))
        else if (page != null)
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: colorScheme.primary,
              backgroundColor: _card,
              child: ListView(
                controller: widget.scrollController,
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
      ],
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
        ForumAvatar(username: page.username, avatarUrl: page.avatarUrl, size: 48),
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
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (page.memberTitle.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF262629),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(page.memberTitle, style: TextStyle(color: Colors.grey[400], fontSize: 10.5)),
                    ),
                  ],
                ],
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(meta, style: TextStyle(color: Colors.grey[500], fontSize: 11.5)),
                ),
              if (page.lastSeen.isNotEmpty)
                Text('Last seen ${page.lastSeen}', style: TextStyle(color: Colors.grey[600], fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          for (final (index, label) in const [(0, 'Profile posts'), (1, 'Postings'), (2, 'About')])
            Expanded(
              child: GestureDetector(
                onTap: () => _openTab(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: _tab == index ? colorScheme.primary.withValues(alpha: 0.18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _tab == index ? colorScheme.primary : Colors.grey[500],
                      fontSize: 12,
                      fontWeight: _tab == index ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
    return [
      if (page.wallPostUrl != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _composeMessage(heading: 'New profile post', actionUrl: page.wallPostUrl!),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 15, color: Colors.grey[600]),
                  const SizedBox(width: 7),
                  Text('Write something…', style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
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
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        )
      else
        for (final post in page.wallPosts) _buildWallPost(colorScheme, post),
    ];
  }

  Widget _buildWallPost(ColorScheme colorScheme, ProfilePost post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
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
                          style: const TextStyle(color: Color(0xFFE8E8E8), fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(post.date, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(post.body, style: const TextStyle(color: Color(0xFFC9C9C9), fontSize: 12.5, height: 1.45)),
          if (post.comments.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(left: 9),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey[800]!, width: 1.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final comment in post.comments) _buildComment(comment)],
              ),
            ),
          if (post.commentUrl != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _composeMessage(heading: 'Comment', actionUrl: post.commentUrl!),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  foregroundColor: Colors.grey[500],
                ),
                icon: Icon(Icons.mode_comment_outlined, size: 13, color: Colors.grey[600]),
                label: const Text('Comment', style: TextStyle(fontSize: 11.5)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComment(ProfileComment comment) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
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
                          style: const TextStyle(color: Color(0xFFD5D5D5), fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    Text(comment.date, style: TextStyle(color: Colors.grey[700], fontSize: 10)),
                  ],
                ),
                Text(comment.body, style: TextStyle(color: Colors.grey[400], fontSize: 11.5, height: 1.4)),
              ],
            ),
          ),
        ],
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
    final postings = _postings;
    if (postings == null) return const [];
    if (postings.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text('No postings yet.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
        ),
      ];
    }
    return [for (final posting in postings) _buildPosting(colorScheme, posting)];
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
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
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
                              color: colorScheme.primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(prefix, style: TextStyle(color: colorScheme.primary, fontSize: 9.5)),
                          ),
                        ),
                      ),
                    TextSpan(
                      text: posting.title,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
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
                    style: TextStyle(color: Colors.grey[500], fontSize: 11.5, height: 1.35),
                  ),
                ),
              if (footer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(footer, style: TextStyle(color: Colors.grey[600], fontSize: 10.5)),
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
            child: Text('Nothing here yet.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
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
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (final (icon, label, value) in details)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(icon, size: 15, color: Colors.grey[600]),
                      const SizedBox(width: 9),
                      Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Color(0xFFD5D5D5), fontSize: 12),
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
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
          child: Text(about.bio, style: const TextStyle(color: Color(0xFFC9C9C9), fontSize: 12.5, height: 1.5)),
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
                style: TextStyle(color: Colors.grey[500], fontSize: 13.5),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildError(String message, Future<void> Function() retry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
