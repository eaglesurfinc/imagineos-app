import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ParentAccount extends ChangeNotifier {
  String? get email;
  bool get recoveringPassword;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> updatePassword(String password);
  Future<void> signOut();
}

class SupabaseParentAccount extends ParentAccount {
  SupabaseParentAccount(this.client) {
    _subscription = client.auth.onAuthStateChange.listen((state) {
      _recovering = state.event == AuthChangeEvent.passwordRecovery ||
          (_recovering && state.session != null);
      notifyListeners();
    }, onError: (Object _) {
      // The next user action can retry; never expose tokens or raw errors.
      notifyListeners();
    });
  }

  final SupabaseClient client;
  late final StreamSubscription<AuthState> _subscription;
  bool _recovering = false;
  @override
  String? get email => client.auth.currentSession?.user.email;
  @override
  bool get recoveringPassword => _recovering;

  String get _redirect => Uri.base.origin;

  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUp(String email, String password) async {
    await client.auth
        .signUp(email: email, password: password, emailRedirectTo: _redirect);
  }

  @override
  Future<void> resetPassword(String email) =>
      client.auth.resetPasswordForEmail(email, redirectTo: _redirect);

  @override
  Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
    _recovering = false;
    notifyListeners();
  }

  @override
  Future<void> signOut() => client.auth.signOut();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
