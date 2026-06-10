import 'package:f95_portal/screens/profile_screen.dart';
import 'package:f95_portal/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cookie_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService previous;

  setUp(() {
    previous = AuthService.instance;
    AuthService.instance = AuthService(InMemoryCookieStorage());
  });

  tearDown(() {
    AuthService.instance = previous;
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('shows sign-in call to action when logged out', (tester) async {
    await pumpProfile(tester);

    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Sign in to F95Zone'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('shows signed-in state and reacts to session changes', (tester) async {
    await pumpProfile(tester);

    await AuthService.instance.saveCookies({'xf_user': 'tok'});
    await tester.pumpAndSettle();

    expect(find.text('Signed in to F95Zone'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('sign out returns to the logged-out state', (tester) async {
    await AuthService.instance.saveCookies({'xf_user': 'tok'});
    await pumpProfile(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
    expect(AuthService.instance.isLoggedIn, isFalse);
  });
}
