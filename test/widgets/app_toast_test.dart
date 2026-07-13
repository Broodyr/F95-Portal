import 'package:f95_portal/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHost(WidgetTester tester, void Function(BuildContext) onTap) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                Center(child: TextButton(onPressed: () => onTap(context), child: const Text('go'))),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a self-sized pill with the message', (tester) async {
    await pumpHost(tester, (context) => AppToast.show(context, 'Image cache cleared.'));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Image cache cleared.'), findsOneWidget);
    // The pill hugs its content instead of spanning the SnackBar's width.
    final pillWidth = tester.getSize(find.ancestor(of: find.text('Image cache cleared.'), matching: find.byType(Container)).first).width;
    expect(pillWidth, lessThan(tester.getSize(find.byType(SnackBar)).width));
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('error variant carries an error icon', (tester) async {
    await pumpHost(tester, (context) => AppToast.show(context, 'Something broke', error: true));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Something broke'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a new toast replaces the current one', (tester) async {
    int count = 0;
    await pumpHost(tester, (context) => AppToast.show(context, 'toast ${++count}'));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('toast 2'), findsOneWidget);
    expect(find.text('toast 1'), findsNothing);
  });
}
