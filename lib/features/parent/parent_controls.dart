import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ParentControlsCall = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> body, String? grant);

class ParentControlsException implements Exception {
  const ParentControlsException(this.message);
  final String message;
}

class FamilyDataOverview {
  FamilyDataOverview(Map<String, dynamic> data)
      : counts = Map.unmodifiable({
          for (final key in const [
            'child_profiles',
            'characters',
            'versions',
            'original_files',
            'page_drafts',
            'stories',
            'provider_connections'
          ])
            key: _count(data[key]),
        }),
        deletionPending = data['deletion_pending'] == true {
    if (data['generation_enabled'] != false) {
      throw const FormatException('Unsupported parent response');
    }
  }
  final Map<String, int> counts;
  final bool deletionPending;
  static int _count(dynamic value) {
    if (value is! int || value < 0) {
      throw const FormatException('Invalid family overview');
    }
    return value;
  }
}

/// Grants stay in memory and cannot survive reload, leaving parent mode,
/// account changes or app backgrounding. The server separately checks expiry.
class ParentControls extends ChangeNotifier {
  ParentControls(this._call);
  final ParentControlsCall _call;
  String? _grant;
  DateTime? _expires;
  Timer? _timer;
  int _epoch = 0;
  bool _disposed = false;
  bool get unlocked =>
      _grant != null && _expires != null && DateTime.now().isBefore(_expires!);

  Future<void> unlock(String password) async {
    final epoch = ++_epoch;
    final data = await _call({'action': 'unlock', 'password': password}, null);
    final token = data['grant'];
    final expires = DateTime.tryParse(data['expires_at']?.toString() ?? '');
    if (token is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token) ||
        expires == null ||
        !expires.isAfter(DateTime.now()) ||
        expires.difference(DateTime.now()) >
            const Duration(minutes: 5, seconds: 5)) {
      throw const ParentControlsException(
          'Could not unlock parent settings. Try again.');
    }
    if (_disposed || epoch != _epoch) {
      unawaited(_revoke(token));
      throw const ParentControlsException('Parent settings are locked.');
    }
    _grant = token;
    _expires = expires;
    _timer?.cancel();
    _timer = Timer(expires.difference(DateTime.now()), lock);
    notifyListeners();
  }

  Future<void> _revoke(String token) async {
    try {
      await _call({'action': 'lock'}, token);
    } catch (_) {/* Server TTL remains. */}
  }

  void lock() {
    _epoch++;
    final token = _grant;
    _grant = null;
    _expires = null;
    _timer?.cancel();
    if (token != null) unawaited(_revoke(token));
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _protected(Map<String, dynamic> body) async {
    if (!unlocked) {
      lock();
      throw const ParentControlsException('Unlock parent settings first.');
    }
    final epoch = _epoch;
    final result = await _call(body, _grant);
    if (_disposed || epoch != _epoch || !unlocked) {
      throw const ParentControlsException(
          'Parent settings are locked. Reopen them to check the result.');
    }
    return result;
  }

  Future<FamilyDataOverview> overview() async =>
      FamilyDataOverview(await _protected({'action': 'overview'}));

  Future<bool> deleteAccount({String? password, String? confirmation}) async {
    final result = await _protected(password == null
        ? {'action': 'continue_delete'}
        : {
            'action': 'start_delete',
            'password': password,
            'confirmation': confirmation
          });
    if (result['deleted'] == true && result['pending'] == false) return true;
    if (result['deleted'] == false && result['pending'] == true) return false;
    throw const ParentControlsException(
        'Could not confirm deletion. Reopen parent settings to check before retrying.');
  }

  @override
  void dispose() {
    _disposed = true;
    lock();
    super.dispose();
  }
}

class SupabaseParentControls extends ParentControls {
  SupabaseParentControls(SupabaseClient client)
      : super((body, grant) async {
          try {
            final response = await client.functions.invoke('parent-controls',
                body: body,
                headers: {
                  if (grant != null) 'x-imagineos-parent-grant': grant
                });
            final value = response.data;
            if (value is! Map<String, dynamic> ||
                value['contract_version'] != 1 ||
                value['code'] != 'OK')
              throw const FormatException('Invalid parent response');
            return value['data'] == null
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(value['data'] as Map);
          } on FunctionException catch (error) {
            final details = error.details;
            final code = details is Map ? details['code'] : null;
            throw ParentControlsException(switch (code) {
              'PARENT_CONFIRMATION_REQUIRED' =>
                'Check your ImagineOS parent password and try again.',
              'PARENT_LOCKED' =>
                'Parent settings are locked. Unlock them again.',
              'TOO_MANY_ATTEMPTS' =>
                'Too many password attempts. Try again in an hour.',
              'AUTH_REQUIRED' => 'Your session has ended. Sign in again.',
              _ =>
                'Could not confirm this request. Reopen parent settings to check before retrying.',
            });
          } catch (_) {
            throw const ParentControlsException(
                'Could not reach parent settings. Try again.');
          }
        });
}
