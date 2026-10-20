import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef ChildCall = Future<dynamic> Function(
    Map<String, dynamic> body, String? secret);

class ChildAccessException implements Exception {
  const ChildAccessException(this.message, {this.approvalRequired = false});
  final String message;
  final bool approvalRequired;
}

class ChildSession {
  ChildSession(Map<String, dynamic> value)
      : childId = value['child_id'] as String,
        id = value['session_id'] as String,
        nickname = value['nickname'] as String,
        allowExport = value['allow_export'] as bool,
        remaining = DateTime.parse(value['expires_at'] as String)
            .difference(DateTime.parse(value['server_time'] as String)) {
    if (value['ai_enabled'] != false ||
        remaining <= Duration.zero ||
        remaining > const Duration(hours: 8))
      throw const FormatException('Invalid approval');
  }
  final String childId, id, nickname;
  final bool allowExport;
  final Duration remaining;
}

/// A child capability lives only in memory. Each new sign-in needs a new
/// single-use parent approval; neither refresh nor activity extends its deadline.
class ChildAccess extends ChangeNotifier {
  ChildAccess(this._transport);
  final ChildCall _transport;
  ChildSession? session;
  bool childMode = false, suspended = false;
  String? message;
  String? _secret, _attemptCode, _attemptId, _attemptSecret;
  Timer? _expiry, _poll;
  Stopwatch? _clock;
  Duration _allowed = Duration.zero;
  bool _disposed = false;
  Future<void>? _verification;
  int _epoch = 0;
  Duration get remaining => _allowed - (_clock?.elapsed ?? Duration.zero);
  bool get active =>
      session != null && _secret != null && remaining > Duration.zero;
  void beginEntry() {
    childMode = true;
    end();
  }

  void leaveMode() {
    end();
    childMode = false;
    notifyListeners();
  }

  void suspend() {
    if (active) {
      suspended = true;
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (!suspended) return;
    final epoch = _epoch;
    await verify();
    if (!_disposed && epoch == _epoch) {
      suspended = false;
      notifyListeners();
    }
  }

  static String _randomSecret() {
    final random = Random.secure();
    return List.generate(
            32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> signIn(String input) async {
    final code = input.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(code)) {
      throw const ChildAccessException(
          'Ask your parent for a new sign-in code and paste it here.');
    }
    if (session != null) end();
    final epoch = ++_epoch;
    _verification = null;
    if (_attemptCode != code) {
      _attemptCode = code;
      _attemptId = const Uuid().v4();
      _attemptSecret = _randomSecret();
    }
    final secret = _attemptSecret!;
    final watch = Stopwatch()..start();
    final data = await _transport({
      'action': 'login',
      'code': code,
      'request_id': _attemptId,
      'secret': secret
    }, null);
    final next = ChildSession(Map<String, dynamic>.from(data as Map));
    if (_disposed || epoch != _epoch) {
      unawaited(_logout(secret));
      throw const ChildAccessException(
          'Sign-in was cancelled. Ask your parent for a new approval.');
    }
    _secret = secret;
    childMode = true;
    suspended = false;
    session = next;
    _attemptCode = _attemptId = _attemptSecret = null;
    message = null;
    _setDeadline(next.remaining - watch.elapsed);
    if (!active)
      throw const ChildAccessException(
          'This approval has expired. Ask your parent for a new code.',
          approvalRequired: true);
    _poll?.cancel();
    _poll =
        Timer.periodic(const Duration(seconds: 15), (_) => unawaited(verify()));
    if (active) notifyListeners();
  }

  void _setDeadline(Duration allowed) {
    _allowed = allowed;
    _clock = Stopwatch()..start();
    _expiry?.cancel();
    if (allowed <= Duration.zero) {
      end('Your time is up. Ask your parent to approve another sign-in.');
    } else {
      _expiry = Timer(
          allowed,
          () => end(
              'Your time is up. Ask your parent to approve another sign-in.'));
    }
  }

  Future<dynamic> call(Map<String, dynamic> body) async {
    if (!active) {
      end('Ask your parent to approve a new sign-in.');
      throw const ChildAccessException(
          'Ask your parent to approve a new sign-in.',
          approvalRequired: true);
    }
    final epoch = _epoch;
    try {
      final value = await _transport(body, _secret);
      if (_disposed || epoch != _epoch || !active)
        throw const ChildAccessException('This session has ended.',
            approvalRequired: true);
      return value;
    } on ChildAccessException catch (error) {
      if (error.approvalRequired && !_disposed && epoch == _epoch)
        end(error.message);
      rethrow;
    }
  }

  Future<void> verify() {
    if (_verification != null) return _verification!;
    late Future<void> task;
    task = _verify().whenComplete(() {
      if (identical(_verification, task)) _verification = null;
    });
    _verification = task;
    return task;
  }

  Future<void> _verify() async {
    if (!active) {
      if (session != null)
        end('Your time is up. Ask your parent to approve another sign-in.');
      return;
    }
    final epoch = _epoch, watch = Stopwatch()..start();
    try {
      final data = await call({'action': 'status'});
      if (_disposed || epoch != _epoch || !active) return;
      final next = ChildSession(Map<String, dynamic>.from(data as Map));
      if (next.id != session!.id || next.childId != session!.childId)
        throw const FormatException();
      final changed = next.allowExport != session!.allowExport;
      session = next;
      // Conservatively shorten, never extend, the original local deadline.
      final serverRemaining = next.remaining - watch.elapsed;
      _setDeadline(serverRemaining < remaining ? serverRemaining : remaining);
      if (changed && active) notifyListeners();
    } catch (_) {
      if (!_disposed && epoch == _epoch)
        end('Your session could not be confirmed. Ask your parent to approve a new sign-in.');
    }
  }

  Future<void> authorizeExport() async {
    await call({'action': 'authorize_export'});
  }

  Future<void> _logout(String secret) async {
    try {
      await _transport({'action': 'logout'}, secret);
    } catch (_) {/* Server expiry still applies. */}
  }

  void end([String? reason]) {
    _epoch++;
    _verification = null;
    final secret = _secret;
    _secret = null;
    session = null;
    suspended = false;
    _attemptCode = _attemptId = _attemptSecret = null;
    _expiry?.cancel();
    _poll?.cancel();
    _clock?.stop();
    message = reason ?? 'Ask your parent to approve your next sign-in.';
    if (secret != null) unawaited(_logout(secret));
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    end();
    super.dispose();
  }
}

ChildAccess supabaseChildAccess(SupabaseClient publicClient) =>
    ChildAccess((body, secret) async {
      try {
        final response = await publicClient.functions.invoke('child-access',
            body: body,
            headers: {if (secret != null) 'x-imagineos-child-session': secret});
        if (response.data is Uint8List) return response.data;
        final value = response.data;
        if (value is! Map ||
            value['contract_version'] != 1 ||
            value['code'] != 'OK') throw const FormatException();
        return value['data'];
      } on FunctionException catch (error) {
        final details = error.details;
        final code = details is Map ? details['code'] : null;
        throw ChildAccessException(
            code == 'CHILD_APPROVAL_REQUIRED'
                ? 'This approval has ended or is unavailable. Ask your parent for a new code.'
                : 'Could not complete this request. Your saved work is kept. Try again.',
            approvalRequired: code == 'CHILD_APPROVAL_REQUIRED');
      } catch (_) {
        throw const ChildAccessException(
            'Could not reach your studio. Keep your working copy and try again.');
      }
    });
