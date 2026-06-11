import 'package:f95_portal/services/settings_service.dart';

class InMemorySettingsStorage implements SettingsStorage {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String value) async => stored = value;
}

/// Swaps in a fresh in-memory SettingsService for the duration of a test.
SettingsService installTestSettings() {
  final service = SettingsService(InMemorySettingsStorage());
  SettingsService.instance = service;
  return service;
}
