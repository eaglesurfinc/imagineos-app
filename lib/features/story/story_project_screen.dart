import '../../core/creation_permissions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/device_drafts.dart';
import '../library/character_store.dart';
import 'illustration_contract.dart';
import 'story_export.dart';
import 'story_project.dart';
import 'story_project_composer.dart';
import 'story_project_export.dart';
import 'story_project_preview.dart';
import 'story_project_store.dart';
import 'story_words_field.dart';

class StoryProjectScreen extends StatefulWidget {
  const StoryProjectScreen(
      {super.key,
      required this.story,
      required this.store,
      required this.characters,
      required this.library,
      required this.draftKey,
      required this.drafts,
      this.saveToDevice = saveStoryDraftToDevice});
  final StoryProject story;
  final StoryProjectStore store;
  final CharacterStore characters;
  final CharacterLibrary library;
  final String draftKey;
  final DeviceDraftStore drafts;
  final SaveStoryDraft saveToDevice;
  @override
  State<StoryProjectScreen> createState() => _StoryProjectScreenState();
}

class _StoryProjectScreenState extends State<StoryProjectScreen> {
  static const steps = [
    'Choose a layout',
    'Choose characters',
    'Tell it your way',
    'Put it in order',
    'Read, save and print'
  ];
  late final StoryProjectComposer _composer;
  final _title = TextEditingController();
  final _scroll = ScrollController();
  final _artwork = <String, OriginalFile>{};
  String? _selected, _exportMessage;
  int _step = 0;
  bool _loadingImages = false, _exporting = false, _includeScenes = false;
  bool _imageError = false;

  @override
  void initState() {
    super.initState();
    _composer = StoryProjectComposer(
        story: widget.story,
        store: widget.store,
        drafts: widget.drafts,
        draftKey: widget.draftKey)
      ..addListener(_changed);
    _initialize();
  }

  Future<void> _initialize() async {
    await _composer.load();
    if (!mounted || !_composer.active) return;
    _title.text = _composer.story.title;
    if (_composer.story.panels.isNotEmpty)
      _selected = _composer.story.panels.first.id;
    if (!_composer.corrupt) await _composer.checkpoint();
    if (mounted) setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _composer.removeListener(_changed);
    _composer.dispose();
    _title.dispose();
    _scroll.dispose();
    super.dispose();
  }

  StoryProject get _story => _composer.story;
  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (step == 4) _loadImages();
  }

  Future<void> _addPanel() async {
    final versions = widget.library.versions
        .where((v) =>
            v.childId == _story.childId &&
            v.state == 'ready' &&
            !v.deletingCharacter)
        .toList();
    final selected = await showDialog<OriginalVersion>(
        context: context,
        builder: (context) => SimpleDialog(
                title: const Text('Choose a saved character'),
                children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Reuse a drawing you already made. The version you choose stays with this page or panel.')),
                  if (versions.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Save a character in My characters first. Your story is kept.')),
                  for (final version in versions)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, version),
                        child: Text(
                            '${version.name} — version ${version.number}')),
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Keep working')),
                ]));
    if (!mounted ||
        !_composer.active ||
        selected == null ||
        _story.panels.length >= StoryProject.maxPanels) return;
    final panel = StoryPanel(
        id: const Uuid().v4(),
        reference: StoryReference.fromVersion(selected),
        characterName: selected.name,
        versionNumber: selected.number);
    _composer.update(_story.copy(panels: [..._story.panels, panel]));
    setState(() => _selected = panel.id);
  }

  void _move(int index, int offset) {
    final panels = _story.panels.toList(), target = index + offset;
    if (target < 0 || target >= panels.length) return;
    final panel = panels.removeAt(index);
    panels.insert(target, panel);
    _composer.update(_story.copy(panels: panels));
  }

  Future<void> _remove(StoryPanel panel) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Remove this ${_story.format.unit}?'),
                scrollable: true,
                content: const Text(
                    'Its scene and words will be removed from this working story. Your saved character drawing stays. A saved story changes only when you save again.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep it')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Remove from story'))
                ]));
    if (!mounted || !_composer.active || yes != true) return;
    _composer.update(_story.copy(
        panels: _story.panels.where((p) => p.id != panel.id).toList()));
    if (_selected == panel.id)
      setState(() => _selected = _story.panels.firstOrNull?.id);
  }

  Future<void> _loadImages() async {
    if (_loadingImages) return;
    setState(() {
      _loadingImages = true;
      _imageError = false;
    });
    try {
      var size = _artwork.values
          .fold<int>(0, (total, file) => total + file.bytes.length);
      for (final panel in _story.panels) {
        if (!panel.sourceAvailable) {
          _imageError = true;
          continue;
        }
        if (_artwork.containsKey(panel.reference.assetId)) continue;
        final version = widget.library.versions
            .where((v) =>
                StoryReference.fromVersion(v).sameAs(panel.reference) &&
                v.state == 'ready' &&
                !v.deletingCharacter)
            .firstOrNull;
        if (version == null) {
          _imageError = true;
          continue;
        }
        final bytes = await widget.characters.read(version);
        if (!mounted || !_composer.active) return;
        size += bytes.length;
        if (size > 32 * 1024 * 1024)
          throw const FormatException('Too much artwork for this preview');
        final file = await validateOriginal(bytes);
        if (!mounted || !_composer.active) return;
        if (file.checksum != panel.reference.sha)
          throw const FormatException('Original mismatch');
        _artwork[panel.reference.assetId] = file;
      }
    } catch (_) {
      _imageError = true;
    } finally {
      if (mounted && _composer.active) setState(() => _loadingImages = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _exportMessage = null;
    });
    final snapshot = _story;
    try {
      final permissions = CreationPermissions.of(context);
      await permissions.requireExport();
      await _loadImages();
      if (!mounted || !_composer.active) return;
      await permissions.requireExport();
      final bytes = exportStoryProject(snapshot, _artwork,
          includeSceneNotes: _includeScenes);
      final saved = await widget.saveToDevice(
          bytes, 'imagineos-story-${snapshot.id}.html');
      if (mounted && _composer.active)
        setState(() => _exportMessage = saved
            ? 'Printable story download requested. Open the HTML file on your device to read or print it.'
            : 'Download cancelled. Your story is kept.');
    } catch (error) {
      if (mounted && _composer.active)
        setState(() => _exportMessage = error is FormatException
            ? error.message
            : 'Could not download this copy. Your story is kept. Try again.');
    } finally {
      if (mounted && _composer.active) setState(() => _exporting = false);
    }
  }

  Future<void> _resolve(bool device) async {
    if (device) {
      await _composer.useDeviceCopy();
    } else {
      final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Open the saved copy?'),
                  scrollable: true,
                  content: const Text(
                      'This replaces the working copy on this device. Open the device copy first if you want to keep or print its changes.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep device copy')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Open saved copy'))
                  ]));
      if (!mounted || yes != true) return;
      await _composer.useSavedCopy(widget.story);
    }
    if (mounted && _composer.active) {
      _title.text = _story.title;
      setState(() {
        _selected = _story.panels.firstOrNull?.id;
        _step = 0;
      });
    }
  }

  Widget _format() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Choose how your drawings and words sit together. You can change this later; your story stays yours.'),
        const SizedBox(height: 16),
        RadioGroup<StoryFormat>(
            groupValue: _story.format,
            onChanged: (value) => _composer.update(_story.copy(format: value)),
            child: Column(children: [
              for (final format in StoryFormat.values)
                RadioListTile<StoryFormat>(
                    value: format,
                    title: Text(format.label),
                    subtitle: Text(format.guide))
            ])),
        const SizedBox(height: 16),
        StoryWordsField(
            controller: _title,
            maxLength: 160,
            label: 'Your story title (optional)',
            helper: 'Only you choose the words. You can leave this blank.',
            onChanged: (value) => _composer.update(_story.copy(title: value))),
      ]);
  Widget _panels({bool arrange = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(arrange
            ? 'You choose the reading order. Use the arrows to move a whole ${_story.format.unit}; every word moves with it.'
            : 'Choose a saved drawing for each ${_story.format.unit}. You can use the same character again and again.'),
        if (_story.panels.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Nothing is added until you choose it.')),
        for (var i = 0; i < _story.panels.length; i++)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            '${_story.format.unit == 'page' ? 'Page' : 'Panel'} ${i + 1}: ${_story.panels[i].characterName}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            'Saved drawing version ${_story.panels[i].versionNumber}'),
                        if (_story.panels[i].scene.isNotEmpty)
                          Text(_story.panels[i].scene,
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                        if (!_story.panels[i].sourceAvailable)
                          const Text(
                              'Drawing was deleted. Your scene and words are kept.'),
                        Wrap(spacing: 8, children: [
                          TextButton.icon(
                              onPressed: () {
                                setState(() => _selected = _story.panels[i].id);
                                _go(2);
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Write or edit')),
                          if (arrange) ...[
                            IconButton(
                                tooltip:
                                    'Move ${_story.format.unit} ${i + 1} earlier',
                                onPressed: i == 0 ? null : () => _move(i, -1),
                                icon: const Icon(Icons.arrow_upward)),
                            IconButton(
                                tooltip:
                                    'Move ${_story.format.unit} ${i + 1} later',
                                onPressed: i == _story.panels.length - 1
                                    ? null
                                    : () => _move(i, 1),
                                icon: const Icon(Icons.arrow_downward)),
                          ],
                          TextButton(
                              onPressed: () => _remove(_story.panels[i]),
                              child: Text(
                                  'Remove ${_story.format.unit} ${i + 1}')),
                        ]),
                      ]))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _story.panels.length >= StoryProject.maxPanels
                ? null
                : _addPanel,
            icon: const Icon(Icons.add),
            label: Text('Add ${_story.format.unit}')),
        Text('Up to ${StoryProject.maxPanels} pages or panels in this story.'),
      ]);
  Widget _words() {
    final panel = _story.panels.where((p) => p.id == _selected).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
          'You decide what happens and what is said. These boxes stay blank until you write. Any box can be left empty.'),
      const SizedBox(height: 16),
      if (_story.panels.isEmpty) ...[
        const Text('Choose a character to start a page or panel.'),
        OutlinedButton(
            onPressed: () => _go(1), child: const Text('Choose characters'))
      ] else
        DropdownButtonFormField<String>(
            initialValue: panel?.id,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: 'Choose a ${_story.format.unit} to work on'),
            items: [
              for (var i = 0; i < _story.panels.length; i++)
                DropdownMenuItem(
                    value: _story.panels[i].id,
                    child: Text('${i + 1}: ${_story.panels[i].characterName}',
                        overflow: TextOverflow.ellipsis))
            ],
            onChanged: (value) => setState(() => _selected = value)),
      if (panel != null) ...[
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
                '${panel.characterName} — saved drawing version ${panel.versionNumber}. Reusing a character keeps this drawing as its reference.')),
        _PanelWordsEditor(
            key: ValueKey(panel.id),
            panel: panel,
            onChanged: (next) => _composer.update(_story.copy(
                panels: _story.panels
                    .map((p) => p.id == next.id ? next : p)
                    .toList()))),
      ],
    ]);
  }

  Widget _preview() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Read it in your order. Go back whenever you want to change something yourself.'),
        SwitchListTile(
            title: const Text('Show my scene notes in the draft'),
            subtitle: const Text(
                'Scene notes direct future illustration. Your typed dialogue and narration always stay exact.'),
            value: _includeScenes,
            onChanged: (value) => setState(() => _includeScenes = value)),
        if (_loadingImages) const LinearProgressIndicator(),
        if (_imageError) ...[
          const Text(
              'Some drawings could not be opened. Your words are kept. Try loading the drawings again.'),
          TextButton(
              onPressed: _loadingImages ? null : _loadImages,
              child: const Text('Retry drawings'))
        ],
        StoryProjectPreview(
            story: _story,
            images: _artwork.map((key, value) => MapEntry(key, value.bytes)),
            includeSceneNotes: _includeScenes),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _composer.busy ? null : _composer.save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save story')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: !CreationPermissions.of(context).export ||
                    _exporting ||
                    _loadingImages ||
                    _story.panels.isEmpty
                ? null
                : _export,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Download printable story')),
        if (_exportMessage != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_exportMessage!, semanticsLabel: _exportMessage)),
      ]);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('My story studio')),
      body: !_composer.ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
                  Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('You are the creator.',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall),
                                              const Text(
                                                  'The guide helps you organize. It never writes, adds, removes or changes your story for you.'),
                                            ]))),
                                if (_composer.message != null)
                                  Semantics(
                                      liveRegion: true,
                                      child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(_composer.message!))),
                                if (_composer.recoveryFailed)
                                  const Text(
                                      'Device recovery is unavailable. Keep this tab open and save or print your story.'),
                                if (_composer.corrupt) ...[
                                  OutlinedButton(
                                      onPressed: () => _resolve(true),
                                      child: const Text('Open device copy')),
                                  OutlinedButton(
                                      onPressed: () => _resolve(false),
                                      child: const Text('Open saved copy')),
                                ] else ...[
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    for (var i = 0; i < steps.length; i++)
                                      ChoiceChip(
                                          label: Text('${i + 1}. ${steps[i]}'),
                                          selected: _step == i,
                                          onSelected: (_) => _go(i))
                                  ]),
                                  const SizedBox(height: 24),
                                  Text(
                                      'Step ${_step + 1} of ${steps.length}: ${steps[_step]}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  const SizedBox(height: 16),
                                  switch (_step) {
                                    0 => _format(),
                                    1 => _panels(),
                                    2 => _words(),
                                    3 => _panels(arrange: true),
                                    _ => _preview()
                                  },
                                  const SizedBox(height: 24),
                                  Wrap(spacing: 12, runSpacing: 12, children: [
                                    if (_step > 0)
                                      OutlinedButton(
                                          onPressed: () => _go(_step - 1),
                                          child: const Text('Back a step')),
                                    if (_step < 4)
                                      FilledButton(
                                          onPressed: () => _go(_step + 1),
                                          child: const Text('Next step')),
                                    if (_step != 4)
                                      TextButton(
                                          onPressed: _composer.busy
                                              ? null
                                              : _composer.save,
                                          child: const Text('Save for later')),
                                  ]),
                                  const SizedBox(height: 24),
                                  if (_composer.dirty && _story.revision > 0)
                                    TextButton(
                                        onPressed: _composer.busy
                                            ? null
                                            : () async {
                                                await _composer
                                                    .keepAsNewStory();
                                                if (mounted)
                                                  setState(() => _selected =
                                                      _story.panels.firstOrNull
                                                          ?.id);
                                              },
                                        child: const Text(
                                            'Keep this copy as another story')),
                                  const Text(
                                      'Live AI illustration is off. Your saved drawing is shown as original artwork, not a newly illustrated scene.'),
                                ],
                              ]))),
                ]));
}

class _PanelWordsEditor extends StatefulWidget {
  const _PanelWordsEditor(
      {super.key, required this.panel, required this.onChanged});
  final StoryPanel panel;
  final ValueChanged<StoryPanel> onChanged;
  @override
  State<_PanelWordsEditor> createState() => _PanelWordsEditorState();
}

class _PanelWordsEditorState extends State<_PanelWordsEditor> {
  late final _scene = TextEditingController(text: widget.panel.scene);
  late final _dialogue = TextEditingController(text: widget.panel.dialogue);
  late final _narration = TextEditingController(text: widget.panel.narration);
  @override
  void didUpdateWidget(covariant _PanelWordsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scene.text != widget.panel.scene) _scene.text = widget.panel.scene;
    if (_dialogue.text != widget.panel.dialogue)
      _dialogue.text = widget.panel.dialogue;
    if (_narration.text != widget.panel.narration)
      _narration.text = widget.panel.narration;
  }

  @override
  void dispose() {
    _scene.dispose();
    _dialogue.dispose();
    _narration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        StoryWordsField(
            controller: _scene,
            minLines: 3,
            maxLength: 2000,
            label: 'What happens here?',
            helper:
                'Describe the action or place you want to show. These are your scene notes.',
            onChanged: (value) =>
                widget.onChanged(widget.panel.words(scene: value))),
        const SizedBox(height: 16),
        StoryWordsField(
            controller: _dialogue,
            minLines: 2,
            maxLength: 20000,
            label: 'What is said? (optional)',
            helper:
                'Write your exact dialogue. Nobody fills it in or changes it.',
            onChanged: (value) =>
                widget.onChanged(widget.panel.words(dialogue: value))),
        const SizedBox(height: 16),
        StoryWordsField(
            controller: _narration,
            minLines: 2,
            maxLength: 20000,
            label: 'Other words for the reader (optional)',
            helper: 'Add your own narration, or leave this empty.',
            onChanged: (value) =>
                widget.onChanged(widget.panel.words(narration: value))),
      ]);
}
