import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/device_drafts.dart';
import '../library/character_library_screen.dart';
import '../library/character_store.dart';
import '../parent/parent_access_screen.dart';
import '../parent/parent_account.dart';
import '../parent/parent_controls.dart';
import '../parent/provider_connections.dart';
import '../story/story_draft_store.dart';
import '../story/story_project_store.dart';
import 'child_access.dart';
import 'child_stores.dart';

enum _Entry { welcome, child, parent }

class FamilyAccessShell extends StatefulWidget {
  const FamilyAccessShell(
      {super.key,
      required this.childAccess,
      required this.account,
      required this.controls,
      required this.characters,
      this.providers,
      this.stories,
      this.pages});
  final ChildAccess childAccess;
  final ParentAccount account;
  final ParentControls controls;
  final CharacterStore characters;
  final ProviderConnections? providers;
  final StoryProjectStore? stories;
  final StoryDraftStore? pages;
  @override
  State<FamilyAccessShell> createState() => _FamilyAccessShellState();
}

class _FamilyAccessShellState extends State<FamilyAccessShell>
    with WidgetsBindingObserver {
  _Entry _entry = _Entry.welcome;
  String? _parentEmail;
  bool _handoff = false;
  late final _characters = ChildCharacterStore(widget.childAccess);
  late final _stories = ChildStoryProjectStore(widget.childAccess);
  late final _pages = ChildStoryDraftStore(widget.childAccess);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _parentEmail = widget.account.email;
    if (widget.account.recoveringPassword) _entry = _Entry.parent;
    widget.account.addListener(_parentChanged);
    widget.controls.addListener(_parentLockChanged);
    widget.childAccess.addListener(_childChanged);
  }

  void _closePrivateRoutes() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void _parentChanged() {
    widget.controls.lock();
    if (_parentEmail != widget.account.email) {
      final signedOut = _parentEmail != null && widget.account.email == null;
      _parentEmail = widget.account.email;
      _closePrivateRoutes();
      if (signedOut && !_handoff)
        unawaited(
            DeviceDraftStore.shared.invalidate().catchError((Object _) {}));
    }
    if (mounted)
      setState(() {
        if (widget.account.recoveringPassword) _entry = _Entry.parent;
      });
  }

  void _parentLockChanged() {
    if (_entry == _Entry.parent && !widget.controls.unlocked)
      _closePrivateRoutes();
  }

  void _childChanged() {
    if (!mounted) return;
    if (widget.childAccess.session == null && _entry == _Entry.child)
      _closePrivateRoutes();
    setState(() {
      if (widget.childAccess.active) _entry = _Entry.child;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.childAccess.resume());
    } else {
      widget.childAccess.suspend();
    }
  }

  Future<void> _startChild(String code) async {
    _handoff = true;
    try {
      await widget.account.leaveForChild();
      widget.controls.lock();
      _closePrivateRoutes();
      if (mounted) setState(() => _entry = _Entry.child);
      await widget.childAccess.signIn(code);
    } finally {
      _handoff = false;
    }
  }

  Future<void> _chooseChild() async {
    widget.childAccess.beginEntry();
    _handoff = true;
    try {
      await widget.account.leaveForChild();
    } finally {
      _handoff = false;
    }
    widget.controls.lock();
    if (mounted) setState(() => _entry = _Entry.child);
  }

  void _chooseParent() {
    widget.childAccess.leaveMode();
    _closePrivateRoutes();
    setState(() => _entry = _Entry.parent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.account.removeListener(_parentChanged);
    widget.controls.removeListener(_parentLockChanged);
    widget.childAccess.removeListener(_childChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.childAccess.session;
    return Scaffold(
      appBar: AppBar(
          title: Text(
              session == null ? 'ImagineOS' : '${session.nickname}’s studio'),
          leading: _entry == _Entry.welcome
              ? null
              : IconButton(
                  tooltip: 'Back to entry',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    widget.childAccess.leaveMode();
                    widget.controls.lock();
                    setState(() => _entry = _Entry.welcome);
                  }),
          actions: [
            if (session != null) ...[
              _SessionClock(access: widget.childAccess),
              TextButton(
                  onPressed: () => widget.childAccess.end(
                      'Session finished. Ask your parent to approve your next sign-in.'),
                  child: const Text('Finish session')),
            ]
          ]),
      body: SafeArea(
          child: _entry == _Entry.welcome
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  Text('Your imagination starts here',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  const Text(
                      'Children create. Parents approve access and look after the family account.'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                      onPressed: _chooseChild,
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Child sign-in')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: _chooseParent,
                      icon: const Icon(Icons.family_restroom),
                      label: const Text('Parent sign-in')),
                  const SizedBox(height: 16),
                  const Text(
                      'Every child sign-in needs a new parent approval. No child email or parent password is needed in the child area.'),
                ])
              : _entry == _Entry.parent
                  ? ParentAccessScreen(
                      account: widget.account,
                      controls: widget.controls,
                      providers: widget.providers,
                      startChild: _startChild,
                      familyLibraryBuilder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Family creations')),
                          body: CharacterLibraryScreen(
                              store: widget.characters,
                              signedIn: true,
                              draftScope: _parentEmail ?? 'parent',
                              storyProjects: widget.stories,
                              storyDrafts: widget.pages)))
                  : session == null
                      ? _ChildEntry(
                          access: widget.childAccess,
                          start: _startChild,
                          parent: _chooseParent)
                      : CharacterLibraryScreen(
                          key: ValueKey(session.id),
                          store: _characters,
                          signedIn: true,
                          draftScope: 'child.${session.childId}',
                          storyProjects: _stories,
                          storyDrafts: _pages)),
    );
  }
}

class _ChildEntry extends StatefulWidget {
  const _ChildEntry(
      {required this.access, required this.start, required this.parent});
  final ChildAccess access;
  final Future<void> Function(String code) start;
  final VoidCallback parent;
  @override
  State<_ChildEntry> createState() => _ChildEntryState();
}

class _ChildEntryState extends State<_ChildEntry> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.start(_code.text);
    } on ChildAccessException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(() =>
            _error = 'Could not start your session. Ask your parent for help.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        Text('Child sign-in',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Text(
            'Ask your parent to approve this sign-in. They choose your profile and how long you can create. Paste the new code they give you.'),
        const SizedBox(height: 16),
        TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration:
                const InputDecoration(labelText: 'Parent approval code'),
            onSubmitted: (_) {
              if (!_busy) _signIn();
            }),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: _busy ? null : _signIn,
            child: Text(_busy ? 'Checking approval…' : 'Enter my studio')),
        TextButton(
            onPressed: _busy ? null : widget.parent,
            child: const Text('Ask a parent on this device')),
        if (_error ?? widget.access.message case final String message)
          Semantics(liveRegion: true, child: Text(message)),
        const SizedBox(height: 16),
        const Text(
            'When your time ends, saved work stays in your library. A new sign-in needs a new approval. Working drafts on this device are best effort; save your work regularly.'),
      ]);
}

class _SessionClock extends StatefulWidget {
  const _SessionClock({required this.access});
  final ChildAccess access;
  @override
  State<_SessionClock> createState() => _SessionClockState();
}

class _SessionClockState extends State<_SessionClock> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.access.remaining.inSeconds.clamp(0, 28800);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
            child: Text(
                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} left')));
  }
}
