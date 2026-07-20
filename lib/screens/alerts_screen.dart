import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/forum_service.dart';
import '../services/site_error.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_view.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/reactions_sheet.dart';
import 'forum_thread_screen.dart';
import 'login_screen.dart';

typedef FetchAlerts = Future<AlertsPage> Function({int page});
typedef AlertsAcknowledger = Future<void> Function(List<int> unreadAlertIds);

/// The account alerts feed: date-grouped rows (actor, action, target
/// thread with its prefix labels), unread highlighting, and load-more
/// pagination. Rows open in the thread viewer.
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

  const AlertsScreen({
    super.key,
    this.fetchAlerts,
    this.alertsAcknowledger,
    this.fetchThreadPosts,
    this.fetchReactions,
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts', style: TextStyle(fontSize: 16))),
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
    return InkWell(
      onTap: () => _openAlert(alert),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: alert.unread ? colorScheme.primary.withValues(alpha: 0.07) : Colors.transparent,
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
                          text: ' ${alert.action} ',
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
                                  color: colorScheme.primary.withValues(alpha: 0.18),
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
      ),
    );
  }
}
