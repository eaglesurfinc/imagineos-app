import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'character_store.dart';
import 'character_editor.dart';

class CharacterUpdate {
  const CharacterUpdate(this.version, [this.file]);
  final OriginalVersion version;
  final OriginalFile? file;
}

class CharacterDetailScreen extends StatefulWidget {
  const CharacterDetailScreen(
      {super.key, required this.store, required this.versions});
  final CharacterStore store;
  final List<OriginalVersion> versions;
  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  late OriginalVersion _version;
  late Future<Uint8List> _image;
  bool _editing = false;
  String? _error;

  Future<void> _edit() async {
    if (_editing) return;
    setState(() {
      _editing = true;
      _error = null;
    });
    final selected = _version;
    try {
      final bytes = await _image;
      if (!mounted) return;
      final file = await Navigator.of(context).push<OriginalFile>(
          MaterialPageRoute(builder: (_) => CharacterEditor(source: bytes)));
      if (mounted && file != null)
        Navigator.of(context).pop(CharacterUpdate(selected, file));
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Could not open the editor. Retry the image first.');
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
              initialValue: _version.versionId,
              decoration: const InputDecoration(labelText: 'Saved version'),
              items: widget.versions
                  .map((version) => DropdownMenuItem(
                      value: version.versionId,
                      child:
                          Text('Version ${version.number}: ${version.name}')))
                  .toList(),
              onChanged: _editing
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
              onPressed: _editing
                  ? null
                  : () => Navigator.of(context)
                      .pop(CharacterUpdate(widget.versions.first)),
              child: const Text('Add new version')),
          OutlinedButton(
              onPressed: _editing ? null : _edit,
              child: const Text('Crop and edit')),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        ]),
      );
}
