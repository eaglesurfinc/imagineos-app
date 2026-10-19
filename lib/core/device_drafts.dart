import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Best-effort device recovery shared by drawing and page drafts.
/// Account changes fence queued writes before clearing local content.
class DeviceDraftStore {
  static final shared = DeviceDraftStore();
  // Retain the namespace so existing drawing drafts survive this refactor.
  static const prefix = 'imagineos.draft.v1.';
  var generation = 0;
  Future<void> _queue = Future.value();
  String key(String scope, String kind) =>
      '$prefix${sha256.convert(utf8.encode(scope))}.$kind';

  Future<String?> read(String key) async {
    await _queue;
    return SharedPreferencesAsync().getString(key);
  }

  Future<void> write(String key, String value, int session) {
    if (value.length > 3 * 1024 * 1024) {
      return Future.error(const FormatException(
          'This draft is too large for device recovery. Save your work before closing.'));
    }
    return _enqueue(() async {
      if (session == generation) {
        await SharedPreferencesAsync().setString(key, value);
      }
    });
  }

  Future<void> drop(String key, int session) => _enqueue(() async {
        if (session == generation) await SharedPreferencesAsync().remove(key);
      });

  Future<void> invalidate() {
    generation++;
    return _enqueue(() async {
      final prefs = SharedPreferencesAsync();
      final keys = await prefs.getKeys();
      await prefs.clear(
          allowList: keys.where((key) => key.startsWith(prefix)).toSet());
    });
  }

  Future<void> _enqueue(Future<void> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.catchError((Object _) {});
    return result;
  }
}
