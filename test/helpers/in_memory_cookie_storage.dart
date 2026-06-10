import 'package:f95_portal/services/auth_service.dart';

class InMemoryCookieStorage implements CookieStorage {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String value) async => stored = value;

  @override
  Future<void> delete() async => stored = null;
}
