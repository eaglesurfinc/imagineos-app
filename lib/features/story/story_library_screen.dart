import '../../core/creation_permissions.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/device_drafts.dart';
import '../library/character_store.dart';
import 'story_project.dart';
import 'story_project_screen.dart';
import 'story_project_store.dart';

class StoryLibraryScreen extends StatefulWidget {
  const StoryLibraryScreen(
      {super.key,
      required this.store,
      required this.characters,
      required this.draftScope,
      this.drafts});
  final StoryProjectStore store;
  final CharacterStore characters;
  final String draftScope;
  final DeviceDraftStore? drafts;
  @override
  State<StoryLibraryScreen> createState() => _StoryLibraryScreenState();
}

class _StoryLibraryScreenState extends State<StoryLibraryScreen> {
  late final _drafts = widget.drafts ?? DeviceDraftStore.shared;
  late final _session = _drafts.generation;
  String get _key => _drafts.key(widget.draftScope, 'story-project.workspace');
  List<StoryProject> _stories = [];
  CharacterLibrary? _library;
  StoryProject? _workspace;
  bool _busy = true, _unreadable = false, _dirty = false;
  bool _hasMore = false, _loadingMore = false;
  int _offset = 0;
  String? _error;
  bool get _active => mounted && _session == _drafts.generation;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _workspace = null;
    _unreadable = false;
    _dirty = false;
    try {
      final raw = await _drafts.read(_key);
      if (!_active) return;
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['schema'] != 1) throw const FormatException();
        _workspace = StoryProject.fromJson(
            Map<String, dynamic>.from(json['story'] as Map));
        _dirty = json['dirty'] == true;
      }
    } catch (_) {
      _unreadable = true;
    }
    try {
      final data =
          await Future.wait([widget.store.load(), widget.characters.load()]);
      if (!_active) return;
      _stories = data[0] as List<StoryProject>;
      _hasMore = _stories.length == 20;
      _offset = 0;
      _library = data[1] as CharacterLibrary;
    } catch (_) {
      if (_active) {
        if (_workspace != null) _library ??= const CharacterLibrary([], []);
        _error =
            'Your stories could not be loaded. Your working copy is kept. Try again.';
      }
    } finally {
      if (_active) setState(() => _busy = false);
    }
  }

  Future<void> _more() async {
    setState(() => _loadingMore = true);
    try {
      final rows = await widget.store.load(offset: _offset + 20);
      if (!_active) return;
      _offset += 20;
      _hasMore = rows.length == 20;
      final ids = _stories.map((s) => s.id).toSet();
      _stories.addAll(rows.where((s) => ids.add(s.id)));
    } catch (_) {
      if (_active) _error = 'More stories could not be loaded. Try again.';
    } finally {
      if (_active) setState(() => _loadingMore = false);
    }
  }

  Future<bool> _leaveWorkspace(String? id) async {
    if (_workspace?.id == id && id != null) return true;
    if (_unreadable ||
        _dirty ||
        (_workspace != null && _workspace!.revision == 0)) {
      final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Leave this working copy?'),
                  scrollable: true,
                  content: const Text(
                      'This device keeps one working story at a time. Save or print that copy first if you want to keep its unsaved changes. Opening another story replaces the device working copy; saved stories stay in your family account.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep working copy')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Replace working copy'))
                  ]));
      if (!_active || yes != true) return false;
    }
    try {
      await _drafts.drop(_key, _session);
      return _active;
    } catch (_) {
      if (_active)
        setState(() => _error =
            'Could not change the device working copy. It is kept. Try again.');
      return false;
    }
  }

  Future<void> _open(StoryProject story) async {
    if (!await _leaveWorkspace(story.id) || !_active) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StoryProjectScreen(
            story: story,
            store: widget.store,
            characters: widget.characters,
            library: _library!,
            draftKey: _key,
            drafts: _drafts)));
    if (_active) await _load();
  }

  Future<void> _new() async {
    final child = await showDialog<CreatorProfile>(
        context: context,
        builder: (context) =>
            SimpleDialog(title: const Text('Whose story is this?'), children: [
              for (final creator in _library!.creators)
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, creator),
                    child: Text(creator.nickname)),
              if (_library!.creators.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Ask your parent to add a creator nickname in My characters first.')),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Keep my stories')),
            ]));
    if (!_active || child == null) return;
    await _open(StoryProject(id: const Uuid().v4(), childId: child.id));
  }

  Future<void> _delete(StoryProject story) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete this saved story?'),
                scrollable: true,
                content: const Text(
                    'This permanently removes the saved story, its scenes, page order and words. Character drawings stay in My characters. Copies already downloaded to a device stay there.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep story')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete saved story'))
                ]));
    if (!_active || yes != true) return;
    setState(() => _busy = true);
    try {
      await widget.store.delete(story);
      if (!_active) return;
      if (_workspace?.id == story.id) await _drafts.drop(_key, _session);
      if (_active) await _load();
    } catch (_) {
      if (_active)
        setState(() {
          _busy = false;
          _error =
              'Could not confirm deletion. Refresh the saved stories before trying again. Character drawings stay unchanged.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('My stories')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text('Your characters. Your story.',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text(
                  'Choose a layout, reuse your drawings and tell it your way. A step-by-step guide helps you organize without writing any part for you.'),
              const SizedBox(height: 16),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              if (_library != null)
                FilledButton.icon(
                    onPressed: _new,
                    icon: const Icon(Icons.add),
                    label: const Text('Start my story')),
              if (_workspace != null && _library != null)
                Card(
                    child: ListTile(
                        title: Text(_workspace!.title.isEmpty
                            ? 'Your working story'
                            : _workspace!.title),
                        subtitle: Text(_dirty || _workspace!.revision == 0
                            ? 'This device has changes to save.'
                            : 'Device working copy'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _open(_stories
                                .where((s) => s.id == _workspace!.id)
                                .firstOrNull ??
                            _workspace!))),
              if (_unreadable)
                const Text(
                    'An unreadable device draft is kept. Starting or opening another story will ask before replacing it.'),
              const SizedBox(height: 20),
              Text('Saved stories',
                  style: Theme.of(context).textTheme.titleLarge),
              if (_stories.isEmpty && _error == null)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                        'Your saved stories will live here. Start one whenever you are ready.')),
              for (final story in _stories)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  story.title.isEmpty
                                      ? 'Story without a title'
                                      : story.title,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              Text(
                                  '${story.format.label} · ${story.panels.length} ${story.format.unit}${story.panels.length == 1 ? '' : 's'} · ${_library?.creators.where((c) => c.id == story.childId).firstOrNull?.nickname ?? 'Creator'}'),
                              Wrap(spacing: 8, children: [
                                TextButton(
                                    onPressed: _library == null
                                        ? null
                                        : () => _open(story),
                                    child: const Text('Open story')),
                                if (CreationPermissions.of(context)
                                    .deleteSavedWork)
                                  TextButton(
                                      onPressed: () => _delete(story),
                                      child: const Text('Delete story'))
                              ]),
                            ]))),
              if (_hasMore)
                TextButton(
                    onPressed: _loadingMore ? null : _more,
                    child: const Text('Load more stories')),
              TextButton(
                  onPressed: _loadingMore ? null : _load,
                  child: const Text('Refresh stories')),
            ]));
}
