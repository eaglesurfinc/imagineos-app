import '../../core/creation_permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/device_drafts.dart';
import '../library/character_store.dart';
import 'illustration_contract.dart';
import 'story_composer.dart';
import 'story_preview.dart';
import 'story_draft_store.dart';
import 'story_export.dart';

class StoryDraftScreen extends StatefulWidget {
  const StoryDraftScreen(
      {super.key,
      required this.version,
      required this.image,
      required this.draftScope,
      this.drafts,
      this.store,
      this.saveToDevice = saveStoryDraftToDevice,
      this.gateway = const DisabledIllustrationGateway()});
  final OriginalVersion version;
  final Uint8List image;
  final String draftScope;
  final DeviceDraftStore? drafts;
  final IllustrationGateway gateway;
  final StoryDraftStore? store;
  final SaveStoryDraft saveToDevice;
  @override
  State<StoryDraftScreen> createState() => _StoryDraftScreenState();
}

class _StoryDraftScreenState extends State<StoryDraftScreen> {
  final _scene = TextEditingController(),
      _dialogue = TextEditingController(),
      _narration = TextEditingController();
  late final StoryComposer _composer;
  bool _saving = false;
  String? _saveMessage;

  Future<void> _saveCloud() async {
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    try {
      final revision = await widget.store!.save(_composer.snapshot);
      if (!mounted || !_composer.active) return;
      _composer.cloudRevision = revision;
      await _composer.checkpoint();
      if (mounted)
        setState(
            () => _saveMessage = 'Page draft saved to your family account.');
    } catch (_) {
      if (mounted)
        setState(() => _saveMessage =
            'Could not confirm this save. Your words are kept. Retry the same save, or load the saved draft if another device changed it.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadCloud() async {
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    try {
      final pages = await widget.store!.load(_composer.reference);
      if (!mounted || !_composer.active) return;
      if (pages.isEmpty) {
        setState(
            () => _saveMessage = 'No saved page drafts for this version yet.');
        return;
      }
      final selected = await showDialog<SavedStoryDraft>(
          context: context,
          builder: (context) => SimpleDialog(
                  title: const Text('Load a saved page draft?'),
                  children: [
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Loading replaces the scene and words currently in this device draft. Saved originals stay unchanged.')),
                    for (final page in pages)
                      SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, page),
                          child: Text(
                              'Revision ${page.revision}: ${page.scene.isEmpty ? 'Untitled scene' : page.scene}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis)),
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Keep current draft'))
                  ]));
      if (selected != null && mounted && _composer.active) {
        await _composer.restoreSaved(selected);
        if (!mounted || !_composer.active) return;
        _scene.text = _composer.scene;
        _dialogue.text = _composer.dialogue;
        _narration.text = _composer.narration;
        if (mounted)
          setState(() => _saveMessage =
              'Saved page draft loaded with its original version.');
      }
    } catch (_) {
      if (mounted)
        setState(() => _saveMessage =
            'Could not load saved page drafts. Your current words are kept.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    try {
      final permissions = CreationPermissions.of(context);
      await permissions.requireExport();
      final original = await validateOriginal(widget.image);
      if (!mounted || !_composer.active) return;
      await permissions.requireExport();
      final bytes = exportStoryDraft(
          _composer.snapshot, original.bytes, original.mimeType);
      final saved = await widget.saveToDevice(
          bytes, 'imagineos-page-${_composer.pageId}.html');
      if (mounted)
        setState(() => _saveMessage = saved
            ? 'Printable page draft download requested. Your browser chooses where to save it.'
            : 'Save cancelled. Your page draft is kept.');
    } catch (_) {
      if (mounted)
        setState(() => _saveMessage =
            'Could not export this page draft. Your words and artwork are kept.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final drafts = widget.drafts ?? DeviceDraftStore.shared;
    _composer = StoryComposer(
        reference: StoryReference.fromVersion(widget.version),
        drafts: drafts,
        draftKey:
            drafts.key(widget.draftScope, 'story.${widget.version.versionId}'),
        gateway: widget.gateway)
      ..addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    await _composer.load();
    if (!mounted) return;
    _scene.text = _composer.scene;
    _dialogue.text = _composer.dialogue;
    _narration.text = _composer.narration;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Discard this page draft?'),
              content: const Text(
                  'Remove the scene and words for this version from this device? The saved character drawing stays.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep draft')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Discard draft'))
              ],
            ));
    if (confirmed == true && await _composer.discard() && mounted) {
      _scene.clear();
      _dialogue.clear();
      _narration.clear();
    }
  }

  Future<void> _leave() async {
    if (_composer.corruptDraft || await _composer.checkpoint()) {
      if (mounted) Navigator.pop(context);
    }
    // A failed checkpoint keeps the screen and exact field values available.
  }

  @override
  void dispose() {
    _composer.removeListener(_changed);
    _composer.dispose();
    _scene.dispose();
    _dialogue.dispose();
    _narration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Plan a story page'),
            leading: BackButton(onPressed: _saving ? null : _leave)),
        body: !_composer.ready
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(
                      '${widget.version.name} - version ${widget.version.number}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                      'Your page starts here. You choose the scene and every word. Illustration is currently turned off.'),
                  const SizedBox(height: 8),
                  Text(widget.store == null
                      ? 'Device drafts depend on local storage. Sign-out clears them. Export a copy to keep your exact words.'
                      : 'Save a page draft to your family account to reopen it on another device. Unsaved device edits are cleared at sign-out. Illustration remains disabled.'),
                  if (_composer.recoveryFailed) ...[
                    const SizedBox(height: 12),
                    Semantics(
                        liveRegion: true,
                        child: Text(_composer.corruptDraft
                            ? 'The existing device draft could not be read. It has not been overwritten. Return to the character or explicitly discard it to start again.'
                            : 'Device recovery is unavailable. Keep this page open and copy your words before closing or signing out.')),
                    if (!_composer.corruptDraft)
                      OutlinedButton(
                          onPressed: _composer.checkpoint,
                          child: const Text('Retry keeping draft')),
                  ],
                  const SizedBox(height: 20),
                  _field('Scene direction', _scene,
                      (value) => _composer.update(scene: value),
                      helper:
                          'Describe the action and setting. Keep it within 2,000 characters.',
                      maxLength: 2000),
                  const SizedBox(height: 16),
                  _field('Exact dialogue', _dialogue,
                      (value) => _composer.update(dialogue: value),
                      helper:
                          'Your words stay exactly as typed. They are never sent to the illustration service.'),
                  const SizedBox(height: 16),
                  _field('Exact narration (optional)', _narration,
                      (value) => _composer.update(narration: value)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    if (widget.store != null) ...[
                      FilledButton(
                          onPressed: _saving ||
                                  _composer.busy ||
                                  _composer.corruptDraft
                              ? null
                              : _saveCloud,
                          child: const Text('Save page draft')),
                      OutlinedButton(
                          onPressed: _saving ||
                                  _composer.busy ||
                                  _composer.corruptDraft
                              ? null
                              : _loadCloud,
                          child: const Text('Load saved page drafts')),
                    ],
                    OutlinedButton(
                        onPressed: !CreationPermissions.of(context).export ||
                                _saving ||
                                _composer.busy ||
                                _composer.corruptDraft
                            ? null
                            : _export,
                        child: const Text('Export printable draft')),
                  ]),
                  if (_saving) const LinearProgressIndicator(),
                  if (_saveMessage != null)
                    Semantics(liveRegion: true, child: Text(_saveMessage!)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: !_saving && _composer.canCheck
                          ? _composer.check
                          : null,
                      icon: const Icon(Icons.shield_outlined),
                      label: Text(_composer.busy
                          ? 'Checking availability...'
                          : _composer.attempts > 0 &&
                                  _composer.result?.retryable == true
                              ? 'Retry availability check'
                              : 'Check illustration availability')),
                  if (_composer.result != null) ...[
                    const SizedBox(height: 8),
                    Semantics(
                        liveRegion: true,
                        child: Text(_composer.result!.message)),
                    if (_composer.result!.retryable &&
                        _composer.attempts >= StoryComposer.maxAttempts)
                      const Text(
                          'The two-attempt limit is reached for this scene. Your draft is kept; no automatic retry will run.'),
                    if (_composer.request != null)
                      SelectableText(
                          'Check reference: ${_composer.request!.traceId}'),
                  ],
                  const SizedBox(height: 24),
                  Text('Page draft preview',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Text(
                      'Original artwork with your exact text. The page grows to fit your words.'),
                  const SizedBox(height: 12),
                  StoryPreview(
                      image: widget.image,
                      dialogue: _composer.dialogue,
                      narration: _composer.narration),
                  const SizedBox(height: 16),
                  TextButton.icon(
                      onPressed: _saving || _composer.busy ? null : _discard,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard device page draft')),
                ]),
              )),
      ));

  Widget _field(String label, TextEditingController controller,
          ValueChanged<String> onChanged, {String? helper, int? maxLength}) =>
      TextField(
          controller: controller,
          enabled: !_saving && !_composer.busy && !_composer.corruptDraft,
          minLines: 2,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          maxLength: maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          decoration: InputDecoration(
              labelText: label, helperText: helper, helperMaxLines: 4),
          onChanged: onChanged);
}
