import 'package:f95_portal/constants.dart';
import 'package:f95_portal/services/draft_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_draft_storage.dart';

void main() {
  late InMemoryDraftStorage storage;
  late DraftService service;

  setUp(() {
    storage = InMemoryDraftStorage();
    service = DraftService(storage);
  });

  test('reads back a saved draft under the same key', () async {
    await service.save('https://f95zone.to/threads/1/add-reply', message: 'half a thought');

    final draft = service.read('https://f95zone.to/threads/1/add-reply');
    expect(draft?.message, 'half a thought');
    expect(draft?.title, '');
  });

  test('keeps drafts for different destinations apart', () async {
    await service.save('wall/1', message: 'profile post');
    await service.save('comment/1', message: 'a comment on it');

    expect(service.read('wall/1')?.message, 'profile post');
    expect(service.read('comment/1')?.message, 'a comment on it');
  });

  test('stores the thread title alongside the message', () async {
    await service.save('node/5/post-thread', title: 'My thread', message: 'body');

    final draft = service.read('node/5/post-thread');
    expect(draft?.title, 'My thread');
    expect(draft?.message, 'body');
  });

  test('has no draft for a key that was never written', () {
    expect(service.read('never/seen'), isNull);
  });

  test('clear drops the draft', () async {
    await service.save('threads/1', message: 'text');
    await service.clear('threads/1');

    expect(service.read('threads/1'), isNull);
  });

  test('saving blank title and message drops the draft', () async {
    await service.save('threads/1', message: 'text');
    await service.save('threads/1', message: '   ');

    expect(service.read('threads/1'), isNull);
  });

  test('survives a reload from storage', () async {
    await service.save('threads/1', title: 'T', message: 'kept across restarts');

    final reloaded = DraftService(storage);
    await reloaded.load();

    expect(reloaded.read('threads/1')?.message, 'kept across restarts');
    expect(reloaded.read('threads/1')?.title, 'T');
  });

  test('evicts the oldest draft once the cap is reached', () async {
    for (var i = 0; i <= AppLimits.composerDrafts; i++) {
      await service.save('key/$i', message: 'draft $i');
    }

    // One over the cap: the first-written key is the one that went.
    expect(service.read('key/0'), isNull);
    expect(service.read('key/1')?.message, 'draft 1');
    expect(service.read('key/${AppLimits.composerDrafts}')?.message, 'draft ${AppLimits.composerDrafts}');
  });

  test('re-saving a draft refreshes its place in the eviction order', () async {
    for (var i = 0; i < AppLimits.composerDrafts; i++) {
      await service.save('key/$i', message: 'draft $i');
    }
    // Touch the oldest, then overflow by one: the *second* oldest goes.
    await service.save('key/0', message: 'still being worked on');
    await service.save('key/new', message: 'newest');

    expect(service.read('key/0')?.message, 'still being worked on');
    expect(service.read('key/1'), isNull);
  });

  test('a corrupt store loads as empty rather than throwing', () async {
    storage.stored = 'not json';

    final service = DraftService(storage);
    await service.load();

    expect(service.read('anything'), isNull);
  });
}
