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

  /// The numeric member id from the xf_user cookie ("id,token", sometimes
  /// URL-encoded by the webview); null when logged out or unparseable.
  /// It's how the app finds its own profile: `/members/<id>/` redirects to
  /// the canonical member URL.
  int? get userId {
    final raw = _cookies['xf_user'];
    if (raw == null) return null;
    String decoded = raw;
    try {
      decoded = Uri.decodeComponent(raw);
    } catch (_) {}
    return int.tryParse(decoded.split(',').first);
  }

  String? get cookieHeader => _cookies.isEmpty ? null : _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> load() async {
    try {
      final raw = await _storage.read();
      if (raw == null) return;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _cookies = {for (final entry in decoded.entries) entry.key: entry.value.toString()};
      notifyListeners();
    } catch (e) {
      // First line only: secure-storage failures embed a full Java stack.
      debugPrint('AuthService.load failed: ${e.toString().split('\n').first}');
      _cookies = const {};
      // BadPaddingException means the blob is permanently undecryptable
      // (e.g. a debug build reading a release build's encrypted data) and
      // would re-fail on every launch; wipe it. Transient keystore errors
      // don't match and keep the data.
      if (e.toString().contains('BadPaddingException')) {
        try {
          await _storage.delete();
        } catch (_) {}
      }
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
