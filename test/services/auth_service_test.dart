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
