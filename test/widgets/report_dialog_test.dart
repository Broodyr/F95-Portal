import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/widgets/report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _form = ReportForm(
  action: 'https://f95zone.to/posts/42/report',
  csrfToken: 'tok',
  reasons: [
    ReportReason(id: 7, label: 'Game update'),
    ReportReason(id: 10, label: 'Inappropriate Behaviour'),
  ],
);

/// Pumps a screen whose only job is to open the dialog on tap.
Future<void> pumpDialog(
  WidgetTester tester, {
  ReportFormFetcher? fetchForm,
  ReportSender? sendReport,
  void Function(bool)? onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final reported = await ReportDialog.show(
                context,
                contentUrl: 'https://f95zone.to/posts/42',
                fetchForm: fetchForm ?? (_) async => _form,
                sendReport: sendReport ?? (action, csrf, {required reasonId, required message}) async {},
              );
              onClosed?.call(reported);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('asks the site for the form at the content URL', (tester) async {
    String? requested;
    await pumpDialog(
      tester,
      fetchForm: (url) async {
        requested = url;
        return _form;
      },
    );

    expect(requested, 'https://f95zone.to/posts/42/report');
    expect(find.text('Game update'), findsOneWidget);
    expect(find.text('Inappropriate Behaviour'), findsOneWidget);
  });

  testWidgets('will not send until a reason is picked', (tester) async {
    await pumpDialog(tester);

    // The site makes the reason a required radio, so the button stays dead
    // until one is chosen rather than filing an uncategorised report.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.text('Game update'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('sends the chosen reason with the form action and token', (tester) async {
    String? sentAction;
    String? sentCsrf;
    int? sentReason;
    String? sentMessage;
    bool? closedWith;

    await pumpDialog(
      tester,
      sendReport: (action, csrf, {required reasonId, required message}) async {
        sentAction = action;
        sentCsrf = csrf;
        sentReason = reasonId;
        sentMessage = message;
      },
      onClosed: (reported) => closedWith = reported,
    );

    await tester.tap(find.text('Inappropriate Behaviour'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('report-message-field')), '  spam bot  ');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(sentAction, 'https://f95zone.to/posts/42/report');
    expect(sentCsrf, 'tok');
    expect(sentReason, 10);
    expect(sentMessage, 'spam bot');
    expect(closedWith, isTrue);
    expect(find.byType(ReportDialog), findsNothing);
  });

  testWidgets('keeps the dialog open and reports the failure when sending throws', (tester) async {
    bool? closedWith;
    await pumpDialog(
      tester,
      sendReport: (action, csrf, {required reasonId, required message}) async => throw Exception('offline'),
      onClosed: (reported) => closedWith = reported,
    );

    await tester.tap(find.text('Game update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    // Still open, so the text typed isn't lost and the send can be retried.
    expect(find.byType(ReportDialog), findsOneWidget);
    expect(closedWith, isNull);
    expect(find.textContaining("Couldn't send the report"), findsOneWidget);
  });

  testWidgets('says so rather than offering a form when the content cannot be reported', (tester) async {
    await pumpDialog(tester, fetchForm: (_) async => const ReportForm());

    expect(find.textContaining("can't be reported"), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('offers a retry when the form fails to load', (tester) async {
    int attempts = 0;
    await pumpDialog(
      tester,
      fetchForm: (_) async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
        return _form;
      },
    );

    expect(find.textContaining("Couldn't load the report form"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Game update'), findsOneWidget);
  });
}
