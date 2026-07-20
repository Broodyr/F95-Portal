import 'dart:async';

import 'package:f95_portal/constants.dart';
import 'package:f95_portal/services/draft_service.dart';
import 'package:f95_portal/services/settings_service.dart';
import 'package:f95_portal/widgets/forum_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_draft_storage.dart';
import '../helpers/in_memory_settings_storage.dart';

/// Opens the composer from a tappable button, the way the screens do, so the
/// sheet can be dismissed and reopened within one test.
Future<void> pumpComposerHost(
  WidgetTester tester, {
  String? draftKey,
  bool withTitle = false,
  String initialMessage = '',
  Future<void> Function(String title, String message)? onSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ForumComposer.show(
              context,
              heading: 'Reply',
              draftKey: draftKey,
              withTitle: withTitle,
              initialMessage: initialMessage,
              onSubmit: onSubmit ?? (_, _) async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> dismissSheet(WidgetTester tester) async {
  // Tapping the barrier is the drag-to-dismiss equivalent: the sheet is
  // popped without a result, so no submit ran.
  await tester.tapAt(const Offset(400, 20));
  await tester.pumpAndSettle();
}

/// Types into a composer field and lets the rebuild land — without the pump
/// the field's onChanged hasn't run, so the submit button is still disabled.
Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

String messageText(WidgetTester tester) => fieldText(tester, 'composer-message');

void main() {
  late SettingsService previousSettings;
  late DraftService previousDrafts;

  setUp(() {
    previousSettings = SettingsService.instance;
    previousDrafts = DraftService.instance;
    installTestSettings();
    installTestDrafts();
  });

  tearDown(() {
    SettingsService.instance = previousSettings;
    DraftService.instance = previousDrafts;
  });

  testWidgets('dismissing the sheet keeps the text for next time', (tester) async {
    await pumpComposerHost(tester, draftKey: 'threads/1/add-reply');

    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'half a thought');
    await dismissSheet(tester);

    await openSheet(tester);
    expect(messageText(tester), 'half a thought');
  });

  testWidgets('a draft belongs to its own destination only', (tester) async {
    await pumpComposerHost(tester, draftKey: 'profile/9/wall');
    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'a profile post');
    await dismissSheet(tester);

    // The comment composer on one of that profile's posts is a different key.
    await pumpComposerHost(tester, draftKey: 'profile-post/44/comment');
    await openSheet(tester);
    expect(messageText(tester), '');
  });

  testWidgets('the new-thread title is restored too', (tester) async {
    await pumpComposerHost(tester, draftKey: 'node/5/post-thread', withTitle: true);

    await openSheet(tester);
    await typeInto(tester, 'composer-title', 'My thread');
    await typeInto(tester, 'composer-message', 'body text');
    await dismissSheet(tester);

    await openSheet(tester);
    expect(
      fieldText(tester, 'composer-title'),
      'My thread',
    );
    expect(messageText(tester), 'body text');
  });

  testWidgets('posting successfully clears the draft', (tester) async {
    await pumpComposerHost(tester, draftKey: 'threads/1/add-reply');

    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'sent for real');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    await openSheet(tester);
    expect(messageText(tester), '');
  });

  testWidgets('posts made in between do not count against the draft cap', (tester) async {
    // One abandoned draft, then a long run of posts that each went out
    // cleanly. Those never accumulate — only drafts left unsent do — so the
    // abandoned one is still there at the end.
    await pumpComposerHost(tester, draftKey: 'threads/1/add-reply');
    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'decided against it for now');
    await dismissSheet(tester);

    for (var i = 0; i < AppLimits.composerDrafts; i++) {
      await pumpComposerHost(tester, draftKey: 'threads/other-$i/add-reply');
      await openSheet(tester);
      await typeInto(tester, 'composer-message', 'post $i');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
    }

    await pumpComposerHost(tester, draftKey: 'threads/1/add-reply');
    await openSheet(tester);
    expect(messageText(tester), 'decided against it for now');
  });

  testWidgets('the fields lock while a post is in flight', (tester) async {
    // Text typed after the request left would be dropped on the floor when
    // the sheet closes, so the fields stop accepting it until the send
    // resolves one way or the other.
    final inFlight = Completer<void>();
    await pumpComposerHost(
      tester,
      draftKey: 'node/5/post-thread',
      withTitle: true,
      onSubmit: (_, _) => inFlight.future,
    );
    await openSheet(tester);
    await typeInto(tester, 'composer-title', 'My thread');
    await typeInto(tester, 'composer-message', 'the real message');

    await tester.tap(find.text('Post'));
    // Not pumpAndSettle: the send is still open and the spinner never stops.
    await tester.pump();

    expect(tester.widget<TextField>(find.byKey(const Key('composer-title'))).readOnly, isTrue);
    expect(tester.widget<TextField>(find.byKey(const Key('composer-message'))).readOnly, isTrue);

    // A send that comes back failed hands the fields straight back.
    inFlight.completeError(Exception('network down'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(const Key('composer-title'))).readOnly, isFalse);
    expect(tester.widget<TextField>(find.byKey(const Key('composer-message'))).readOnly, isFalse);
    expect(messageText(tester), 'the real message');
  });

  testWidgets('a failed post keeps the draft', (tester) async {
    await pumpComposerHost(
      tester,
      draftKey: 'threads/1/add-reply',
      onSubmit: (_, _) async => throw Exception('network down'),
    );

    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'worth keeping');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    await dismissSheet(tester);

    await openSheet(tester);
    expect(messageText(tester), 'worth keeping');
  });

  testWidgets('emptying the field drops the stored draft', (tester) async {
    await pumpComposerHost(tester, draftKey: 'threads/1/add-reply');

    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'never mind');
    await dismissSheet(tester);

    await openSheet(tester);
    await typeInto(tester, 'composer-message', '');
    await dismissSheet(tester);

    expect(DraftService.instance.read('threads/1/add-reply'), isNull);
  });

  testWidgets('a quote is prepended to the draft already in progress', (tester) async {
    await pumpComposerHost(tester, draftKey: 'threads/1/add-reply');
    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'my own words');
    await dismissSheet(tester);

    // Tapping Quote reopens the composer with the quote as initialMessage.
    await pumpComposerHost(
      tester,
      draftKey: 'threads/1/add-reply',
      initialMessage: '[QUOTE="bob"]hi[/QUOTE]\n',
    );
    await openSheet(tester);

    expect(messageText(tester), '[QUOTE="bob"]hi[/QUOTE]\nmy own words');
  });

  testWidgets('an edit composer ignores drafts entirely', (tester) async {
    // Edits pass no draftKey: the fetched BBCode is the only seed, and
    // abandoning an edit must not leave a draft behind to resurrect.
    await pumpComposerHost(tester, initialMessage: 'the existing post body');
    await openSheet(tester);
    await typeInto(tester, 'composer-message', 'edited but abandoned');
    await dismissSheet(tester);

    await openSheet(tester);
    expect(messageText(tester), 'the existing post body');
  });
}
