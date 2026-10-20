import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/device_drafts.dart';
import '../library/character_store.dart';
import 'family_backup.dart';
import 'parent_controls.dart';

class ParentPrivacyScreen extends StatefulWidget {
  const ParentPrivacyScreen(
      {super.key, required this.recovery, this.pickBackup, this.saveBackup});
  final FamilyRecovery recovery;
  final Future<FamilyBackup?> Function()? pickBackup;
  final Future<bool> Function(FamilyBackup)? saveBackup;
  @override
  State<ParentPrivacyScreen> createState() => _ParentPrivacyScreenState();
}

class _ParentPrivacyScreenState extends State<ParentPrivacyScreen> {
  ParentControls get controls => widget.recovery.controls;
  Map<String, dynamic>? _status;
  FamilyBackup? _archive;
  List<CreatorProfile> _targets = [];
  String? _source, _target, _message;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    controls.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    controls.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!controls.unlocked && mounted)
      setState(() {
        _archive = null;
        _status = null;
        _targets = [];
        _source = _target = _message = null;
      });
  }

  Future<void> _load() async {
    try {
      final status = await controls.privacyStatus();
      if (mounted && controls.unlocked) setState(() => _status = status);
    } catch (_) {
      if (mounted)
        setState(() => _message =
            'Could not load privacy controls. Unlock parent settings and try again.');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!controls.unlocked) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on ParentControlsException catch (e) {
      _progress(e.message);
    } on FormatException catch (e) {
      _progress(e.message);
    } catch (_) {
      _progress(
          'This operation was not confirmed. Keep your backup file. Completed recovery copies remain saved; reopening the same file and choosing the same creator resumes safely.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _progress(String text) {
    if (mounted && controls.unlocked) setState(() => _message = text);
  }

  Future<bool> _confirm(
          String title, String explanation, String action) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(title),
                  content: SingleChildScrollView(child: Text(explanation)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(action))
                  ])) ??
      false;
  Future<void> _backup() async {
    if (!await _confirm(
        'Download saved family work?',
        'This private file includes creator nicknames, saved drawings and exact story words. It is not encrypted. Keep it somewhere only your family can access. It excludes passwords, provider keys, approvals and unsaved device work.',
        'Download backup')) return;
    await _run(() async {
      final archive = await widget.recovery.backup(_progress);
      if (!mounted || !controls.unlocked) return;
      final saved = await (widget.saveBackup ?? _save)(archive);
      _progress(saved
          ? 'Backup download requested. Check your device, then use Review backup to verify the saved file.'
          : 'Backup save cancelled. Cloud work is unchanged.');
    });
  }

  Future<bool> _save(FamilyBackup archive) async {
    final name =
        'imagineos-family-${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.imagineos.json';
    final file = XFile.fromData(archive.encode(),
        mimeType: 'application/json', name: name);
    if (kIsWeb) {
      await file.saveTo(name);
      return true;
    }
    final location =
        await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [
      XTypeGroup(label: 'ImagineOS backup', extensions: ['json'])
    ]);
    if (location == null) return false;
    await file.saveTo(location.path);
    return true;
  }

  Future<FamilyBackup?> _pick() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
          label: 'ImagineOS backup',
          extensions: ['json'],
          mimeTypes: ['application/json'])
    ]);
    if (file == null) return null;
    if (await file.length() > maxFamilyBackupBytes)
      throw const FormatException('Choose an ImagineOS backup up to 48 MB.');
    return FamilyBackup.decode(await file.readAsBytes());
  }

  Future<void> _review() => _run(() async {
        setState(() {
          _archive = null;
          _targets = [];
          _source = _target = null;
        });
        final archive = await (widget.pickBackup ?? _pick)();
        if (archive == null) return;
        final status = await controls.privacyStatus();
        if (status['family_id'] != archive.familyId)
          throw const FormatException(
              'This backup belongs to a different family. Sign in to its owning account.');
        final targets = (await widget.recovery.characters.load()).creators;
        if (mounted && controls.unlocked)
          setState(() {
            _archive = archive;
            _targets = targets;
            _source = _target = null;
            _message =
                'Backup integrity and image checks passed. Nothing has been imported.';
          });
      });
  Future<void> _restore() async {
    final archive = _archive, source = _source, target = _target;
    if (archive == null || source == null || target == null) return;
    final from = archive.children.singleWhere((c) => c.id == source).nickname;
    final to = _targets.singleWhere((c) => c.id == target).nickname;
    if (!await _confirm(
        'Recover copies for $to?',
        'Recover $from’s saved drawings and stories into $to. Existing work stays unchanged. Drawing copies receive new version references; story words and layout stay exact. Recovery can finish in steps. Keep this file and select the same creator if interrupted.',
        'Recover copies')) return;
    await _run(
        () => widget.recovery.restore(archive, source, target, _progress));
  }

  Future<void> _pause() async {
    final paused = _status?['child_access_paused'] == true;
    if (!await _confirm(
        paused ? 'Resume approval requests?' : 'Pause all child access?',
        paused
            ? 'This allows new parent approvals in the adult test preview. Ended sessions and old codes stay invalid. Individually blocked profiles stay blocked.'
            : 'All child sessions will end and unused codes will stop working. Saved drawings and stories remain available to you. Screenshots and already received files cannot be recalled.',
        paused ? 'Allow new approvals' : 'Pause child access')) return;
    await _run(() async {
      final status = await controls.pauseChildAccess(!paused);
      if (mounted && controls.unlocked) setState(() => _status = status);
      _progress(paused
          ? 'New parent approvals are allowed. Every sign-in still needs a fresh code.'
          : 'Child access is paused. Saved work has been kept.');
    });
  }

  Future<void> _clearDrafts() async {
    if (!await _confirm(
        'Clear working drafts on this browser?',
        'Remove all ImagineOS unfinished drawing and story drafts on this browser, including other profiles. Saved cloud work and downloaded files remain. This cannot be undone.',
        'Clear device drafts')) return;
    await _run(() async {
      await controls.privacyStatus();
      await DeviceDraftStore.shared.invalidate();
      _progress(
          'ImagineOS device drafts cleared. Cloud work and downloads remain.');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Privacy and recovery')),
      body: !controls.unlocked
          ? const Center(
              child: Text(
                  'Parent settings are locked. Return and unlock them again.'))
          : ListView(padding: const EdgeInsets.all(24), children: [
              Text('Your family’s work, under your control',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              const Text(
                  'USA pilot is not available yet. Parental verification and retention periods have not been selected. This development preview is for adult-created fictional work only. Signing in or approving a code does not complete parental consent.'),
              const SizedBox(height: 16),
              const Text(
                  'Cloud: creator nicknames, drawings, versions and saved story words belong to the private family account. AI generation is disabled. Provider keys stay in the server vault and are excluded from backups.'),
              const SizedBox(height: 12),
              const Text(
                  'Device: unfinished work is best-effort recovery storage. Child session expiry keeps working drafts for the next approval; parent sign-out clears app drafts on this browser. Downloads remain until you remove them. A downloaded backup is not encrypted.'),
              const SizedBox(height: 16),
              Text(
                  _status == null
                      ? 'Loading privacy controls…'
                      : _status!['child_access_paused'] == true
                          ? 'Child access is paused'
                          : 'Fresh parent approvals are required for child access',
                  style: Theme.of(context).textTheme.titleMedium),
              FilledButton(
                  onPressed: _busy || _status == null ? null : _pause,
                  child: Text(_status?['child_access_paused'] == true
                      ? 'Allow new parent approvals'
                      : 'Pause all child access')),
              const SizedBox(height: 24),
              Text('Saved-content backup',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'Copy all saved originals, creator nicknames, organized stories and page drafts. Nothing is deleted. Limits: 32 MB of image bytes and a 48 MB file. Larger families are rejected as a whole; content is never silently left out.'),
              OutlinedButton(
                  onPressed: _busy ? null : _backup,
                  child: const Text('Download family backup')),
              OutlinedButton(
                  onPressed: _busy ? null : _review,
                  child: const Text('Review backup')),
              if (_archive case final archive?) ...[
                Text('Verified backup from ${archive.createdAt}'),
                Text(
                    '${archive.children.length} creators • ${archive.originals.length} saved drawings • ${archive.stories.length} stories • ${archive.pages.length} page drafts'),
                const Text(
                    'Recover one creator at a time into an existing profile in this family. Profiles, passwords, approvals and provider connections are not restored. Stories whose drawings were deleted before backup remain in the file but cannot be automatically imported.'),
                DropdownButtonFormField<String>(
                    key: ValueKey('source-${archive.digest}'),
                    initialValue: _source,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Creator in backup'),
                    items: archive.children
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.nickname)))
                        .toList(),
                    onChanged:
                        _busy ? null : (v) => setState(() => _source = v)),
                DropdownButtonFormField<String>(
                    key: ValueKey('target-${archive.digest}'),
                    initialValue: _target,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Recover into this creator'),
                    items: _targets
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.nickname)))
                        .toList(),
                    onChanged:
                        _busy ? null : (v) => setState(() => _target = v)),
                FilledButton(
                    onPressed: _busy || _source == null || _target == null
                        ? null
                        : _restore,
                    child: const Text('Recover saved copies')),
              ],
              const SizedBox(height: 24),
              OutlinedButton(
                  onPressed: _busy ? null : _clearDrafts,
                  child: const Text('Clear device working drafts')),
              const Text(
                  'To permanently delete cloud work, return to parent settings and choose Delete my account. This removes the whole family. Downloaded copies and infrastructure/provider retention have separate limits; final retention and backup-expiry policies are still pending.'),
              TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Refresh privacy controls')),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(_message!)),
            ]));
}
