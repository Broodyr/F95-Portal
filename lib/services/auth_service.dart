import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence backend for the session cookies; secure storage in the app,
/// in-memory fakes in tests.
abstract class CookieStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureCookieStorage implements CookieStorage {
  static const String _key = 'f95_session_cookies';
  final FlutterSecureStorage _storage;

  const SecureCookieStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Holds the F95Zone (XenForo) session cookies captured from the login
/// webview. `xf_user` is the long-lived remember-me token; its presence is
/// what makes a session count as logged in. All requests attach the cookies
/// via [cookieHeader], which lifts the anonymous hourly rate limit.
class AuthService extends ChangeNotifier {
  static AuthService instance = AuthService(const SecureCookieStorage());

  final CookieStorage _storage;
  Map<String, String> _cookies = const {};

  AuthService(this._storage);

  bool get isLoggedIn => _cookies.containsKey('xf_user');

  String? get cookieHeader => _cookies.isEmpty ? null : _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> load() async {
    try {
      final raw = await _storage.read();
      if (raw == null) return;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _cookies = {for (final entry in decoded.entries) entry.key: entry.value.toString()};
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.load failed: $e');
      _cookies = const {};
    }
  }

  Future<void> saveCookies(Map<String, String> cookies) async {
    _cookies = Map.unmodifiable(cookies);
    await _storage.write(json.encode(cookies));
    notifyListeners();
  }

  Future<void> logout() async {
    _cookies = const {};
    await _storage.delete();
    notifyListeners();
  }
}
