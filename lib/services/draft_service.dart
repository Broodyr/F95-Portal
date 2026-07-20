import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// Unsent composer text for one posting destination, kept so that dismissing
/// the sheet doesn't throw the work away.
@immutable
class ComposerDraft {
  /// Only the new-thread composer has a title; elsewhere this is empty.
  final String title;
  final String message;

  const ComposerDraft({this.title = '', this.message = ''});

  bool get isEmpty => title.trim().isEmpty && message.trim().isEmpty;

  Map<String, dynamic> toJson() => {'title': title, 'message': message};

  factory ComposerDraft.fromJson(Map<String, dynamic> json) {
    return ComposerDraft(
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

/// Persistence backend; shared_preferences in the app, in-memory in tests.
abstract class DraftStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPrefsDraftStorage implements DraftStorage {
  static const String _key = 'composer_drafts';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async => (await SharedPreferences.getInstance()).setString(_key, value);
}

/// Composer drafts keyed by posting destination, persisted across restarts.
///
/// The key is the form's action URL, which is already distinct per
/// destination: a forum's post-thread URL, a thread's add-reply URL, a
/// profile's wall-post URL, a profile post's comment URL. So a wall post and
/// a comment on one of its posts keep separate drafts without the callers
/// having to invent an identity scheme.
class DraftService extends ChangeNotifier {
  static DraftService instance = DraftService(SharedPrefsDraftStorage());

  final DraftStorage _storage;

  /// Insertion-ordered, oldest first — Dart's map iteration order is what
  /// makes the cap evict the least-recently-saved draft.
  final Map<String, ComposerDraft> _drafts = {};

  DraftService(this._storage);

  Future<void> load() async {
    try {
      final raw = await _storage.read();
      if (raw == null) return;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _drafts.clear();
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          _drafts[entry.key] = ComposerDraft.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('DraftService.load failed: $e');
      _drafts.clear();
    }
  }

  ComposerDraft? read(String key) => _drafts[key];

  /// How many destinations are holding unsent text; drives the settings
  /// screen's clear button, which hides itself at zero.
  int get count => _drafts.length;

  /// Stores the in-progress text for [key]. A draft that is blank (or has
  /// gone blank because the user emptied the field) is removed instead.
  Future<void> save(String key, {String title = '', required String message}) async {
    final draft = ComposerDraft(title: title, message: message);
    if (draft.isEmpty) return clear(key);

    // Re-inserting moves the key to the end of the iteration order, so an
    // actively edited draft isn't the one evicted.
    _drafts.remove(key);
    _drafts[key] = draft;
    while (_drafts.length > AppLimits.composerDrafts) {
      _drafts.remove(_drafts.keys.first);
    }
    notifyListeners();
    await _flush();
  }

  Future<void> clear(String key) async {
    if (_drafts.remove(key) == null) return;
    notifyListeners();
    await _flush();
  }

  /// Wipes every stored draft. Offered in settings because a draft is
  /// otherwise only reachable by navigating back to the exact composer that
  /// wrote it — there is no other way to get unsent text off the device.
  Future<void> clearAll() async {
    if (_drafts.isEmpty) return;
    _drafts.clear();
    notifyListeners();
    await _flush();
  }

  /// Writes never surface to the user: the last save runs from the sheet's
  /// dispose, where nothing is around to await the result or show an error.
  /// The in-memory map is already updated, so the session stays correct even
  /// if the disk write is what failed.
  Future<void> _flush() async {
    try {
      await _storage.write(json.encode({for (final e in _drafts.entries) e.key: e.value.toJson()}));
    } catch (e) {
      debugPrint('DraftService write failed: $e');
    }
  }
}
