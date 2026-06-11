import 'package:f95_portal/models/thread_page.dart';
import 'package:f95_portal/models/thread_summary.dart';
import 'package:f95_portal/services/thread_page_service.dart';
import 'package:f95_portal/widgets/screenshot_gallery.dart';
import 'package:f95_portal/widgets/thread_details_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';
import '../helpers/test_data.dart';

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

ThreadSummary detailedThread() => createThreadSummary(
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

/// Hosts a button that opens the modal; returns a getter for the popped
/// tag selection and a recorder for launched URLs.
Future<(ThreadTagSelection? Function(), List<Uri>)> pumpDetails(
  WidgetTester tester, {
  ThreadSummary? thread,
  FetchThreadPage? fetchThreadPage,
}) async {
  ThreadTagSelection? selection;
  final launched = <Uri>[];

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                selection = await ThreadDetailsModal.show(
                  context,
                  thread ?? detailedThread(),
                  urlLauncher: (uri) async {
                    launched.add(uri);
                    return true;
                  },
                  fetchThreadPage: fetchThreadPage ?? (id) async => ThreadPage(threadId: id),
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
    await pumpDetails(tester, thread: createThreadSummary(threadId: 42, cover: 'https://example.com/cover.png'));

    await tester.tap(find.byKey(const Key('details-cover')));
    // The gallery's loading spinner animates indefinitely (the image never
    // resolves in tests), so pump a fixed route-transition duration instead
    // of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScreenshotGallery), findsOneWidget);
  });

  testWidgets('open thread launches the canonical thread URL', (tester) async {
    final (_, launched) = await pumpDetails(tester);

    await tester.scrollUntilVisible(find.text('Open thread'), 100);
    await tester.ensureVisible(find.text('Open thread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open thread'));
    await tester.pumpAndSettle();

    expect(launched, [Uri.parse('https://f95zone.to/threads/42/')]);
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
    await tester.tap(find.text('PIXELDRAIN'));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse('https://example.com/win-pd')]);

    // Switching platform swaps the host list.
    await tester.tap(find.text('Linux'));
    await tester.pumpAndSettle();
    expect(find.text('PIXELDRAIN'), findsNothing);
    await tester.tap(find.text('MEGA'));
    await tester.pumpAndSettle();
    expect(launched.last, Uri.parse('https://example.com/linux-mega'));

    // Extras render with their host links.
    expect(find.text('Extras'), findsOneWidget);
    expect(find.text('Full save'), findsOneWidget);
  });

  testWidgets('spoiler cards expand and collapse', (tester) async {
    await pumpDetails(
      tester,
      fetchThreadPage: (id) async => ThreadPageService.createMockThreadPage(id),
    );

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
