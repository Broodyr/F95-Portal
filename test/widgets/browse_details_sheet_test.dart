import 'dart:async';

import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/widgets/remote_image.dart';
import 'package:f95_portal/models/browse_thread.dart';
import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/screens/forum_thread_screen.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:f95_portal/services/forum_service.dart';
import 'package:f95_portal/services/thread_page_service.dart';
import 'package:f95_portal/widgets/screenshot_gallery.dart';
import 'package:f95_portal/widgets/sliding_reveal.dart';
import 'package:f95_portal/widgets/browse_details_sheet.dart';
import 'package:f95_portal/widgets/version_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cookie_storage.dart';
import '../helpers/metadata_test_utils.dart';
import '../helpers/test_data.dart';
import '../helpers/widget_test_utils.dart';

List<String> recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      // HapticFeedback.vibrate() sends no arguments; the impact/selection
      // variants send their HapticFeedbackType as a string.
      haptics.add(call.arguments?.toString() ?? 'vibrate');
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return haptics;
}

BrowseThread detailedThread() => createBrowseThread(
  threadId: 42,
  title: 'College Dreams',
  creator: 'EduDev',
  version: 'v0.8.2',
  views: 2100000,
  likes: 789,
  rating: 4.5,
  date: '5 days',
  prefixes: [7, 18],
  tags: [107, 254],
);

/// Hosts a button that opens the sheet; returns a getter for the popped
/// tag selection and a recorder for launched URLs.
Future<(BrowseTagSelection? Function(), List<Uri>)> pumpDetails(
  WidgetTester tester, {
  BrowseThread? thread,
  FetchThreadPage? fetchThreadPage,
  ThreadActionSender? actionSender,
  SearchCategory category = SearchCategory.games,
}) async {
  BrowseTagSelection? selection;
  final launched = <Uri>[];

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                selection = await BrowseDetailsSheet.show(
                  context,
                  thread ?? detailedThread(),
                  category: category,
                  urlLauncher: (uri) async {
                    launched.add(uri);
                    return true;
                  },
                  fetchThreadPage: fetchThreadPage ?? (id) async => ThreadPage(threadId: id),
                  actionSender: actionSender,
                  fetchThreadPosts: (url, {page = 1}) async => ForumService.createMockThreadPosts(page: page),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  return (() => selection, launched);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    loadAndInstallMetadata();
  });

  testWidgets('renders title, creator, stats, engine, version, and tag names', (tester) async {
    await pumpDetails(tester);

    expect(find.text('College Dreams'), findsOneWidget);
    expect(find.text('by EduDev'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('789'), findsOneWidget);
    expect(find.text('2.1M'), findsOneWidget);
    expect(find.text('5 days'), findsOneWidget);
    expect(find.text("Ren'Py"), findsOneWidget);
    expect(find.textContaining('v0.8.2'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('3dcg'), 100);
    expect(find.text('3dcg'), findsOneWidget);
    expect(find.text('harem'), findsOneWidget);
  });

  testWidgets('hides the version pill for comics and assets', (tester) async {
    for (final category in [SearchCategory.comics, SearchCategory.assets]) {
      await pumpDetails(tester, category: category);
      expect(find.byType(VersionPill), findsNothing, reason: '$category should not show a version');
      expect(find.textContaining('v0.8.2'), findsNothing, reason: '$category should not show a version');
    }
  });

  testWidgets('tapping a tag pops with an additive selection and a light haptic', (tester) async {
    final (getSelection, _) = await pumpDetails(tester);
    final haptics = recordHaptics(tester);

    await tester.scrollUntilVisible(find.text('3dcg'), 100);
    await tester.tap(find.text('3dcg'));
    await tester.pumpAndSettle();

    final selection = getSelection();
    expect(selection, isNotNull);
    expect(selection!.tagId, 107);
    expect(selection.replace, isFalse);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('long-pressing a tag pops with a replace selection and a heavy haptic', (tester) async {
    final (getSelection, _) = await pumpDetails(tester);
    final haptics = recordHaptics(tester);

    await tester.scrollUntilVisible(find.text('harem'), 100);
    await tester.longPress(find.text('harem'));
    await tester.pumpAndSettle();

    final selection = getSelection();
    expect(selection!.tagId, 254);
    expect(selection.replace, isTrue);
    expect(haptics, contains('vibrate'));
  });

  testWidgets('tapping the cover opens it fullscreen in the gallery', (tester) async {
    await pumpDetails(tester, thread: createBrowseThread(threadId: 42, cover: 'https://example.com/cover.png'));

    await tester.tap(find.byKey(const Key('details-cover')));
    // The gallery's loading spinner animates indefinitely (the image never
    // resolves in tests), so pump a fixed route-transition duration instead
    // of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScreenshotGallery), findsOneWidget);
  });

  testWidgets('the gallery gets the HD variant of a preview-host cover', (tester) async {
    await pumpDetails(
      tester,
      thread: createBrowseThread(threadId: 42, cover: 'https://preview.f95zone.to/2023/02/42_cover.png'),
    );

    await tester.tap(find.byKey(const Key('details-cover')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final gallery = tester.widget<ScreenshotGallery>(find.byType(ScreenshotGallery));
    expect(gallery.urls, ['https://attachments.f95zone.to/2023/02/42_cover.png']);

    // cached_network_image leaves pending timers.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('screenshot thumbs stay low-res while the gallery gets HD', (tester) async {
    const screens = ['https://preview.f95zone.to/2023/02/42_s1.png', 'https://preview.f95zone.to/2023/02/42_s2.png'];
    await pumpDetails(tester, thread: createBrowseThread(threadId: 42, screens: screens));

    await tester.scrollUntilVisible(find.text('Screenshots'), 150);
    await tester.pumpAndSettle();

    // The grid renders the low-quality preview URLs as-is.
    thumbFinder(String url) => find.byWidgetPredicate((w) => w is RemoteImage && w.url == url);
    expect(thumbFinder(screens[1]), findsOneWidget);

    await tester.tap(thumbFinder(screens[1]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final gallery = tester.widget<ScreenshotGallery>(find.byType(ScreenshotGallery));
    expect(gallery.urls, [
      'https://attachments.f95zone.to/2023/02/42_s1.png',
      'https://attachments.f95zone.to/2023/02/42_s2.png',
    ]);
    expect(gallery.initialIndex, 1);

    // cached_network_image leaves pending timers.
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('open thread pushes the in-app forum viewer', (tester) async {
    final (_, launched) = await pumpDetails(tester);

    await tester.scrollUntilVisible(find.text('Open thread'), 100);
    await tester.ensureVisible(find.text('Open thread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open thread'));
    await tester.pumpAndSettle();

    // Internal viewer (its app bar keeps the external-browser action);
    // nothing is launched externally.
    expect(find.byType(ForumThreadScreen), findsOneWidget);
    expect(launched, isEmpty);
  });

  testWidgets('the Open thread button uses the enlarged 18pt CTA label', (tester) async {
    await pumpDetails(tester);

    await tester.scrollUntilVisible(find.text('Open thread'), 100);
    expect(effectiveFontSize(tester, find.text('Open thread')), moreOrLessEquals(18));
  });

  testWidgets('screenshot strip appears only when screens exist', (tester) async {
    await pumpDetails(tester);

    expect(find.text('Screenshots'), findsNothing);
  });

  testWidgets('scraped sections render: info grid, overview, downloads', (tester) async {
    final (_, launched) = await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id),
    );

    await tester.scrollUntilVisible(find.text('MockDev'), 150);
    expect(find.text('Developer'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Downloads'), 150);
    expect(find.textContaining('representative mock thread page'), findsOneWidget);

    // Platform switcher: Win is selected by default, its hosts shown.
    await tester.scrollUntilVisible(find.text('PIXELDRAIN'), 150);
    await tester.ensureVisible(find.text('PIXELDRAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIXELDRAIN'));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse('https://example.com/win-pd')]);

    // Switching platform swaps the host list.
    await tester.ensureVisible(find.text('Linux'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Linux'));
    await tester.pumpAndSettle();
    expect(find.text('PIXELDRAIN'), findsNothing);
    await tester.ensureVisible(find.text('MEGA').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MEGA').first);
    await tester.pumpAndSettle();
    expect(launched.last, Uri.parse('https://example.com/linux-mega'));

    // The alternate set renders with its own title and groups.
    await tester.scrollUntilVisible(find.text('Alternate Version (v0.8)'), 150);
    expect(find.text('GOFILE'), findsOneWidget);

    // Extras and attachments render with their host links.
    await tester.scrollUntilVisible(find.text('Full save'), 150);
    expect(find.text('Extras'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Attachments'), 150);
    expect(find.text('mock-2026.torrent'), findsOneWidget);
  });

  testWidgets('rich spoiler content renders links that launch', (tester) async {
    final (_, launched) = await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id),
    );

    await tester.scrollUntilVisible(find.text('Developer Notes'), 150);
    await tester.ensureVisible(find.text('Developer Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Developer Notes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Thanks for'), findsOneWidget);

    // Tap the link inside the rich text.
    await tester.tapOnText(find.textRange.ofSubstring('discord'));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse('https://example.com/discord')]);
  });

  testWidgets('overflowing overview shows a chevron and expands with an animated size change', (tester) async {
    final longOverview = List.filled(60, 'lorem ipsum dolor sit amet consectetur').join(' ');
    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPage(threadId: id, overview: longOverview),
    );

    final overviewText = find.textContaining('lorem ipsum');
    await tester.scrollUntilVisible(overviewText, 150);
    await tester.ensureVisible(overviewText);
    await tester.pumpAndSettle();

    // The card resizes through an AnimatedSize with a nonzero duration,
    // and the overflow affordance is present.
    final animated = tester.widget<AnimatedSize>(find.byKey(const Key('overview-size')));
    expect(animated.duration, greaterThan(Duration.zero));
    expect(find.byKey(const Key('overview-chevron')), findsOneWidget);

    Text overview() => tester.widget<Text>(overviewText);
    expect(overview().maxLines, 5);

    await tester.tap(overviewText);
    await tester.pumpAndSettle();
    expect(overview().maxLines, isNull);

    await tester.ensureVisible(find.byKey(const Key('overview-chevron')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overview-chevron')));
    await tester.pumpAndSettle();
    expect(overview().maxLines, 5);
  });

  testWidgets('short overview has no chevron and ignores taps', (tester) async {
    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPage(threadId: id, overview: 'Short and sweet.'),
    );

    await tester.scrollUntilVisible(find.text('Short and sweet.'), 150);
    expect(find.byKey(const Key('overview-chevron')), findsNothing);

    await tester.tap(find.text('Short and sweet.'));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Short and sweet.')).maxLines, 5);
  });

  testWidgets('spoiler content slides open and closed instead of popping', (tester) async {
    await pumpDetails(tester, fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id));

    await tester.scrollUntilVisible(find.text('Changelog'), 150);
    await tester.ensureVisible(find.text('Changelog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Changelog'));
    await tester.pump();

    // The body mounts immediately and slides open.
    SlidingReveal body() => tester.widget<SlidingReveal>(find.byKey(const Key('spoiler-body-Changelog')));
    expect(body().visible, isTrue);
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixed things'), findsOneWidget);

    // Collapsing keeps the content mounted while it slides shut.
    await tester.tap(find.text('Changelog'));
    await tester.pump();
    expect(body().visible, isFalse);
    expect(find.textContaining('Fixed things'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixed things'), findsNothing);
  });

  testWidgets('spoiler cards expand and collapse', (tester) async {
    await pumpDetails(tester, fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id));

    await tester.scrollUntilVisible(find.text('Changelog'), 150);
    await tester.ensureVisible(find.text('Changelog'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixed things'), findsNothing);

    await tester.tap(find.text('Changelog'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixed things'), findsOneWidget);

    await tester.tap(find.text('Changelog'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fixed things'), findsNothing);
  });

  testWidgets('bookmark posts the XenForo bookmark action and toggles state', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());
    await AuthService.instance.saveCookies({'xf_user': 'tok'});

    final sent = <(String, String, Map<String, String>)>[];
    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id),
      actionSender: (url, csrf, fields) async => sent.add((url, csrf, fields)),
    );

    await tester.scrollUntilVisible(find.byTooltip('Bookmark'), 150);
    await tester.ensureVisible(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();

    // The old Like button is gone: reacting happens inside the thread viewer.
    expect(find.byTooltip('Like'), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(sent.last.$1, 'https://example.com/posts/1/bookmark');
    expect(sent.last.$2, 'mock-csrf');
    expect(sent.last.$3, isEmpty);

    // Removing a bookmark posts delete=1 to the same endpoint.
    await tester.tap(find.byTooltip('Remove bookmark'));
    await tester.pumpAndSettle();
    expect(sent.last.$1, 'https://example.com/posts/1/bookmark');
    expect(sent.last.$3, {'delete': '1'});
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('action failure reverts the optimistic state', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());
    await AuthService.instance.saveCookies({'xf_user': 'tok'});

    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id),
      actionSender: (url, csrf, fields) async => throw Exception('offline'),
    );

    await tester.scrollUntilVisible(find.byTooltip('Bookmark'), 150);
    await tester.ensureVisible(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('a second tap while the toggle is in flight is ignored', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());
    await AuthService.instance.saveCookies({'xf_user': 'tok'});

    // Two taps racing would send opposing bookmark/delete requests, and
    // whichever failed would revert to its own stale snapshot — leaving the
    // icon disagreeing with the server.
    final sent = <Map<String, String>>[];
    final inFlight = Completer<void>();
    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id),
      actionSender: (url, csrf, fields) {
        sent.add(fields);
        return inFlight.future;
      },
    );

    await tester.scrollUntilVisible(find.byTooltip('Bookmark'), 150);
    await tester.ensureVisible(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pump();
    // Optimistically bookmarked, request still open.
    expect(sent, hasLength(1));

    await tester.tap(find.byTooltip('Remove bookmark'));
    await tester.pump();
    expect(sent, hasLength(1));

    // Once it settles the control is live again.
    inFlight.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove bookmark'));
    await tester.pump();
    expect(sent, hasLength(2));
    expect(sent.last, {'delete': '1'});
  });

  testWidgets('logged-out taps prompt for sign-in instead of posting', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());

    final sent = <String>[];
    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id),
      actionSender: (url, csrf, fields) async => sent.add(url),
    );

    await tester.scrollUntilVisible(find.byTooltip('Bookmark'), 150);
    await tester.ensureVisible(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
    expect(find.textContaining('Sign in from the Profile tab'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('logged out with no downloads shows a sign-in notice under Downloads', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());

    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPage(threadId: id, overview: 'A guest-rendered page.'),
    );

    await tester.scrollUntilVisible(find.textContaining('Sign in to see download links'), 150);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('logged in with no downloads omits the Downloads section', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());
    await AuthService.instance.saveCookies({'xf_user': 'tok'});

    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPage(threadId: id, overview: 'A page without downloads.'),
    );

    await tester.scrollUntilVisible(find.text('Open thread'), 150);
    expect(find.text('Downloads'), findsNothing);
    expect(find.textContaining('Sign in to see download links'), findsNothing);
  });

  testWidgets('logged out with parsed downloads shows them, not the notice', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());

    await pumpDetails(tester, fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id));

    await tester.scrollUntilVisible(find.text('Downloads'), 150);
    expect(find.textContaining('Sign in to see download links'), findsNothing);
  });

  testWidgets('signing in inside the pushed viewer refreshes the sheet on return', (tester) async {
    final previousAuth = AuthService.instance;
    addTearDown(() => AuthService.instance = previousAuth);
    AuthService.instance = AuthService(InMemoryCookieStorage());

    await pumpDetails(
      tester,
      // Guest fetches see no downloads; member fetches do.
      fetchThreadPage: (id) async => AuthService.instance.isLoggedIn
          ? ThreadPageService.createMockThreadPage(id)
          : ThreadPage(threadId: id, overview: 'Guest view.'),
    );

    await tester.scrollUntilVisible(find.textContaining('Sign in to see download links'), 150);

    await tester.scrollUntilVisible(find.text('Open thread'), 100);
    await tester.ensureVisible(find.text('Open thread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open thread'));
    await tester.pumpAndSettle();
    expect(find.byType(ForumThreadScreen), findsOneWidget);

    // Sign in while the viewer is on top, then come back.
    await AuthService.instance.saveCookies({'xf_user': 'tok'});
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The sheet refetched as a member: downloads replace the notice.
    expect(find.textContaining('Sign in to see download links'), findsNothing);
    await tester.scrollUntilVisible(find.text('Downloads'), 150);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('page load failure shows an inline retry that recovers', (tester) async {
    int attempts = 0;
    await pumpDetails(
      tester,
      fetchThreadPage: (id) async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
        return ThreadPageService.createMockThreadPage(id);
      },
    );

    await tester.scrollUntilVisible(find.text("Couldn't load thread details"), 150);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load thread details"), findsNothing);
    await tester.scrollUntilVisible(find.text('MockDev'), 150);
    expect(attempts, 2);
  });
}
