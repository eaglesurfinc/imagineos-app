import 'package:flutter/material.dart';

import 'parent_account.dart';
import 'provider_connections.dart';
import 'provider_connections_screen.dart';

class ParentAccessScreen extends StatefulWidget {
  const ParentAccessScreen({super.key, required this.account, this.providers});
  final ParentAccount account;
  final ProviderConnections? providers;

  @override
  State<ParentAccessScreen> createState() => _ParentAccessScreenState();
}

class _ParentAccessScreenState extends State<ParentAccessScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _busy = false;
  String? _message;
  String? _loadedEmail;
  Future<FamilySummary>? _family;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_accountChanged);
    _syncSession();
  }

  void _syncSession() {
    final email = widget.account.email;
    if (email != _loadedEmail) {
      _loadedEmail = email;
      _family = email == null ? null : widget.account.loadFamily();
      _password.clear();
      _message = null;
    }
  }

  void _accountChanged() {
    if (mounted) setState(_syncSession);
  }

  @override
  void didUpdateWidget(covariant ParentAccessScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Returning from the library must reflect newly created creator profiles.
    if (widget.account.email != null && !widget.account.recoveringPassword) {
      _family = widget.account.loadFamily();
    }
  }

  @override
  void dispose() {
    widget.account.removeListener(_accountChanged);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String? success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() {
          _message = success;
          _password.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not complete that request. Check your details, confirm your email if needed, and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (widget.account.recoveringPassword) {
      _run(() => widget.account.updatePassword(password), 'Password updated.');
    } else if (_create) {
      _run(() => widget.account.signUp(email, password),
          'Check your email to confirm your account, then sign in.');
    } else {
      _run(() => widget.account.signIn(email, password), null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final recovery = account.recoveringPassword;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('For parents', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Text('Manage your family account. Children remain the creators.'),
        const SizedBox(height: 16),
        if (account.email != null && !recovery) ...[
          Text('Signed in as ${account.email}'),
          const SizedBox(height: 16),
          FutureBuilder<FamilySummary>(
            key: ValueKey(_loadedEmail),
            future: _family,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Could not load your family. Please try again.'),
                    TextButton(
                      onPressed: () => setState(() {
                        _family = account.loadFamily();
                      }),
                      child: const Text('Retry family'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Text('Loading your family…');
              }
              return Text(
                  'Your family is ready. Child profiles: ${snapshot.data!.childCount}.');
            },
          ),
          const SizedBox(height: 16),
          if (widget.providers != null) ...[
            FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ProviderConnectionsScreen(
                            connections: widget.providers!))),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('AI provider accounts')),
            const SizedBox(height: 16),
          ],
          OutlinedButton(
            onPressed: _busy ? null : () => _run(account.signOut, null),
            child: const Text('Sign out'),
          ),
        ] else
          AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!recovery)
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      decoration:
                          const InputDecoration(labelText: 'Parent email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      validator: (value) => value != null &&
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(value.trim())
                          ? null
                          : 'Enter a valid parent email.',
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    decoration: InputDecoration(
                        labelText: recovery ? 'New password' : 'Password'),
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: [
                      _create || recovery
                          ? AutofillHints.newPassword
                          : AutofillHints.password
                    ],
                    validator: (value) => (value?.length ?? 0) >=
                            (_create || recovery ? 12 : 1)
                        ? null
                        : 'Use ${_create || recovery ? 'at least 12 characters' : 'your password'}.',
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy
                        ? 'Please wait…'
                        : recovery
                            ? 'Save password'
                            : _create
                                ? 'Create parent account'
                                : 'Sign in'),
                  ),
                  if (!recovery) ...[
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _create = !_create;
                                _message = null;
                                _password.clear();
                              }),
                      child: Text(_create
                          ? 'Already have an account? Sign in'
                          : 'Create a parent account'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              final email = _email.text.trim();
                              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(email)) {
                                setState(() => _message =
                                    'Enter your parent email first.');
                                return;
                              }
                              _run(() => account.resetPassword(email),
                                  'If an account exists, check your email for a password reset link.');
                            },
                      child: const Text('Forgot password?'),
                    ),
                    const Text(
                        'Development preview: use adult test accounts only. Do not enter real child information.'),
                  ],
                ],
              ),
            ),
          ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_message!)),
        ],
      ],
    );
  }
}
