import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'character_store.dart';

class CharacterLibraryScreen extends StatefulWidget {
  const CharacterLibraryScreen(
      {super.key,
      required this.store,
      required this.signedIn,
      this.chooseFile = pickOriginal});
  final CharacterStore store;
  final bool signedIn;
  final Future<OriginalFile?> Function() chooseFile;

  @override
  State<CharacterLibraryScreen> createState() => _CharacterLibraryScreenState();
}

class _CharacterLibraryScreenState extends State<CharacterLibraryScreen> {
  final _nickname = TextEditingController();
  final _name = TextEditingController();
  CharacterLibrary? _library;
  String? _childId;
  OriginalFile? _file;
  OriginalVersion? _updating;
  OriginalDraft? _draft;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.signedIn) _reload();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _name.dispose();
    super.dispose();
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

  Future<void> _run(Future<void> Function() action, String success) async {
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
        setState(() => _message =
            'Could not complete the save. Your original selection is kept. Retry, or check unfinished uploads.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearForm() {
    _file = null;
    _draft = null;
    _updating = null;
    _name.clear();
  }

  Future<void> _save() async {
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
    await _run(() async {
      await widget.store.save(_draft!);
      if (mounted) setState(_clearForm);
    }, 'Original saved. You can reopen it below.');
    if (mounted) await _reload();
  }

  Future<void> _open(OriginalVersion version) async {
    final history = _library!.versions
        .where((row) =>
            row.characterId == version.characterId && row.state == 'ready')
        .toList();
    final update =
        await Navigator.of(context).push<OriginalVersion>(MaterialPageRoute(
      builder: (_) => _CharacterDetail(store: widget.store, versions: history),
    ));
    if (!mounted || update == null) return;
    setState(() {
      _clearForm();
      _updating = update;
      _childId = update.childId;
      _name.text = update.name;
      _message =
          'Choose the intentionally updated drawing. Earlier versions will stay unchanged.';
    });
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
    for (final version in library?.versions ?? <OriginalVersion>[]) {
      if (version.state == 'ready' && version.childId == _childId) {
        latest.putIfAbsent(version.characterId, () => version);
      }
    }
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('A home for your characters',
          style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      const Text(
          'Upload an original drawing. Your drawings and every saved version stay yours.'),
      const SizedBox(height: 16),
      if (library == null) ...[
        const Text('Loading your library…'),
        TextButton(
            onPressed: _busy ? null : _reload,
            child: const Text('Retry library')),
      ] else ...[
        if (library.creators.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _childId,
            decoration: const InputDecoration(labelText: 'Creator'),
            items: library.creators
                .map((creator) => DropdownMenuItem(
                    value: creator.id, child: Text(creator.nickname)))
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
              decoration: const InputDecoration(labelText: 'Character name')),
          OutlinedButton(
              onPressed: _busy || _draft != null
                  ? null
                  : () => _run(() async {
                        final file = await widget.chooseFile();
                        if (file != null && mounted)
                          setState(() => _file = file);
                      }, 'Image selection ready.'),
              child: const Text('Choose drawing')),
          const Text('PNG, JPEG, or WebP · up to 5 MB and 16 megapixels.'),
          if (_file != null) ...[
            const SizedBox(height: 8),
            Image.memory(_file!.bytes,
                height: 160,
                fit: BoxFit.contain,
                semanticLabel: 'Selected original drawing'),
          ],
          FilledButton(
              onPressed: _busy ? null : _save,
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
        Text('Saved characters', style: Theme.of(context).textTheme.titleLarge),
        if (latest.isEmpty) const Text('No characters yet.'),
        for (final version in latest.values)
          ListTile(
              title: Text(version.name),
              subtitle: Text('Version ${version.number}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _open(version)),
        const SizedBox(height: 12),
        TextButton(
            onPressed: _busy ? null : _reload,
            child: const Text('Refresh library')),
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
                                        final file = await widget.chooseFile();
                                        if (file == null || !mounted) return;
                                        if (file.checksum != pending.checksum) {
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
                                              characterId: pending.characterId,
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

class _CharacterDetail extends StatefulWidget {
  const _CharacterDetail({required this.store, required this.versions});
  final CharacterStore store;
  final List<OriginalVersion> versions;
  @override
  State<_CharacterDetail> createState() => _CharacterDetailState();
}

class _CharacterDetailState extends State<_CharacterDetail> {
  late OriginalVersion _version;
  late Future<Uint8List> _image;
  @override
  void initState() {
    super.initState();
    _select(widget.versions.first);
  }

  void _select(OriginalVersion version) {
    _version = version;
    _image = widget.store.read(version);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_version.name)),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          DropdownButtonFormField<String>(
              initialValue: _version.versionId,
              decoration: const InputDecoration(labelText: 'Saved version'),
              items: widget.versions
                  .map((version) => DropdownMenuItem(
                      value: version.versionId,
                      child:
                          Text('Version ${version.number}: ${version.name}')))
                  .toList(),
              onChanged: (id) {
                if (id != null)
                  setState(() => _select(widget.versions
                      .firstWhere((version) => version.versionId == id)));
              }),
          const SizedBox(height: 16),
          FutureBuilder<Uint8List>(
              future: _image,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Column(children: [
                    const Text('Could not reopen this original. Please retry.'),
                    TextButton(
                        onPressed: () => setState(() => _select(_version)),
                        child: const Text('Retry image')),
                  ]);
                // Do not show the previous version while another image is loading.
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData) return const Text('Opening original…');
                return Image.memory(snapshot.data!,
                    fit: BoxFit.contain,
                    semanticLabel:
                        'Original drawing for ${_version.name}, version ${_version.number}',
                    errorBuilder: (_, __, ___) =>
                        const Text('This image could not be displayed.'));
              }),
          const SizedBox(height: 16),
          const Text(
              'This saved original stays unchanged. Intentional updates create a new version.'),
          OutlinedButton(
              onPressed: () => Navigator.of(context).pop(widget.versions.first),
              child: const Text('Add new version')),
        ]),
      );
}
