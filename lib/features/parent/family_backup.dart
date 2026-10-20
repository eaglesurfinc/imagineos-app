import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../library/character_store.dart';
import '../story/illustration_contract.dart';
import '../story/story_draft_store.dart';
import '../story/story_project.dart';
import '../story/story_project_store.dart';
import 'parent_controls.dart';

const maxFamilyBackupBytes = 48 * 1024 * 1024;
const _maxImageBytes = 32 * 1024 * 1024;
final _id = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$');
Object? _ordered(Object? value) => value is Map
    ? {
        for (final key in value.keys.cast<String>().toList()..sort())
          key: _ordered(value[key])
      }
    : value is List
        ? value.map(_ordered).toList()
        : value;
String canonicalBackupJson(Object? value) => jsonEncode(_ordered(value));
Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);
List<Map<String, dynamic>> _rows(dynamic v) => (v as List).map(_map).toList();
void _check(bool condition) {
  if (!condition)
    throw const FormatException(
        'This backup is incomplete or invalid. No recovery was started.');
}

bool _uuid(dynamic value) => value is String && _id.hasMatch(value);
void _keys(Map<String, dynamic> row, String fields) {
  final expected = fields.split(' ');
  _check(row.length == expected.length && expected.every(row.containsKey));
}

/// Portable saved-content copy. It contains no Auth/provider/session secrets.
/// The digest detects corruption; an imported file is still untrusted input.
class FamilyBackup {
  FamilyBackup._(this.snapshot, this.images, this.createdAt, this.digest);
  final Map<String, dynamic> snapshot;
  final Map<String, OriginalFile> images;
  final String createdAt, digest;
  String get familyId => snapshot['family_id'] as String;
  List<CreatorProfile> get children => _rows(snapshot['children'])
      .map((c) => CreatorProfile(c['id'], c['nickname']))
      .toList();
  List<OriginalVersion> get originals =>
      _rows(snapshot['originals']).map(OriginalVersion.fromJson).toList();
  List<StoryProject> get stories =>
      _rows(snapshot['stories']).map(StoryProject.fromJson).toList();
  List<Map<String, dynamic>> get pages => _rows(snapshot['pages']);
  Map<String, dynamic> get _payload => {
        'format': 'imagineos-family-backup',
        'version': 1,
        'created_at': createdAt,
        'snapshot': snapshot,
        'files': {
          for (final e in images.entries) e.key: base64Encode(e.value.bytes)
        }
      };
  Uint8List encode() {
    final bytes = Uint8List.fromList(
        utf8.encode(canonicalBackupJson({..._payload, 'sha256': digest})));
    _check(bytes.length <= maxFamilyBackupBytes);
    return bytes;
  }

  static Future<FamilyBackup> create(
      Map<String, dynamic> snapshot, Map<String, OriginalFile> images) async {
    final time = DateTime.now().toUtc().toIso8601String();
    final draft = FamilyBackup._(snapshot, images, time, '');
    final digest = sha256
        .convert(utf8.encode(canonicalBackupJson(draft._payload)))
        .toString();
    return decode(FamilyBackup._(snapshot, images, time, digest).encode());
  }

  static Future<FamilyBackup> decode(Uint8List bytes) async {
    try {
      _check(bytes.isNotEmpty && bytes.length <= maxFamilyBackupBytes);
      final document = _map(jsonDecode(utf8.decode(bytes)));
      _keys(document, 'format version created_at snapshot files sha256');
      _check(document['format'] == 'imagineos-family-backup' &&
          document['version'] == 1);
      _check(document['created_at'] is String &&
          DateTime.tryParse(document['created_at']) != null);
      final digest = document.remove('sha256');
      _check(digest is String &&
          digest ==
              sha256
                  .convert(utf8.encode(canonicalBackupJson(document)))
                  .toString());
      final snapshot = _map(document['snapshot']);
      _keys(snapshot, 'family_id children originals stories pages');
      _check(_uuid(snapshot['family_id']));
      final children = _rows(snapshot['children']),
          originals = _rows(snapshot['originals']),
          stories = _rows(snapshot['stories']),
          pages = _rows(snapshot['pages']);
      _check(children.length <= 100 &&
          originals.length <= 250 &&
          stories.length <= 200 &&
          pages.length <= 500);
      final childIds = <String>{},
          assetIds = <String>{},
          versionIds = <String>{},
          panelIds = <String>{};
      final characters = <String, String>{};
      for (final c in children) {
        _keys(c, 'id nickname');
        _check(_uuid(c['id']) &&
            c['nickname'] is String &&
            (c['nickname'] as String).trim().isNotEmpty &&
            (c['nickname'] as String).length <= 40 &&
            childIds.add(c['id']));
      }
      final files = _map(document['files']), images = <String, OriginalFile>{};
      var total = 0;
      final byAsset = <String, OriginalVersion>{};
      final numbers = <String>{};
      for (final row in originals) {
        _keys(row,
            'request_id character_id child_profile_id version_id version_number name object_path sha256 state deleting_character mime_type byte_size');
        final v = OriginalVersion.fromJson(row);
        _check(
            [v.requestId, v.characterId, v.childId, v.versionId].every(_uuid) &&
                childIds.contains(v.childId) &&
                assetIds.add(v.requestId) &&
                versionIds.add(v.versionId));
        _check(v.state == 'ready' &&
            !v.deletingCharacter &&
            v.number >= 1 &&
            numbers.add('${v.characterId}:${v.number}') &&
            v.name.trim().isNotEmpty &&
            v.name.length <= 80);
        _check(v.objectPath == '${snapshot['family_id']}/${v.requestId}');
        _check(!characters.containsKey(v.characterId) ||
            characters[v.characterId] == v.childId);
        characters[v.characterId] = v.childId;
        _check(files[v.requestId] is String &&
            (files[v.requestId] as String).length <= 6990508);
        final raw = base64Decode(files[v.requestId]);
        total += raw.length;
        _check(total <= _maxImageBytes);
        final file = await validateOriginal(raw);
        _check(file.checksum == v.checksum &&
            row['mime_type'] == file.mimeType &&
            row['byte_size'] == raw.length);
        images[v.requestId] = file;
        byAsset[v.requestId] = v;
      }
      _check(files.length == images.length);
      final storyIds = <String>{}, pageIds = <String>{};
      for (final row in stories) {
        _keys(row, 'id child_id title format revision panels');
        final s = StoryProject.fromJson(row);
        _check(_uuid(s.id) &&
            storyIds.add(s.id) &&
            childIds.contains(s.childId) &&
            s.withinSaveLimits);
        for (final p in s.panels) {
          _check(_uuid(p.id) &&
              panelIds.add(p.id) &&
              [
                p.reference.characterId,
                p.reference.versionId,
                p.reference.assetId
              ].every(_uuid));
          _check(RegExp(r'^[a-f0-9]{64}$').hasMatch(p.reference.sha));
          if (p.sourceAvailable) {
            final v = byAsset[p.reference.assetId];
            _check(v != null &&
                v.childId == s.childId &&
                StoryReference.fromVersion(v).sameAs(p.reference) &&
                v.name == p.characterName &&
                v.number == p.versionNumber);
          }
        }
      }
      for (final p in pages) {
        _keys(p,
            'page_id source_id character_id version_id sha256 scene dialogue narration revision');
        final v = byAsset[p['source_id']];
        _check(_uuid(p['page_id']) &&
            pageIds.add(p['page_id']) &&
            v != null &&
            v.characterId == p['character_id'] &&
            v.versionId == p['version_id'] &&
            v.checksum == p['sha256']);
        _check(p['revision'] is int &&
            p['revision'] >= 1 &&
            p['scene'] is String &&
            p['dialogue'] is String &&
            p['narration'] is String);
        _check((p['scene'] as String).length <= 2000 &&
            (p['dialogue'] as String).length <= 20000 &&
            (p['narration'] as String).length <= 20000);
      }
      return FamilyBackup._(
          snapshot, images, document['created_at'], digest as String);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'This backup is incomplete or invalid. No recovery was started.');
    }
  }
}

class FamilyRecovery {
  FamilyRecovery(
      {required this.controls,
      required this.characters,
      required this.stories,
      required this.pages});
  final ParentControls controls;
  final CharacterStore characters;
  final StoryProjectStore stories;
  final StoryDraftStore pages;
  Future<void> _guard(String family) async {
    final status = await controls.privacyStatus();
    if (status['family_id'] != family)
      throw const ParentControlsException(
          'Sign in to the family that owns this backup.');
  }

  Future<FamilyBackup> backup(void Function(String) progress) async {
    final snapshot = await controls.recoverySnapshot();
    final images = <String, OriginalFile>{};
    for (final row in _rows(snapshot['originals'])) {
      final v = OriginalVersion.fromJson(row);
      progress(
          'Copying saved drawing ${images.length + 1} of ${(snapshot['originals'] as List).length}');
      await _guard(snapshot['family_id']);
      final bytes = await characters.read(v);
      images[v.requestId] = OriginalFile(bytes, row['mime_type']);
    }
    final latest = await controls.recoverySnapshot();
    if (canonicalBackupJson(latest) != canonicalBackupJson(snapshot))
      throw const ParentControlsException(
          'Saved family work changed during backup. Try again when no one is saving. No incomplete backup was downloaded.');
    final archive = await FamilyBackup.create(snapshot, images);
    await _guard(archive.familyId);
    return archive;
  }

  /// Replays the same file/creator mapping using stable IDs; never overwrites a
  /// changed story, restores credentials, or resurrects a deleted retry key.
  Future<void> restore(FamilyBackup archive, String sourceChild,
      String targetChild, void Function(String) progress) async {
    await _guard(archive.familyId);
    final library = await characters.load();
    _check(archive.children.any((c) => c.id == sourceChild) &&
        library.creators.any((c) => c.id == targetChild));
    final selectedStories =
        archive.stories.where((s) => s.childId == sourceChild).toList();
    if (selectedStories.any((s) => s.panels.any((p) => !p.sourceAvailable)))
      throw const FormatException(
          'This creator has a story whose drawing was deleted before backup. Its exact words remain in the backup, but automatic story recovery is unavailable. Nothing was imported.');
    String key(String kind, String old) => const Uuid().v5(
        '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
        '${archive.digest}:$targetChild:$kind:$old');
    final versions =
        archive.originals.where((v) => v.childId == sourceChild).toList()
          ..sort((a, b) {
            final c = a.characterId.compareTo(b.characterId);
            return c == 0 ? a.number.compareTo(b.number) : c;
          });
    final recovered = <String, OriginalVersion>{},
        characterIds = <String, String>{};
    for (final v in versions) {
      progress(
          'Recovering drawing ${recovered.length + 1} of ${versions.length}');
      await _guard(archive.familyId);
      final request = key('original', v.requestId);
      await characters.save(OriginalDraft(
          childId: targetChild,
          name: v.name,
          file: archive.images[v.requestId]!,
          requestId: request,
          characterId: characterIds[v.characterId]));
      await _guard(archive.familyId);
      final saved = (await characters.load())
          .versions
          .singleWhere((v) => v.requestId == request && v.state == 'ready');
      recovered[v.requestId] = saved;
      characterIds[v.characterId] = saved.characterId;
    }
    final existing = <String, StoryProject>{};
    var offset = 0;
    while (true) {
      await _guard(archive.familyId);
      final batch = await stories.load(offset: offset);
      for (final s in batch) {
        existing[s.id] = s;
      }
      if (batch.length < 20) break;
      offset += batch.length;
    }
    for (final s in selectedStories) {
      progress('Recovering saved stories');
      await _guard(archive.familyId);
      final next = StoryProject(
          id: key('story', s.id),
          childId: targetChild,
          title: s.title,
          format: s.format,
          panels: s.panels.map((p) {
            final v = recovered[p.reference.assetId]!;
            return StoryPanel(
                id: key('panel', p.id),
                reference: StoryReference.fromVersion(v),
                characterName: v.name,
                versionNumber: v.number,
                scene: p.scene,
                dialogue: p.dialogue,
                narration: p.narration);
          }).toList());
      final old = existing[next.id];
      if (old != null) {
        if (canonicalBackupJson(old.toJson()..remove('revision')) !=
            canonicalBackupJson(next.toJson()..remove('revision')))
          throw const FormatException(
              'A recovered story has changed. It was kept and was not overwritten.');
      } else {
        await stories.save(next);
      }
    }
    for (final p in archive.pages) {
      final v = recovered[p['source_id']];
      if (v == null) continue;
      progress('Recovering saved page drafts');
      await _guard(archive.familyId);
      await pages.save(SavedStoryDraft(
          pageId: key('page', p['page_id']),
          reference: StoryReference.fromVersion(v),
          scene: p['scene'],
          dialogue: p['dialogue'],
          narration: p['narration']));
    }
    await _guard(archive.familyId);
    progress('Recovery finished. Review the copies in Family creations.');
  }
}
