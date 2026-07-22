import 'package:f95_portal/models/forum.dart';
import 'package:f95_portal/widgets/posted_by_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Wraps the dialog behind a launcher button so `show`'s return value —
  // the applied names, or null on dismissal — can be asserted on.
  Future<void> pumpDialog(
    WidgetTester tester, {
    List<String> initial = const [],
    UserFinder? finder,
    void Function(List<String>?)? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                final names = await PostedByDialog.show(context, initial: initial, finder: finder);
                onResult?.call(names);
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

  testWidgets('typing queries the finder; tapping a suggestion adds it', (tester) async {
    final queries = <String>[];
    List<String>? applied;
    await pumpDialog(
      tester,
      finder: (query) async {
        queries.add(query);
        return const [UserSuggestion(username: 'Bro 04'), UserSuggestion(username: 'bro cha-cha')];
      },
      onResult: (names) => applied = names,
    );

    await tester.enterText(find.byKey(const Key('posted-by-field')), 'Bro');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(queries, ['Bro']);
    expect(find.text('Bro 04'), findsOneWidget);
    expect(find.text('bro cha-cha'), findsOneWidget);

    await tester.tap(find.text('Bro 04'));
    await tester.pump();

    // Chosen: the suggestion list clears, the name stays on as a chip.
    expect(find.text('bro cha-cha'), findsNothing);
    expect(find.text('Bro 04'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, ['Bro 04']);
  });

  testWidgets('a single character does not hit the finder', (tester) async {
    final queries = <String>[];
    await pumpDialog(
      tester,
      finder: (query) async {
        queries.add(query);
        return const [];
      },
    );

    await tester.enterText(find.byKey(const Key('posted-by-field')), 'B');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(queries, isEmpty);
  });

  testWidgets('submitting free text adds it; several names apply together', (tester) async {
    List<String>? applied;
    await pumpDialog(tester, onResult: (names) => applied = names);

    await tester.enterText(find.byKey(const Key('posted-by-field')), 'Alice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('posted-by-field')), 'Bob');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, ['Alice', 'Bob']);
  });

  testWidgets('a name still sitting in the field counts on apply', (tester) async {
    List<String>? applied;
    await pumpDialog(tester, onResult: (names) => applied = names);

    await tester.enterText(find.byKey(const Key('posted-by-field')), 'Ghost');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applied, ['Ghost']);
  });

  testWidgets('initial names show as chips and can be removed', (tester) async {
    List<String>? applied;
    await pumpDialog(tester, initial: const ['Alice', 'Bob'], onResult: (names) => applied = names);

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applied, ['Bob']);
  });

  testWidgets('cancel returns null so the caller keeps its filter', (tester) async {
    List<String>? applied = const ['sentinel'];
    await pumpDialog(tester, initial: const ['Alice'], onResult: (names) => applied = names);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(applied, isNull);
  });
}
