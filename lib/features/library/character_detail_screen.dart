import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'character_store.dart';
import 'character_editor.dart';
import '../drawing/drawing_drafts.dart';
import '../drawing/drawing_studio.dart';
import '../story/illustration_contract.dart';
import '../story/story_draft_screen.dart';
import '../story/story_draft_store.dart';

class CharacterUpdate {
  const CharacterUpdate(this.version,
      [this.file, this.removed = false, this.studioDraftKey]);
  final OriginalVersion version;
  final OriginalFile? file;
  final bool removed;
  final String? studioDraftKey;
}

class CharacterDetailScreen extends StatefulWidget {
  const CharacterDetailScreen(
      {super.key,
      required this.store,
      required this.versions,
      this.draftScope = 'preview',
      this.storyGateway = const DisabledIllustrationGateway(),
      this.storyDrafts,
      this.drafts});
  final CharacterStore store;
  final List<OriginalVersion> versions;
  final String draftScope;
  final DrawingDraftStore? drafts;
  final IllustrationGateway storyGateway;
  final StoryDraftStore? storyDrafts;
  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  late OriginalVersion _version;
  late Future<Uint8List> _image;
  bool _editing = false;
  bool? _deleteWhole;
  String? _error;

  Future<void> _remove(bool whole) async {
    if (_deleteWhole == null) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                scrollable: true,
                title: Text(whole
                    ? 'Delete character?'
                    : 'Delete version ${_version.number}?'),
                content: Text(whole
                    ? 'Permanently delete "${_version.name}" and all its versions, original drawings, edits, unfinished uploads, saved page drafts, and page drafts on this device? Organized story words stay, but these drawings become unavailable there. This cannot be undone.'
                    : 'Permanently delete version ${_version.number} of "${_version.name}", its drawing, its saved page drafts, and its page draft on this device? Other versions will stay. Organized story words stay, but this drawing becomes unavailable there. This cannot be undone.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Delete permanently')),
                ],
              ));
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      _editing = true;
      _deleteWhole = whole;
      _error = null;
    });
    try {
      await widget.store.deleteCharacter(_version.characterId,
          versionId: whole ? null : _version.versionId);
      final drafts = widget.drafts ?? DrawingDraftStore.shared;
      final session = drafts.generation;
      for (final version in widget.versions
          .where((row) => whole || row.versionId == _version.versionId)) {
        for (final kind in ['version', 'story']) {
          try {
            await drafts.drop(
                drafts.key(widget.draftScope, '$kind.${version.versionId}'),
                session);
          } catch (_) {}
        }
      }
      if (whole) {
        try {
          await drafts.drop(
              drafts.key(widget.draftScope, 'update.${_version.characterId}'),
              session);
        } catch (_) {}
      }
      if (!mounted) return;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      Navigator.of(context).pop(CharacterUpdate(_version, null, true));
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Deletion did not finish. Retry, or return to the library to check unfinished deletions. If this is the last saved version, use Delete character instead.');
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _edit({bool studio = false}) async {
    if (_editing) return;
    setState(() {
      _editing = true;
      _error = null;
    });
    final selected = _version;
    try {
      final bytes = await _image;
      if (!mounted) return;
      final key = (widget.drafts ?? DrawingDraftStore.shared)
          .key(widget.draftScope, 'version.${selected.versionId}');
      final file = studio
          ? await openDrawingStudio(context,
              source: bytes, draftKey: key, drafts: widget.drafts)
          : await Navigator.of(context).push<OriginalFile>(MaterialPageRoute(
              builder: (_) => CharacterEditor(source: bytes)));
      if (mounted && file != null)
        Navigator.of(context)
            .pop(CharacterUpdate(selected, file, false, studio ? key : null));
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Could not open the editor. Retry the image first.');
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _story() async {
    if (_editing) return;
    setState(() {
      _editing = true;
      _error = null;
    });
    final selected = _version;
    try {
      final bytes = await _image;
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => StoryDraftScreen(
              version: selected,
              image: bytes,
              draftScope: widget.draftScope,
              drafts: widget.drafts,
              store: widget.storyDrafts,
              gateway: widget.storyGateway)));
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Could not open the page draft. Retry the original image first.');
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

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
              isExpanded: true,
              initialValue: _version.versionId,
              decoration: const InputDecoration(labelText: 'Saved version'),
              items: widget.versions
                  .map((version) => DropdownMenuItem(
                      value: version.versionId,
                      child: Text('Version ${version.number}: ${version.name}',
                          maxLines: 1, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _editing || _deleteWhole != null
                  ? null
                  : (id) {
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
              onPressed: _editing || _deleteWhole != null
                  ? null
                  : () => Navigator.of(context)
                      .pop(CharacterUpdate(widget.versions.first)),
              child: const Text('Add new version')),
          OutlinedButton(
              onPressed:
                  _editing || _deleteWhole != null ? null : () => _edit(),
              child: const Text('Crop and edit')),
          FilledButton.icon(
              onPressed: _editing || _deleteWhole != null
                  ? null
                  : () => _edit(studio: true),
              icon: const Icon(Icons.draw),
              label: const Text('Open drawing studio')),
          FilledButton.tonalIcon(
              onPressed: _editing || _deleteWhole != null ? null : _story,
              icon: const Icon(Icons.auto_stories_outlined),
              label: const Text('Plan a story page')),
          if (_deleteWhole == null) ...[
            if (widget.versions.length > 1)
              OutlinedButton.icon(
                  onPressed: _editing ? null : () => _remove(false),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete selected version'))
            else
              const Text(
                  'This is the only saved version. Use Delete character to remove it.'),
            TextButton.icon(
                onPressed: _editing ? null : () => _remove(true),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete character')),
          ] else
            FilledButton(
                onPressed: _editing ? null : () => _remove(_deleteWhole!),
                child: Text(_editing ? 'Deleting…' : 'Retry deletion')),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        ]),
      );
}
