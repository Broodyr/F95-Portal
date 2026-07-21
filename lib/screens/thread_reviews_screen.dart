import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../models/forum.dart';
import '../services/api_service.dart' show ApiException;
import '../services/forum_service.dart';
import '../services/site_error.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_view.dart';
import '../widgets/forum_composer.dart';
import '../widgets/glass_fab.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/reaction_icon.dart';
import '../widgets/report_dialog.dart';
import '../widgets/rich_spoiler_text.dart';
import '../widgets/star_rating.dart';
import 'profile_screen.dart';

typedef FetchThreadReviews = Future<ThreadReviewsPage> Function(String url, {int page});
typedef ReviewLiker = Future<void> Function(int reviewId, String csrfToken);
typedef RateFormFetcher = Future<RateForm> Function(String rateUrl);
typedef RatingSender = Future<void> Function(String action, String csrfToken, {required int rating, required String message});

/// A thread's reviews (`…/br-reviews/`), styled like the thread viewer's
/// post loop. Reviews are read-mostly: the only interactions are Like and
/// Report — the site offers no replying or quoting here, and the viewer's
/// own review is managed on the site.
class ThreadReviewsScreen extends StatefulWidget {
  final String url;

  /// The thread's title, for the app bar; the reviews page itself doesn't
  /// need re-parsing for it.
  final String title;

  /// The aggregate score, shown as a summary header when known.
  final ThreadScore? score;

  final FetchThreadReviews? fetchReviews;
  final ReviewLiker? likeSender;
  final RateFormFetcher? rateFormFetcher;
  final RatingSender? ratingSender;
  final ReportFormFetcher? reportFormFetcher;
  final ReportSender? reportSender;
  final Future<bool> Function(Uri uri)? urlLauncher;

  const ThreadReviewsScreen({
    super.key,
    required this.url,
    required this.title,
    this.score,
    this.fetchReviews,
    this.likeSender,
    this.rateFormFetcher,
    this.ratingSender,
    this.reportFormFetcher,
    this.reportSender,
    this.urlLauncher,
  });

  @override
  State<ThreadReviewsScreen> createState() => _ThreadReviewsScreenState();
}

class _ThreadReviewsScreenState extends State<ThreadReviewsScreen> {
  final ScrollController _scrollController = ScrollController();
  ThreadReviewsPage? _page;
  int _pageNumber = 1;
  bool _loading = true;
  String? _error;
  bool _errorRetryable = true;

  /// Optimistic like flips by review id, applied over the parsed state
  /// until the page reloads.
  final Map<int, bool> _likeFlips = {};

  /// Reviews with a like POST in flight; a second tap waits its turn.
  final Set<int> _likesInFlight = {};

  @override
  void initState() {
    super.initState();
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
      final fetch = widget.fetchReviews ?? ForumService.fetchThreadReviews;
      final page = await fetch(widget.url, page: _pageNumber);
      if (!mounted) return;
      setState(() {
        _page = page;
        _pageNumber = page.currentPage;
        _likeFlips.clear();
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

  void _goToPage(int page) {
    if (page == _pageNumber) return;
    setState(() => _pageNumber = page);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load();
  }

  Future<void> _toggleLike(ThreadReview review) async {
    final csrfToken = _page?.csrfToken ?? '';
    if (_likesInFlight.contains(review.reviewId) || csrfToken.isEmpty) return;
    HapticFeedback.selectionClick();
    _likesInFlight.add(review.reviewId);
    setState(() => _likeFlips[review.reviewId] = !(_likeFlips[review.reviewId] ?? false));
    try {
      final send = widget.likeSender ?? ForumService.likeReview;
      await send(review.reviewId, csrfToken);
    } catch (_) {
      if (mounted) {
        setState(() => _likeFlips[review.reviewId] = !(_likeFlips[review.reviewId] ?? false));
        AppToast.show(context, "Couldn't update the like");
      }
    } finally {
      _likesInFlight.remove(review.reviewId);
    }
  }

  /// Fetches the rate form and opens the review composer: a star picker
  /// above the message field, the site's reviewing-rules pointer below it.
  /// Posting again replaces the viewer's existing review, so the same
  /// sheet is also the edit path.
  Future<void> _openRateSheet() async {
    final rateUrl = widget.score?.rateUrl;
    if (rateUrl == null) return;
    final RateForm form;
    try {
      final fetch = widget.rateFormFetcher ?? ForumService.fetchRateForm;
      form = await fetch(rateUrl);
    } catch (_) {
      if (mounted) AppToast.show(context, "Couldn't load the rating form");
      return;
    }
    if (!mounted) return;
    if (!form.isAvailable) {
      AppToast.show(context, 'Sign in to write a review');
      return;
    }

    // TODO: the pre-filled edit path (initialRating/initialMessage set) is
    // parsed but unverified — confirm against a br-rate fixture saved with
    // an existing review, then label the FAB "Edit your review" when the
    // form comes back pre-filled.
    final rating = ValueNotifier<int>(form.initialRating);
    final posted = await ForumComposer.show(
      context,
      heading: 'Rate this thread',
      submitLabel: 'Submit rating',
      initialMessage: form.initialMessage,
      // Edits arrive seeded from the existing review; drafts are for text
      // that hasn't been posted anywhere yet.
      draftKey: form.initialMessage.isEmpty ? form.action : null,
      header: ValueListenableBuilder<int>(
        valueListenable: rating,
        builder: (context, value, _) => StarPicker(rating: value, onChanged: (star) => rating.value = star),
      ),
      footnote: _buildRulesFootnote(),
      onSubmit: (_, message) async {
        if (rating.value == 0) throw ApiException('Choose a star rating first.');
        final send = widget.ratingSender ?? ForumService.sendRating;
        await send(form.action, form.csrfToken, rating: rating.value, message: message);
      },
    );
    rating.dispose();
    if (posted && mounted) {
      AppToast.show(context, 'Review submitted');
      ForumService.invalidateThreadReviews(widget.url);
      await _load();
    }
  }

  /// "Please read the Reviewing Rules before posting." — the site's own
  /// pointer, kept because the rules are enforced (non-constructive
  /// reviews get removed). The link opens externally for now, like other
  /// forum thread links.
  Widget _buildRulesFootnote() {
    final colorScheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: AppColors.of(context).subtleText, fontSize: 11.5);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Please read the ', style: style),
        GestureDetector(
          onTap: () => _launch(Uri.parse('https://f95zone.to/threads/review-rating-rules-updated-2018-11-23.1753/')),
          child: Text(
            'Reviewing Rules',
            style: style.copyWith(
              color: colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: colorScheme.primary,
            ),
          ),
        ),
        Text(' before posting.', style: style),
      ],
    );
  }

  Future<void> _report(ThreadReview review) {
    return ReportDialog.show(
      context,
      contentUrl: 'https://f95zone.to/bratr-ratings/${review.reviewId}',
      fetchForm: widget.reportFormFetcher,
      sendReport: widget.reportSender,
    );
  }

  void _openProfile(ThreadReview review) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(url: review.authorUrl!, username: review.author),
      ),
    );
  }

  Future<void> _launch(Uri uri) async {
    final launch =
        widget.urlLauncher ?? ((uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication));
    await launch(uri);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final page = _page;
    final int totalPages = page?.totalPages ?? 1;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            Text(
              totalPages > 1 ? 'reviews · page $_pageNumber of $totalPages' : 'reviews',
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
          // The compose spot Reply holds on the thread screen; here the
          // thing composed is a review.
          if (widget.score?.rateUrl != null && page != null)
            Positioned(
              right: 32,
              bottom: MediaQuery.of(context).padding.bottom + 88,
              child: GlassFab(
                icon: Icons.star_outline,
                tooltip: 'Write a review',
                scrollController: _scrollController,
                onPressed: _openRateSheet,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, ThreadReviewsPage? page, int totalPages) {
    if (_loading) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null || page == null) {
      return ErrorView(headline: "Couldn't load the reviews", detail: _error, onRetry: _errorRetryable ? _load : null);
    }

    final score = widget.score;
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 16 + MediaQuery.of(context).viewPadding.bottom),
      children: [
        if (score != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Row(
              children: [
                StarBar(rating: score.rating, starSize: 18),
                const SizedBox(width: 8),
                if (score.rating > 0) ...[
                  Text(
                    score.rating.toStringAsFixed(1),
                    style: TextStyle(
                      color: AppColors.of(context).brightText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· ${score.votes} rating${score.votes == 1 ? '' : 's'}',
                    style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12.5),
                  ),
                ] else
                  Text('No ratings yet', style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12.5)),
              ],
            ),
          ),
        for (final review in page.reviews)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildReviewCard(colorScheme, review),
          ),
        if (totalPages > 1) PaginationBar(page: _pageNumber, totalPages: totalPages, onSelect: _goToPage),
      ],
    );
  }

  Widget _buildReviewCard(ColorScheme colorScheme, ThreadReview review) {
    final bool flipped = _likeFlips[review.reviewId] ?? false;
    final bool liked = flipped ? !review.liked : review.liked;
    final int likeCount = review.likeCount + (flipped ? (review.liked ? -1 : 1) : 0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: review.authorUrl == null ? null : () => _openProfile(review),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      ForumAvatar(username: review.author, avatarUrl: review.avatarUrl),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              review.author,
                              style: TextStyle(
                                color: AppColors.of(context).brightText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              review.date,
                              style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StarBar(rating: review.rating, starSize: 14),
              if (review.reportUrl != null) _buildOverflow(review),
            ],
          ),
          const SizedBox(height: 8),
          RichSpoilerText(pieces: review.pieces, onOpenLink: _launch),
          if (likeCount > 0 || review.likeUrl != null) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                if (likeCount > 0) ...[
                  Icon(Icons.favorite, size: 13, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    '$likeCount',
                    style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 11.5),
                  ),
                ],
                const Spacer(),
                if (review.likeUrl != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleLike(review),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            liked ? Icons.favorite : Icons.favorite_border,
                            size: 14,
                            color: liked ? colorScheme.primary : AppColors.of(context).subtleText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            liked ? 'Unlike' : 'Like',
                            style: TextStyle(
                              color: AppColors.of(context).bodyText,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Same shape as a post card's overflow: report is rare enough that it
  /// doesn't earn a spot in the footer row.
  Widget _buildOverflow(ThreadReview review) {
    return PopupMenuButton<String>(
      tooltip: 'Review tools',
      padding: EdgeInsets.zero,
      color: AppColors.of(context).chipSurface,
      onSelected: (_) => _report(review),
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
}
