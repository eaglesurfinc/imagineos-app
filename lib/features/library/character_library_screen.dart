import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../drawing/drawing_drafts.dart';
import '../drawing/drawing_studio.dart';
import '../story/illustration_contract.dart';

import 'character_store.dart';
import 'character_detail_screen.dart';

class CharacterLibraryScreen extends StatefulWidget {
  const CharacterLibraryScreen(
      {super.key,
      required this.store,
      required this.signedIn,
      this.draftScope = 'preview',
      this.drafts,
      this.storyGateway = const DisabledIllustrationGateway(),
      this.chooseFile = pickOriginal});
  final CharacterStore store;
  final bool signedIn;
  final String draftScope;
  final DrawingDraftStore? drafts;
  final IllustrationGateway storyGateway;
  final Future<OriginalFile?> Function() chooseFile;

  @override
  State<CharacterLibraryScreen> createState() => _CharacterLibraryScreenState();
}

class _CharacterLibraryScreenState extends State<CharacterLibraryScreen> {
  final _nickname = TextEditingController();
  final _name = TextEditingController();
  final _scroll = ScrollController();
  CharacterLibrary? _library;
  String? _childId;
  OriginalFile? _file;
  OriginalVersion? _updating;
  OriginalDraft? _draft;
  bool _busy = false;
  String? _message;
  String? _studioKey;
  late final _drafts = widget.drafts ?? DrawingDraftStore.shared;
  late final _session = _drafts.generation;
  String get _formKey => _drafts.key(widget.draftScope, 'form');
  Timer? _formCheckpoint;

  @override
  void initState() {
    super.initState();
    _name.addListener(_queueForm);
    if (widget.signedIn) _initialize();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _name.dispose();
    _scroll.dispose();
    _formCheckpoint?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _reload();
    try {
      final encoded = await _drafts.read(_formKey);
      if (!mounted || encoded == null || _file != null || _name.text.isNotEmpty)
        return;
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final child = json['child'] as String;
      if (!(_library?.creators.any((row) => row.id == child) ?? false)) return;
      OriginalVersion? updating;
      final character = json['character'] as String?;
      if (character != null) {
        final candidates = _library!.versions.where(
            (row) => row.characterId == character && row.state == 'ready');
        if (candidates.isEmpty) return;
        updating = candidates.first;
      }
      final file = await validateOriginal(base64Decode(json['file'] as String));
      if (!mounted || _file != null || _name.text.isNotEmpty) return;
      setState(() {
        _file = file;
        _studioKey = json['studio'] as String?;
        _childId = child;
        _updating = updating;
        _name.text = json['name'] as String;
        if (json['request'] != null)
          _draft = OriginalDraft(
              childId: child,
              name: _name.text,
              file: file,
              characterId: character,
              requestId: json['request'] as String);
        _message =
            'Drawing selection restored. Save it, or reopen the drawing studio.';
      });
    } catch (_) {
      /* Missing device storage never blocks the signed-in library. */
    }
  }

  void _queueForm() {
    if (_studioKey == null || _file == null) return;
    _formCheckpoint?.cancel();
    _formCheckpoint =
        Timer(const Duration(milliseconds: 200), () => unawaited(_cacheForm()));
  }

  Future<void> _cacheForm() async {
    if (_studioKey == null || _file == null || _childId == null) return;
    final value = jsonEncode({
      'child': _childId,
      'character': _updating?.characterId,
      'name': _name.text,
      'file': base64Encode(_file!.bytes),
      'request': _draft?.requestId,
      'studio': _studioKey
    });
    try {
      await _drafts.write(_formKey, value, _session);
    } catch (_) {
      if (mounted)
        setState(() => _message =
            'Device recovery is unavailable. Keep this tab open and save your drawing.');
    }
  }

  Future<void> _newDrawing() async {
    if (_childId == null) return;
    final key = _drafts.key(
        widget.draftScope,
        _updating == null
            ? 'new.$_childId'
            : 'update.${_updating!.characterId}');
    final file =
        await openDrawingStudio(context, draftKey: key, drafts: _drafts);
    if (!mounted || file == null) return;
    setState(() {
      _file = file;
      _studioKey = key;
      _message = 'Drawing ready. Name it and save it to your library.';
    });
    await _cacheForm();
  }

  Future<void> _resumeDrawing() async {
    final key = _studioKey;
    if (key == null || _draft != null) return;
    final file = await openDrawingStudio(context,
        source: _file?.bytes, draftKey: key, drafts: _drafts);
    if (!mounted || file == null) return;
    setState(() {
      _file = file;
      _message = 'Drawing ready. Save it to your library.';
    });
    await _cacheForm();
  }

  Future<void> _studioForSaved(OriginalVersion version) async {
    await _run(() async {
      final bytes = await widget.store.read(version);
      if (!mounted) return;
      final key =
          _drafts.key(widget.draftScope, 'version.${version.versionId}');
      final file = await openDrawingStudio(context,
          source: bytes, draftKey: key, drafts: _drafts);
      if (!mounted || file == null) return;
      setState(() {
        _updating = version;
        _childId = version.childId;
        _name.text = version.name;
        _file = file;
        _studioKey = key;
      });
      await _cacheForm();
    }, 'Original preserved. Use Save new version to keep the studio drawing.');
  }

  Future<void> _reload() async {
    try {
      final library = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _library = library;
        if (!library.creators.any((creator) => creator.id == _childId)) {
          _childId =
              library.creators.isEmpty ? null : library.creators.first.id;
        }
      });
    } catch (_) {
      if (mounted)
        setState(() => _message = 'Could not load your library. Please retry.');
    }
  }

  Future<void> _run(Future<void> Function() action, String success,
      {String? failure}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _message = failure ??
            'Could not complete the save. Your original selection is kept. Retry, or check unfinished uploads.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearForm() {
    _formCheckpoint?.cancel();
    _file = null;
    _draft = null;
    _updating = null;
    _studioKey = null;
    _name.clear();
    unawaited(_drafts.drop(_formKey, _session).catchError((Object _) {}));
  }

  Future<void> _save({bool openStudio = false}) async {
    if (_childId == null ||
        _file == null ||
        _name.text.trim().isEmpty ||
        _name.text.trim().length > 80) {
      setState(() => _message =
          'Choose a creator and an image, and enter a name up to 80 characters.');
      return;
    }
    _draft ??= OriginalDraft(
        childId: _childId!,
        name: _name.text,
        file: _file!,
        characterId: _updating?.characterId);
    final saving = _draft!;
    final studioKey = _studioKey;
    var success = false;
    await _cacheForm();
    await _run(() async {
      await widget.store.save(saving);
      success = true;
      if (studioKey != null) {
        try {
          await _drafts.drop(studioKey, _session);
        } catch (_) {}
      }
      if (mounted) setState(_clearForm);
    }, 'Original saved. You can reopen it below.');
    if (mounted) await _reload();
    if (mounted && success && openStudio) {
      final matches = _library?.versions.where(
          (row) => row.requestId == saving.requestId && row.state == 'ready');
      if (matches != null && matches.isNotEmpty)
        await _studioForSaved(matches.first);
      else
        setState(() => _message =
            'Original saved. Reopen it from the library to use the drawing studio.');
    }
  }

  Future<void> _open(OriginalVersion version) async {
    final history = _library!.versions
        .where((row) =>
            row.characterId == version.characterId && row.state == 'ready')
        .toList();
    final update =
        await Navigator.of(context).push<CharacterUpdate>(MaterialPageRoute(
      builder: (_) => CharacterDetailScreen(
          store: widget.store,
          versions: history,
          draftScope: widget.draftScope,
          storyGateway: widget.storyGateway,
          drafts: _drafts),
    ));
    if (!mounted) return;
    await _reload();
    if (!mounted || update == null) return;
    if (update.removed) {
      setState(() => _message = 'Deletion complete.');
      return;
    }
    setState(() {
      _clearForm();
      _updating = update.version;
      _file = update.file;
      _studioKey = update.studioDraftKey;
      _childId = update.version.childId;
      _name.text = update.version.name;
      _message = update.file == null
          ? 'Choose the intentionally updated drawing. Earlier versions will stay unchanged.'
          : 'Edited drawing ready. Save new version to keep it. Earlier versions stay unchanged.';
    });
    await _cacheForm();
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.signedIn) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Sign in under For parents to save and reopen original characters.')));
    }
    final library = _library;
    final latest = <String, OriginalVersion>{};
    final deletions = <String, OriginalVersion>{};
    for (final version in library?.versions ?? <OriginalVersion>[]) {
      if (version.state == 'deleting') {
        deletions.putIfAbsent(
            version.deletingCharacter ? version.characterId : version.versionId,
            () => version);
      }
      if (version.state == 'ready' && version.childId == _childId) {
        latest.putIfAbsent(version.characterId, () => version);
      }
    }
    return ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Text('A home for your characters',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text(
              'Draw here or bring your artwork from a photo. Saved originals and earlier versions stay unchanged when you edit.'),
          const SizedBox(height: 16),
          if (library == null) ...[
            const Text('Loading your library…'),
            TextButton(
                onPressed: _busy ? null : _reload,
                child: const Text('Retry library')),
          ] else ...[
            if (library.creators.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _childId,
                decoration: const InputDecoration(labelText: 'Creator'),
                items: library.creators
                    .map((creator) => DropdownMenuItem(
                        value: creator.id,
                        child: Text(creator.nickname,
                            maxLines: 1, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: _busy || _draft != null || _updating != null
                    ? null
                    : (value) => setState(() => _childId = value),
              ),
            ExpansionTile(
              title: Text(library.creators.isEmpty
                  ? 'Add a creator nickname'
                  : 'Add another creator'),
              initiallyExpanded: library.creators.isEmpty,
              children: [
                TextField(
                    controller: _nickname,
                    maxLength: 40,
                    enabled: !_busy,
                    decoration:
                        const InputDecoration(labelText: 'Creator nickname')),
                OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_nickname.text.trim().isEmpty) {
                              setState(() => _message =
                                  'Enter a nickname. No child email is needed.');
                              return;
                            }
                            _run(() async {
                              await widget.store.addCreator(_nickname.text);
                              _nickname.clear();
                              await _reload();
                            }, 'Creator added.');
                          },
                    child: const Text('Add creator')),
              ],
            ),
            if (_childId != null) ...[
              const SizedBox(height: 16),
              Text(_updating == null ? 'Save an original' : 'Add a new version',
                  style: Theme.of(context).textTheme.titleLarge),
              TextField(
                  controller: _name,
                  maxLength: 80,
                  enabled: !_busy && _draft == null,
                  decoration:
                      const InputDecoration(labelText: 'Character name')),
              OutlinedButton(
                  onPressed: _busy || _draft != null
                      ? null
                      : () => _run(() async {
                            final file = await widget.chooseFile();
                            if (file != null && mounted) {
                              _formCheckpoint?.cancel();
                              setState(() {
                                _file = file;
                                _studioKey = null;
                              });
                              try {
                                await _drafts.drop(_formKey, _session);
                              } catch (_) {}
                            }
                          }, 'Image selection ready.'),
                  child: const Text('Choose drawing')),
              FilledButton.icon(
                  onPressed: _busy || _draft != null || _file != null
                      ? null
                      : _newDrawing,
                  icon: const Icon(Icons.draw),
                  label: const Text('Draw a character')),
              const Text('PNG, JPEG, or WebP · up to 5 MB and 16 megapixels.'),
              if (_file != null) ...[
                const SizedBox(height: 8),
                Image.memory(_file!.bytes,
                    height: 160,
                    fit: BoxFit.contain,
                    semanticLabel: 'Selected original drawing'),
                if (_studioKey != null && _draft == null)
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _resumeDrawing,
                      icon: const Icon(Icons.edit),
                      label: const Text('Resume drawing studio')),
                if (_studioKey == null && _draft == null)
                  OutlinedButton.icon(
                      onPressed: _busy ? null : () => _save(openStudio: true),
                      icon: const Icon(Icons.content_cut),
                      label: const Text('Save original and open studio')),
              ],
              FilledButton(
                  onPressed: _busy ? null : () => _save(),
                  child: Text(_busy
                      ? 'Please wait…'
                      : _draft != null
                          ? 'Retry save'
                          : _updating == null
                              ? 'Save character'
                              : 'Save new version')),
              if (_file != null || _updating != null)
                TextButton(
                    onPressed: _busy ? null : () => setState(_clearForm),
                    child: Text(_draft == null
                        ? 'Clear selection'
                        : 'Keep unfinished upload and clear form')),
            ],
            const SizedBox(height: 24),
            Text('Saved characters',
                style: Theme.of(context).textTheme.titleLarge),
            if (latest.isEmpty) const Text('No characters yet.'),
            for (final version in latest.values)
              ListTile(
                  title: Text(version.name),
                  subtitle: Text('Version ${version.number}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || _file != null || _updating != null
                      ? null
                      : () => _open(version)),
            if (_file != null || _updating != null)
              const Text(
                  'Save or clear your current selection before opening another character.'),
            const SizedBox(height: 12),
            TextButton(
                onPressed: _busy ? null : _reload,
                child: const Text('Refresh library')),
            for (final removal in deletions.values)
              Card(
                  child: ListTile(
                      title: Text(removal.deletingCharacter
                          ? 'Deleting character: ${removal.name}'
                          : 'Deleting version ${removal.number}: ${removal.name}'),
                      subtitle: const Text(
                          'Deletion is unfinished. Finish removing the selected files and records.'),
                      trailing: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    await widget.store.deleteCharacter(
                                        removal.characterId,
                                        versionId: removal.deletingCharacter
                                            ? null
                                            : removal.versionId);
                                    for (final version in library.versions
                                        .where((row) =>
                                            removal.deletingCharacter
                                                ? row.characterId ==
                                                    removal.characterId
                                                : row.versionId ==
                                                    removal.versionId)) {
                                      try {
                                        await _drafts.drop(
                                            _drafts.key(widget.draftScope,
                                                'version.${version.versionId}'),
                                            _session);
                                      } catch (_) {}
                                    }
                                    if (removal.deletingCharacter) {
                                      try {
                                        await _drafts.drop(
                                            _drafts.key(widget.draftScope,
                                                'update.${removal.characterId}'),
                                            _session);
                                      } catch (_) {}
                                    }
                                    PaintingBinding.instance.imageCache.clear();
                                    PaintingBinding.instance.imageCache
                                        .clearLiveImages();
                                    await _reload();
                                  }, 'Deletion complete.',
                                      failure:
                                          'Deletion did not finish. Retry Finish deletion to continue cleanup.'),
                          child: const Text('Finish deletion')))),
            for (final pending
                in library.versions.where((row) => row.state == 'pending'))
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Unfinished: ${pending.name} · version ${pending.number}'),
                            const Text(
                                'Finish an uploaded file, or discard its unfinished reservation. A file that never uploaded can be chosen again.'),
                            Wrap(spacing: 8, children: [
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() async {
                                            final file =
                                                await widget.chooseFile();
                                            if (file == null || !mounted)
                                              return;
                                            if (file.checksum !=
                                                pending.checksum) {
                                              throw const FormatException(
                                                  'Choose the same original image to resume this upload.');
                                            }
                                            setState(() {
                                              _file = file;
                                              _childId = pending.childId;
                                              _name.text = pending.name;
                                              _updating = pending;
                                              _draft = OriginalDraft(
                                                  childId: pending.childId,
                                                  name: pending.name,
                                                  file: file,
                                                  characterId:
                                                      pending.characterId,
                                                  requestId: pending.requestId);
                                            });
                                          }, 'Original selected. Use Retry save to finish this upload.'),
                                  child: const Text('Choose file again')),
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() async {
                                            await widget.store.finish(pending);
                                            if (_draft?.requestId ==
                                                    pending.requestId &&
                                                mounted) setState(_clearForm);
                                            await _reload();
                                          }, 'Original saved.'),
                                  child: const Text('Finish save')),
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() async {
                                            await widget.store.discard(pending);
                                            if (_draft?.requestId ==
                                                    pending.requestId &&
                                                mounted) setState(_clearForm);
                                            await _reload();
                                          }, 'Unfinished upload discarded.'),
                                  child: const Text('Discard unfinished')),
                            ]),
                          ]))),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(_message!))
          ],
        ]);
  }
}
