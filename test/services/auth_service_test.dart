import 'package:f95_portal/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cookie_storage.dart';

void main() {
  late InMemoryCookieStorage storage;
  late AuthService auth;

  setUp(() {
    storage = InMemoryCookieStorage();
    auth = AuthService(storage);
  });

  group('AuthService', () {
    test('starts logged out with no cookie header', () {
      expect(auth.isLoggedIn, isFalse);
      expect(auth.cookieHeader, isNull);
    });

    test('saveCookies persists and builds the Cookie header', () async {
      await auth.saveCookies({'xf_user': 'abc123', 'xf_session': 's1'});

      expect(auth.isLoggedIn, isTrue);
      expect(auth.cookieHeader, 'xf_user=abc123; xf_session=s1');
      expect(storage.stored, isNotNull);
    });

    test('load restores a persisted session', () async {
      await auth.saveCookies({'xf_user': 'abc123'});

      final fresh = AuthService(storage);
      expect(fresh.isLoggedIn, isFalse);
      await fresh.load();

      expect(fresh.isLoggedIn, isTrue);
      expect(fresh.cookieHeader, 'xf_user=abc123');
    });

    test('userId parses the id prefix of the xf_user cookie', () async {
      await auth.saveCookies({'xf_user': '328002,sometoken'});
      expect(auth.userId, 328002);
    });

    test('userId handles URL-encoded cookie values from the webview', () async {
      await auth.saveCookies({'xf_user': '1957582%2Cabc%20def'});
      expect(auth.userId, 1957582);
    });

    test('userId is null when logged out or unparseable', () async {
      expect(auth.userId, isNull);
      await auth.saveCookies({'xf_user': 'garbage'});
      expect(auth.userId, isNull);
    });

    test('session cookies alone do not count as logged in', () async {
      await auth.saveCookies({'xf_session': 'only-session'});

      expect(auth.isLoggedIn, isFalse);
      expect(auth.cookieHeader, 'xf_session=only-session');
    });

    test('logout clears memory and storage', () async {
      await auth.saveCookies({'xf_user': 'abc123'});
      await auth.logout();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.cookieHeader, isNull);
      expect(storage.stored, isNull);
    });

    test('load tolerates corrupt storage contents', () async {
      storage.stored = 'not json {{{';

      await auth.load();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.cookieHeader, isNull);
    });
  });
}
