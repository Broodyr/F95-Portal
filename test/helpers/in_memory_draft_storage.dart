import 'package:f95_portal/services/draft_service.dart';

class InMemoryDraftStorage implements DraftStorage {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String value) async => stored = value;
}

/// Swaps in a fresh in-memory DraftService for the duration of a test.
DraftService installTestDrafts() {
  final service = DraftService(InMemoryDraftStorage());
  DraftService.instance = service;
  return service;
}
