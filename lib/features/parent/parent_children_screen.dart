import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'parent_controls.dart';

class ParentChildrenScreen extends StatefulWidget {
  const ParentChildrenScreen(
      {super.key, required this.controls, this.startOnThisDevice});
  final ParentControls controls;
  final Future<void> Function(String code)? startOnThisDevice;
  @override
  State<ParentChildrenScreen> createState() => _ParentChildrenScreenState();
}

class _ParentChildrenScreenState extends State<ParentChildrenScreen> {
  final _nickname = TextEditingController();
  Map<String, dynamic>? _data;
  String? _message;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.controls.children();
      if (mounted && widget.controls.unlocked) setState(() => _data = data);
    } catch (_) {
      if (mounted)
        setState(() => _message =
            'Could not load child access. Unlock parent settings again if needed.');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _load();
    } on ParentControlsException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _message =
            'Could not confirm this update. Refresh child access before retrying.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Map profile, int minutes) async {
    final approval =
        await widget.controls.approveChild(profile['id'] as String, minutes);
    if (!mounted || !widget.controls.unlocked) return;
    final code = approval['code'] as String;
    final start = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(
                    'Approve ${profile['nickname']} for $minutes ${minutes == 1 ? 'minute' : 'minutes'}'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const Text(
                          'This code approves one sign-in and must be used within 10 minutes. Time starts when the child signs in. Give it only to this child. A new sign-in always needs a new approval.'),
                      const SizedBox(height: 16),
                      SelectableText(code,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy code for another device')),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Done')),
                  if (widget.startOnThisDevice != null)
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child:
                            const Text('Start child session on this device')),
                ]));
    if (start == true && mounted && widget.controls.unlocked)
      await widget.startOnThisDevice!(code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Children and sign-in approvals')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
              'Every child sign-in needs your approval. You choose the time; expiry or End session blocks access until you approve again. Children never use your password or AI provider keys.'),
          const SizedBox(height: 16),
          TextField(
              controller: _nickname,
              maxLength: 40,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Child nickname')),
          FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final nickname = _nickname.text.trim();
                        if (nickname.isEmpty)
                          throw const ParentControlsException(
                              'Enter a nickname. A child email is not needed.');
                        await widget.controls.addChild(nickname);
                        _nickname.clear();
                      }),
              child: const Text('Add child profile')),
          if (_data == null)
            TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Load child access')),
          for (final profile in (_data?['profiles'] as List? ?? []))
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _ChildAccessCard(
                    key: ValueKey(profile.toString()),
                    profile: Map<String, dynamic>.from(profile as Map),
                    busy: _busy,
                    save: (minutes, export, blocked) => _run(() =>
                        widget.controls.setChildAccess(
                            profile['id'] as String, minutes, export, blocked)),
                    approve: (minutes) =>
                        _run(() => _approve(profile, minutes)))),
          const SizedBox(height: 24),
          Text('Active child sessions',
              style: Theme.of(context).textTheme.titleLarge),
          const Text(
              'End a session to block new cloud requests immediately. The child screen checks for revocation regularly. Changing the default duration applies to new approvals and never extends an active session.'),
          for (final session in (_data?['sessions'] as List? ?? []))
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(session['nickname'] as String),
                subtitle: Text(
                    'Ends ${TimeOfDay.fromDateTime(DateTime.parse(session['expires_at'] as String).toLocal()).format(context)}'),
                trailing: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.controls
                            .endChildSession(session['id'] as String)),
                    child: const Text('End session'))),
          TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh child access')),
          const Text(
              'AI illustrations remain disabled. Export permission controls ImagineOS save/print actions; it cannot prevent screenshots or copies already downloaded.'),
          if (_message != null)
            Semantics(liveRegion: true, child: Text(_message!)),
        ]),
      );
}

class _ChildAccessCard extends StatefulWidget {
  const _ChildAccessCard(
      {super.key,
      required this.profile,
      required this.busy,
      required this.save,
      required this.approve});
  final Map<String, dynamic> profile;
  final bool busy;
  final Future<void> Function(int minutes, bool export, bool blocked) save;
  final Future<void> Function(int minutes) approve;
  @override
  State<_ChildAccessCard> createState() => _ChildAccessCardState();
}

class _ChildAccessCardState extends State<_ChildAccessCard> {
  late final _minutes =
      TextEditingController(text: widget.profile['minutes'].toString());
  late bool _export = widget.profile['allow_export'] as bool,
      _blocked = widget.profile['blocked'] as bool;
  String? _error;
  int? _duration() {
    final value = int.tryParse(_minutes.text);
    if (value == null || value < 1 || value > 480) {
      setState(() => _error = 'Choose 1 to 480 minutes.');
      return null;
    }
    setState(() => _error = null);
    return value;
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.profile['nickname'] as String,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Semantics(
                container: true,
                label: 'Allowed minutes for ${widget.profile['nickname']}',
                child: TextField(
                    controller: _minutes,
                    enabled: !widget.busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Allowed minutes', errorText: _error))),
            const Text(
                '1–480 minutes per approval. Save access settings before creating a new approval.'),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow saving and printing copies'),
                value: _export,
                onChanged:
                    widget.busy ? null : (v) => setState(() => _export = v!)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Block sign-ins and end active sessions'),
                value: _blocked,
                onChanged:
                    widget.busy ? null : (v) => setState(() => _blocked = v!)),
            OutlinedButton(
                onPressed: widget.busy
                    ? null
                    : () {
                        final minutes = _duration();
                        if (minutes != null)
                          widget.save(minutes, _export, _blocked);
                      },
                child: const Text('Save access settings')),
            FilledButton(
                onPressed: widget.busy || _blocked
                    ? null
                    : () {
                        final minutes = _duration();
                        if (minutes != null) widget.approve(minutes);
                      },
                child: Text(
                    'Approve next sign-in for ${widget.profile['nickname']}')),
          ])));
}
