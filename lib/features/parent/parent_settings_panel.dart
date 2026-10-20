import 'package:flutter/material.dart';

import 'parent_account.dart';
import 'parent_controls.dart';
import 'provider_connections.dart';
import 'provider_connections_screen.dart';
import 'parent_children_screen.dart';

class ParentSettingsPanel extends StatefulWidget {
  const ParentSettingsPanel(
      {super.key,
      required this.account,
      required this.controls,
      this.providers,
      this.startChild,
      this.familyLibraryBuilder});
  final ParentAccount account;
  final ParentControls controls;
  final ProviderConnections? providers;
  final Future<void> Function(String code)? startChild;
  final WidgetBuilder? familyLibraryBuilder;
  @override
  State<ParentSettingsPanel> createState() => _ParentSettingsPanelState();
}

class _ParentSettingsPanelState extends State<ParentSettingsPanel>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  Future<({FamilyDataOverview? data, bool failed})>? _overview;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controls.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      _password.clear();
      _overview = widget.controls.unlocked ? _loadOverview() : null;
    });
  }

  Future<({FamilyDataOverview? data, bool failed})> _loadOverview() async {
    try {
      return (data: await widget.controls.overview(), failed: false);
    } catch (_) {
      return (data: null, failed: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.controls.lock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controls.removeListener(_changed);
    widget.controls.lock();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on ParentControlsException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted)
        setState(
            () => _message = 'Could not complete this request. Try again.');
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _password.clear();
        });
    }
  }

  Future<void> _delete(bool pending) async {
    if (!pending) {
      final details =
          await showDialog<({String password, String confirmation})>(
              context: context, builder: (_) => const _DeleteFamilyDialog());
      if (details == null || !mounted || !widget.controls.unlocked) return;
      await _run(() async {
        final deleted = await widget.controls.deleteAccount(
            password: details.password, confirmation: details.confirmation);
        await _deletionResult(deleted);
      });
    } else {
      await _run(
          () async => _deletionResult(await widget.controls.deleteAccount()));
    }
  }

  Future<void> _deletionResult(bool deleted) async {
    if (deleted) {
      widget.controls.lock();
      await widget.account.signOut();
    } else if (mounted) {
      setState(() {
        _overview = _loadOverview();
        _message =
            'Deletion is in progress. Choose Finish deleting account to continue. New cloud saves are blocked.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.controls.unlocked) ...[
        const Icon(Icons.lock_outline, size: 40),
        const SizedBox(height: 12),
        const Text(
            'Parent settings are locked. Enter your ImagineOS parent password to continue. Children do not need this password.'),
        const SizedBox(height: 12),
        TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Parent password'),
            onSubmitted: (_) {
              if (!_busy && _password.text.isNotEmpty)
                _run(() => widget.controls.unlock(_password.text));
            }),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() => widget.controls.unlock(_password.text)),
            child: Text(_busy ? 'Please wait…' : 'Unlock parent settings')),
        const Text(
            'Settings lock when you leave, put the app in the background, or after five minutes.'),
        TextButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await widget.account.resetPassword(widget.account.email!);
                      if (mounted)
                        setState(() => _message =
                            'Check your parent email for a password reset link.');
                    }),
            child: const Text('Forgot parent password?')),
        TextButton(
            onPressed: _busy ? null : () => _run(widget.account.signOut),
            child: const Text('Sign out')),
      ] else ...[
        Text('Signed in as ${widget.account.email}'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _busy ? null : widget.controls.lock,
            icon: const Icon(Icons.lock),
            label: const Text('Lock parent settings')),
        const SizedBox(height: 16),
        FutureBuilder<({FamilyDataOverview? data, bool failed})>(
            future: _overview,
            builder: (context, snapshot) {
              if (snapshot.data?.failed ?? false)
                return Column(children: [
                  const Text(
                      'Could not load your family data. Unlock again if the parent session expired.'),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _overview = _loadOverview();
                              }),
                      child: const Text('Retry family overview')),
                ]);
              final data = snapshot.data?.data;
              if (data == null) return const Text('Loading family overview…');
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!data.deletionPending) ...[
                      FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => ParentChildrenScreen(
                                          controls: widget.controls,
                                          startOnThisDevice:
                                              widget.startChild))),
                          icon: const Icon(Icons.child_care),
                          label: const Text('Children and sign-in approvals')),
                      if (widget.familyLibraryBuilder != null)
                        OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: widget.familyLibraryBuilder!)),
                            icon: const Icon(Icons.folder_outlined),
                            label: const Text('Review family creations')),
                      const SizedBox(height: 16),
                    ],
                    Text('Your family data',
                        style: Theme.of(context).textTheme.titleLarge),
                    for (final entry in const {
                      'child_profiles': 'Child profiles',
                      'characters': 'Characters',
                      'versions': 'Drawing versions',
                      'original_files': 'Stored image files',
                      'page_drafts': 'Page drafts',
                      'stories': 'Organized stories',
                      'provider_connections': 'AI provider connections',
                    }.entries)
                      Text('${entry.value}: ${data.counts[entry.key]}'),
                    const SizedBox(height: 16),
                    const Text(
                        'Cloud: your parent email, creator nicknames, original drawings, versions and saved stories are held in your private family account. Provider API keys are stored in the server vault and are never sent back to this device.'),
                    const SizedBox(height: 12),
                    const Text(
                        'Device: unfinished drawings and story work may be stored on this browser or device for recovery. This is best-effort storage, not a backup. Signing out clears this app’s drafts on this device. Downloads and copies on other devices remain under your control.'),
                    const SizedBox(height: 12),
                    const Text(
                        'AI illustrations remain disabled. Connecting an API key does not turn generation on. Drawings and story words are not sent to providers by this preview. Subscription sign-in is available only when a provider officially permits this use.'),
                    const SizedBox(height: 12),
                    const Text(
                        'USA development preview: adult-created test content only. Parent sign-in does not verify legal guardianship or complete parental consent. Pilot consent, retention schedules and backup expiry still require review.'),
                    const SizedBox(height: 16),
                    if (widget.providers != null && !data.deletionPending)
                      FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => ListenableBuilder(
                                      listenable: widget.controls,
                                      builder: (context, _) => widget
                                              .controls.unlocked
                                          ? ProviderConnectionsScreen(
                                              connections: widget.providers!)
                                          : Scaffold(
                                              appBar: AppBar(
                                                  title: const Text(
                                                      'Parent settings locked')),
                                              body: const Center(child: Text('Return to For parents and unlock settings again.')))))),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('AI provider accounts')),
                    const SizedBox(height: 16),
                    Text(
                        data.deletionPending
                            ? 'Family deletion in progress'
                            : 'Delete family account',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text(
                        'Permanently removes every child profile, drawing, version, saved story and provider connection in this family, then removes the parent account and its sessions. Save any copies you want first. Completed deletion cannot be undone. Existing downloads and provider-held records are not erased by ImagineOS.'),
                    OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _delete(data.deletionPending),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: Text(data.deletionPending
                            ? 'Finish deleting account'
                            : 'Delete my account')),
                  ]);
            }),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      widget.controls.lock();
                      await widget.account.signOut();
                    }),
            child: const Text('Sign out')),
      ],
      if (_message != null)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(liveRegion: true, child: Text(_message!))),
    ]);
  }
}

class _DeleteFamilyDialog extends StatefulWidget {
  const _DeleteFamilyDialog();
  @override
  State<_DeleteFamilyDialog> createState() => _DeleteFamilyDialogState();
}

class _DeleteFamilyDialogState extends State<_DeleteFamilyDialog> {
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Permanently delete the entire family?'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'This begins irreversible deletion of all family profiles, drawings and stories. If interrupted, sign back in to finish. It cannot restore your work. Type DELETE MY FAMILY and confirm your parent password.'),
          const SizedBox(height: 12),
          TextField(
              controller: _confirmation,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(labelText: 'Type DELETE MY FAMILY')),
          const SizedBox(height: 12),
          TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(labelText: 'Confirm parent password')),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep family account')),
          FilledButton(
              onPressed: _confirmation.text == 'DELETE MY FAMILY' &&
                      _password.text.isNotEmpty
                  ? () => Navigator.pop(context, (
                        password: _password.text,
                        confirmation: _confirmation.text
                      ))
                  : null,
              child: const Text('Permanently delete family')),
        ],
      );
}
