import 'package:f95_portal/models/thread_summary.dart';
import 'package:f95_portal/widgets/thread_details_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';
import '../helpers/test_data.dart';

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

  testWidgets('tapping a tag pops with an additive selection', (tester) async {
    final (getSelection, _) = await pumpDetails(tester);

    await tester.scrollUntilVisible(find.text('3dcg'), 100);
    await tester.tap(find.text('3dcg'));
    await tester.pumpAndSettle();

    final selection = getSelection();
    expect(selection, isNotNull);
    expect(selection!.tagId, 107);
    expect(selection.replace, isFalse);
  });

  testWidgets('long-pressing a tag pops with a replace selection', (tester) async {
    final (getSelection, _) = await pumpDetails(tester);

    await tester.scrollUntilVisible(find.text('harem'), 100);
    await tester.longPress(find.text('harem'));
    await tester.pumpAndSettle();

    final selection = getSelection();
    expect(selection!.tagId, 254);
    expect(selection.replace, isTrue);
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
}
