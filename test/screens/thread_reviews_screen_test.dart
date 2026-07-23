import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/screens/thread_reviews_screen.dart';
import 'package:f95_portal/widgets/star_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadReviewsPage twoReviews() => const ThreadReviewsPage(
  reviews: [
    ThreadReview(
      reviewId: 7001,
      author: 'Toaster Moogle',
      authorUrl: 'https://example.com/members/toaster-moogle.1438075/',
      rating: 4,
      date: 'Today at 12:37 AM',
      pieces: [RichPiece.text('Good but not amazing.')],
      likeUrl: 'https://example.com/bratr-ratings/7001/like',
      likeCount: 4,
      reportUrl: 'https://example.com/bratr-ratings/7001/report',
    ),
    ThreadReview(
      reviewId: 7002,
      author: 'Helmrim',
      rating: 2,
      date: 'Yesterday',
      pieces: [RichPiece.text('Grindy and short.')],
    ),
  ],
  csrfToken: 'tok',
);

Widget screen({
  Future<void> Function(int reviewId, String csrfToken)? likeSender,
  ThreadScore? score,
  ThreadReviewsPage? reviewsPage,
  Future<RateForm> Function(String rateUrl)? rateFormFetcher,
  Future<void> Function(String action, String csrfToken, {required int rating, required String message})? ratingSender,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: ThreadReviewsScreen(
    url: 'https://example.com/threads/x.1/br-reviews/',
    title: "Freya's potion Shop",
    score: score,
    fetchReviews: (url, {int page = 1}) async => reviewsPage ?? twoReviews(),
    likeSender: likeSender,
    rateFormFetcher: rateFormFetcher,
    ratingSender: ratingSender,
  ),
);

const ThreadScore ratableScore = ThreadScore(
  rating: 4.3,
  votes: 233,
  reviewsUrl: 'https://example.com/threads/x.1/br-reviews/',
  rateUrl: 'https://example.com/threads/x.1/br-rate',
);

void main() {
  testWidgets('renders each review with its star rating and like count', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Toaster Moogle'), findsOneWidget);
    expect(find.text('Helmrim'), findsOneWidget);
    expect(find.textContaining('Good but not amazing', findRichText: true), findsOneWidget);

    final bars = tester.widgetList<StarBar>(find.byType(StarBar)).toList();
    expect(bars.map((b) => b.rating), containsAll([4.0, 2.0]));

    // The first review's like tally; the second has none and no action.
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Like'), findsOneWidget);
  });

  testWidgets('a summary header shows the thread score', (tester) async {
    await tester.pumpWidget(
      screen(score: const ThreadScore(rating: 4.3, votes: 233, reviewsUrl: 'https://example.com/x/br-reviews/')),
    );
    await tester.pumpAndSettle();

    expect(find.text('4.3'), findsOneWidget);
    expect(find.textContaining('233'), findsOneWidget);
  });

  testWidgets('liking toggles optimistically and posts the toggle', (tester) async {
    final calls = <(int, String)>[];
    await tester.pumpWidget(
      screen(
        likeSender: (reviewId, csrfToken) async {
          calls.add((reviewId, csrfToken));
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Like'));
    await tester.pump();

    expect(calls, [(7001, 'tok')]);
    expect(find.text('Unlike'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    // Tapping again unlikes and restores the tally.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlike'));
    await tester.pump();
    expect(calls, hasLength(2));
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('an unrated thread shows the no-ratings header instead of numbers', (tester) async {
    await tester.pumpWidget(
      screen(
        score: const ThreadScore(rating: 0, votes: 0, reviewsUrl: 'https://example.com/threads/x.1/br-reviews/'),
        reviewsPage: const ThreadReviewsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
  });

  testWidgets('the review FAB opens the composer with stars and the rules pointer', (tester) async {
    final sent = <(String, String, int, String)>[];
    await tester.pumpWidget(
      screen(
        score: ratableScore,
        rateFormFetcher: (rateUrl) async =>
            const RateForm(action: 'https://example.com/threads/x.1/br-rate', csrfToken: 'form-tok'),
        ratingSender: (action, csrfToken, {required rating, required message}) async {
          sent.add((action, csrfToken, rating, message));
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Write a review'));
    await tester.pumpAndSettle();

    expect(find.text('Rate this thread'), findsOneWidget);
    expect(find.textContaining('Reviewing Rules'), findsOneWidget);

    // Submitting without a rating is refused inline.
    await tester.enterText(find.byKey(const Key('composer-message')), 'Solid little game.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a star rating first.'), findsOneWidget);
    expect(sent, isEmpty);

    // Pick four stars and submit for real.
    await tester.tap(find.bySemanticsLabel('4 stars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();

    expect(sent, [('https://example.com/threads/x.1/br-rate', 'form-tok', 4, 'Solid little game.')]);
    // The sheet closed and the reviews reloaded.
    expect(find.text('Rate this thread'), findsNothing);
    expect(find.text('Review submitted'), findsOneWidget);
  });

  testWidgets('no rate endpoint, no FAB', (tester) async {
    await tester.pumpWidget(
      screen(score: const ThreadScore(rating: 4.3, votes: 233, reviewsUrl: 'https://example.com/x/br-reviews/')),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Write a review'), findsNothing);
  });

  testWidgets('a guest form degrades to a sign-in prompt', (tester) async {
    await tester.pumpWidget(screen(score: ratableScore, rateFormFetcher: (rateUrl) async => const RateForm()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Write a review'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to write a review'), findsOneWidget);
    expect(find.text('Rate this thread'), findsNothing);
  });

  testWidgets('a failed like reverts and keeps the action usable', (tester) async {
    await tester.pumpWidget(screen(likeSender: (reviewId, csrfToken) async => throw Exception('down')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Like'));
    // The sender fails at once, so the optimistic flip reverts before the
    // next frame; what matters is the resting state.
    await tester.pumpAndSettle();
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}
