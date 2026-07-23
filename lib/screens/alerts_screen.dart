import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../constants.dart';
import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/forum_service.dart';
import '../services/site_error.dart';
import '../theme/app_colors.dart';
import '../widgets/app_action_sheet.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_view.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import 'forum_thread_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

typedef FetchAlerts = Future<AlertsPage> Function({int page});
typedef AlertsAcknowledger = Future<void> Function(List<int> unreadAlertIds);
typedef AlertReadMarker = Future<void> Function(int alertId);
typedef AlertUnreadMarker = Future<void> Function(int alertId);
typedef AlertsBulkReadMarker = Future<void> Function();
typedef AlertPreferencesFetcher = Future<AlertPreferences> Function();

/// A thread or post permalink — the shapes [ForumThreadScreen] can open
/// (`/posts/N/` from a reply or reaction, `/threads/slug.N/…` from a quote).
/// The `-` in `/profile-posts/` keeps those from matching here; they route to
/// the member's wall instead.
final RegExp _threadAlertUrl = RegExp(r'/(?:threads|posts)/');

/// A bare member profile (`/members/slug.N/`), the target of a "started
/// following you" alert — [ProfileScreen] renders it. Anchored to the id so a
/// sub-page like `/members/slug.N/trophies` (a trophy award) doesn't match and
/// stays non-actionable.
final RegExp _memberProfileUrl = RegExp(r'/members/[^/]+\.\d+/?(?:$|\?)');

bool isMemberProfileUrl(String url) => _memberProfileUrl.hasMatch(url);

/// Whether tapping [alert] reaches a screen the app can render. The alerts
/// feed carries many XenForo types — a trophy award, ticket and conversation
/// notices, username-change verdicts — that the app has no destination for;
/// this whitelist keeps those rows from opening a blank thread viewer.
/// Openable: a post/thread permalink (the thread viewer), a profile
/// post/comment, or a follower's profile (the member's wall).
bool alertIsActionable(AlertEntry alert) =>
    isProfilePostUrl(alert.url) || isMemberProfileUrl(alert.url) || _threadAlertUrl.hasMatch(alert.url);

/// The account alerts feed: date-grouped rows (actor, action, target
/// thread with its prefix labels), unread highlighting, and load-more
/// pagination. A tap reads the row and opens it where the app can — the
/// thread viewer or a member's wall (see [alertIsActionable]); a type with
/// no in-app screen just reads and points at the browser. Long-press is a
/// per-row menu: read/unread and open-in-browser.
///
/// This screen is the app's bell, so opening it acknowledges the feed the
/// same way the site's bell dropdown does: the just-fetched rows keep
/// their unread tint for this visit, and the server marks them read per
/// the account's pop-up preference.
class AlertsScreen extends StatefulWidget {
  final FetchAlerts? fetchAlerts;
  final AlertsAcknowledger? alertsAcknowledger;
  final FetchThreadPosts? fetchThreadPosts;
  final FetchReactions? fetchReactions;

  /// Reads/restores a single alert (a tap, or the row menu's toggle). Injected
  /// by tests; both default to the [ForumService] endpoints.
  final AlertReadMarker? alertReadMarker;
  final AlertUnreadMarker? alertUnreadMarker;

  /// Opens an alert's URL in the platform browser from the row menu; defaults
  /// to url_launcher. Injected by tests.
  final Future<bool> Function(Uri uri)? urlLauncher;

  /// Reads the whole feed at once (the app-bar "Mark all read"), and the
  /// preference that gates whether that control even shows. Both default to
  /// [ForumService]; injected by tests.
  final AlertsBulkReadMarker? markAllReadMarker;
  final AlertPreferencesFetcher? preferencesFetcher;

  const AlertsScreen({
    super.key,
    this.fetchAlerts,
    this.alertsAcknowledger,
    this.fetchThreadPosts,
    this.fetchReactions,
    this.alertReadMarker,
    this.alertUnreadMarker,
    this.urlLauncher,
    this.markAllReadMarker,
    this.preferencesFetcher,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final ScrollController _scrollController = ScrollController();

  AlertsPage? _page;
  final List<AlertGroup> _groups = [];
  int _loadedPages = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// A 403 or 404 will not change on a second ask, so the view drops Retry.
  bool _errorRetryable = true;

  /// Whether the account keeps alerts unread until visited. Only then is a
  /// "Mark all read" affordance useful — otherwise opening the feed already
  /// read everything. Learned once per visit (the preference is per-session).
  bool _popupSkipsMarkRead = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    // The web build runs on mock data without a session.
    if (kIsWeb || AuthService.instance.isLoggedIn) {
      _load();
      _loadPreference();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Alerts arrive server-side while the app runs: always fetch live.
    ForumService.invalidateAccountPages();
    setState(() {
      _loading = _page == null;
      _error = null;
    });
    try {
      final fetch = widget.fetchAlerts ?? ForumService.fetchAlerts;
      final page = await fetch(page: 1);
      if (!mounted) return;
      setState(() {
        _page = page;
        // Clone with growable lists so later pages can merge into a group.
        _groups
          ..clear()
          ..addAll([
            for (final group in page.groups) AlertGroup(title: group.title, alerts: [...group.alerts]),
          ]);
        _loadedPages = 1;
        _loading = false;
      });
      await _acknowledge(page);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _errorRetryable = e is! ContentUnavailableException;
        _loading = false;
      });
    }
  }

  /// Learns whether the account keeps alerts unread until visited, which gates
  /// the "Mark all read" control. Failure just leaves it hidden — it's an
  /// affordance, not something worth a toast.
  Future<void> _loadPreference() async {
    try {
      final fetch = widget.preferencesFetcher ?? ForumService.fetchAlertPreferences;
      final prefs = await fetch();
      if (!mounted) return;
      setState(() => _popupSkipsMarkRead = prefs.popupSkipsMarkRead);
    } catch (_) {
      // No preference, no button.
    }
  }

  /// Viewing the feed acknowledges it, like opening the site's bell — plus
  /// the displayed unread rows get marked read individually, since the
  /// pop-up route only covers its own short render. This visit keeps its
  /// unread tints; the next fetch shows them read. Failures surface as a
  /// toast: a silently stuck badge is a bug report nobody can act on.
  Future<void> _acknowledge(AlertsPage page) async {
    try {
      final acknowledge = widget.alertsAcknowledger ?? (ids) => ForumService.acknowledgeAlerts(unreadAlertIds: ids);
      await acknowledge([
        for (final group in page.groups)
          for (final alert in group.alerts)
            if (alert.unread && alert.alertId > 0) alert.alertId,
      ]);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, "Couldn't mark alerts read: $e", error: true);
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
      final fetch = widget.fetchAlerts ?? ForumService.fetchAlerts;
      final next = await fetch(page: _loadedPages + 1);
      if (!mounted) return;
      setState(() {
        for (final group in next.groups) {
          // A date can span the page break; keep one header per date.
          if (_groups.isNotEmpty && _groups.last.title == group.title) {
            _groups.last.alerts.addAll(group.alerts);
          } else {
            _groups.add(AlertGroup(title: group.title, alerts: [...group.alerts]));
          }
        }
        _loadedPages++;
      });
      // Older pages scrolled into view count as seen too; skip the round
      // trip when the page carries nothing unread.
      if (next.groups.any((group) => group.alerts.any((alert) => alert.unread))) {
        await _acknowledge(next);
      }
    } catch (_) {
      // Silent: scrolling further retries.
    } finally {
      _loadingMore = false;
    }
  }

  void _openAlert(AlertEntry alert) {
    // Profile content (a comment on your post, a like) and a follow both open
    // the member's wall, not the thread viewer: a profile-post permalink jumps
    // to the post (its redirect resolves the wall page), while a bare member
    // URL just lands on the wall.
    if (isProfilePostUrl(alert.url) || isMemberProfileUrl(alert.url)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(url: alert.url)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumThreadScreen(
          url: alert.url,
          title: alert.title,
          fetchPosts: widget.fetchThreadPosts,
          fetchReactions: widget.fetchReactions,
        ),
      ),
    );
  }

  /// A row tap reads the alert (the site does the same on any click) and then,
  /// if it points somewhere the app can render, opens it. For a type with no
  /// in-app destination the read is the whole action, so it's confirmed by a
  /// toast that also points at the one way to actually see it.
  void _onTapAlert(AlertEntry alert) {
    if (alertIsActionable(alert)) {
      // The reader is leaving for the target, so the read is best-effort here:
      // its failure stays silent, and the bulk ack and next fetch backstop it.
      if (alert.unread) _markRead(alert, surfaceErrors: false);
      _openAlert(alert);
      return;
    }
    // The browser hint only makes sense when there's a link to open; some
    // system notices carry none.
    final hint = alert.url.isNotEmpty ? ' — long-press to open in browser' : '';
    if (alert.unread) {
      _markRead(alert, surfaceErrors: true);
      AppToast.show(context, 'Marked as read$hint');
    } else if (alert.url.isNotEmpty) {
      AppToast.show(context, 'Long-press to open in browser');
    }
  }

  /// Flips one alert's unread tint in place, keyed by its id so a page loaded
  /// after the tap can't shift the wrong row.
  void _setUnread(int alertId, bool unread) {
    for (final group in _groups) {
      final i = group.alerts.indexWhere((alert) => alert.alertId == alertId);
      if (i >= 0) {
        group.alerts[i] = group.alerts[i].copyWith(unread: unread);
        return;
      }
    }
  }

  /// Marks [alert] read optimistically, reverting the tint if the request
  /// fails. [surfaceErrors] toasts that failure — off for the tap that
  /// navigates away, since the reader is no longer looking at this screen.
  Future<void> _markRead(AlertEntry alert, {required bool surfaceErrors}) async {
    setState(() => _setUnread(alert.alertId, false));
    try {
      await (widget.alertReadMarker ?? ForumService.markAlertRead)(alert.alertId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _setUnread(alert.alertId, true));
      if (surfaceErrors) AppToast.show(context, "Couldn't mark read: $e", error: true);
    }
  }

  /// The row menu's read/unread toggle: an explicit action, so its failure
  /// always surfaces.
  Future<void> _toggleRead(AlertEntry alert) async {
    final markUnread = !alert.unread;
    setState(() => _setUnread(alert.alertId, markUnread));
    try {
      final marker = markUnread
          ? (widget.alertUnreadMarker ?? ForumService.markAlertUnread)
          : (widget.alertReadMarker ?? ForumService.markAlertRead);
      await marker(alert.alertId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _setUnread(alert.alertId, !markUnread));
      AppToast.show(context, "Couldn't update alert: $e", error: true);
    }
  }

  Future<void> _launch(String url) async {
    final launch =
        widget.urlLauncher ?? ((uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication));
    await launch(Uri.parse(url));
  }

  /// Whether the currently-loaded feed has an unread row.
  bool get _hasUnread => _groups.any((group) => group.alerts.any((alert) => alert.unread));

  /// The "Mark all read" control only earns its place when the account keeps
  /// alerts unread on view (otherwise opening the feed already read them) and
  /// there's actually something unread to clear.
  bool get _showMarkAll => _popupSkipsMarkRead && _hasUnread;

  /// Reads the whole feed at once, clearing every row's tint optimistically
  /// and restoring them all if the request fails.
  Future<void> _markAllRead() async {
    final wasUnread = [
      for (final group in _groups)
        for (final alert in group.alerts)
          if (alert.unread) alert.alertId,
    ];
    if (wasUnread.isEmpty) return;
    setState(() {
      for (final id in wasUnread) {
        _setUnread(id, false);
      }
    });
    try {
      await (widget.markAllReadMarker ?? ForumService.markAllAlertsRead)();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        for (final id in wasUnread) {
          _setUnread(id, true);
        }
      });
      AppToast.show(context, "Couldn't mark all read: $e", error: true);
    }
  }

  /// The per-row long-press menu: the read/unread toggle (the undo for a tap,
  /// and a manual read for anything the feed left new) plus opening the target
  /// in the browser — the only way to reach a type the app can't render yet.
  Future<void> _showAlertMenu(AlertEntry alert, BuildContext rowContext) async {
    // Long-press earns the heavier buzz; the InkWell's own feedback is off so
    // this is the only one. The shared sheet stays haptic-free for the
    // tap-to-open overflows that don't want it.
    HapticFeedback.vibrate();
    // A long-press acts on the whole row, so the whole row lights — matching
    // its own rounded edge — rather than a single control.
    await showAppActionSheet(
      rowContext,
      anchorRect: menuAnchorRect(rowContext),
      anchorRadius: BorderRadius.circular(10),
      actions: [
        AppSheetAction(
          icon: alert.unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
          label: alert.unread ? 'Mark as read' : 'Mark as unread',
          onTap: () => _toggleRead(alert),
        ),
        if (alert.url.isNotEmpty)
          AppSheetAction(icon: Icons.open_in_browser, label: 'Open in browser', onTap: () => _launch(alert.url)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts', style: TextStyle(fontSize: 16)),
        actions: [
          if (_showMarkAll)
            IconButton(
              tooltip: 'Mark all read',
              icon: const Icon(Icons.done_all, size: 20),
              onPressed: _markAllRead,
            ),
        ],
      ),
      body: _buildBody(colorScheme),
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
            Text('Alerts require an account', style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 13)),
            TextButton(
              onPressed: () async {
                final success = await Navigator.of(
                  context,
                ).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
                if (success == true && mounted) {
                  await _load();
                  if (mounted) await _loadPreference();
                }
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
      return ErrorView(headline: "Couldn't load alerts", detail: _error, onRetry: _errorRetryable ? _load : null);
    }
    if (_groups.isEmpty) {
      return Center(
        child: Text('No alerts yet', style: TextStyle(color: AppColors.of(context).hintText, fontSize: 13)),
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
        padding: EdgeInsets.fromLTRB(8, 4, 8, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              child: Text(
                group.title,
                style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
            for (final alert in group.alerts) _buildRow(colorScheme, alert),
          ],
          if (page != null && _loadedPages < page.totalPages)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(ColorScheme colorScheme, AlertEntry alert) {
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: alert.unread ? colorScheme.primary.withValues(alpha: AppAlphas.highlightWash) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ForumAvatar(username: alert.username, avatarUrl: alert.avatarUrl, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (alert.username.isNotEmpty)
                        TextSpan(
                          text: alert.username,
                          style: TextStyle(
                            // Read drops a step rather than unread rising: at
                            // white-over-brightText the two were 23 points
                            // apart and the state barely showed.
                            color: alert.unread ? AppColors.of(context).brightText : AppColors.of(context).bodyText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      TextSpan(
                        // A system alert (a trophy award) has no actor, so the
                        // action leads the line and drops the actor's space.
                        text: alert.username.isEmpty ? '${alert.action} ' : ' ${alert.action} ',
                        style: TextStyle(color: AppColors.of(context).subtleText),
                      ),
                      for (final label in alert.labels)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: AppAlphas.labelChip),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(label, style: TextStyle(color: colorScheme.primary, fontSize: 9.5)),
                            ),
                          ),
                        ),
                      TextSpan(
                        text: alert.title,
                        style: TextStyle(
                          color: alert.unread ? AppColors.of(context).brightText : AppColors.of(context).bodyText,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (alert.time.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(alert.time, style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5)),
                  ),
              ],
            ),
          ),
          if (alert.unread)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );

    // A tap reads it, then opens it when the app has a screen for it; a type it
    // can't render (a trophy award, other server notices) instead confirms the
    // read and points at the browser. Long-press is the same row menu on every
    // alert: read/unread and open-in-browser.
    // A Builder so the menu can anchor its highlight to this row's own box.
    return Builder(
      builder: (rowContext) => InkWell(
        onTap: () => _onTapAlert(alert),
        onLongPress: () => _showAlertMenu(alert, rowContext),
        // The menu fires its own haptic; InkWell's built-in long-press feedback
        // on top of it was the occasional double-buzz.
        enableFeedback: false,
        borderRadius: BorderRadius.circular(10),
        child: row,
      ),
    );
  }
}
