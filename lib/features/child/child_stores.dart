import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../library/character_store.dart';
import '../story/illustration_contract.dart';
import '../story/story_draft_store.dart';
import '../story/story_project.dart';
import '../story/story_project_store.dart';
import 'child_access.dart';

class ChildCharacterStore implements CharacterStore {
  const ChildCharacterStore(this.access);
  final ChildAccess access;
  @override
  Future<CharacterLibrary> load() async {
    final data = Map<String, dynamic>.from(
        await access.call({'action': 'library'}) as Map);
    return CharacterLibrary(
        (data['creators'] as List)
            .map((c) =>
                CreatorProfile(c['id'] as String, c['nickname'] as String))
            .toList(),
        (data['versions'] as List)
            .map((v) =>
                OriginalVersion.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList());
  }

  @override
  Future<void> addCreator(String nickname) async {
    throw const ChildAccessException(
        'Ask your parent to manage child profiles.');
  }

  @override
  Future<void> deleteCharacter(String characterId, {String? versionId}) async {
    throw const ChildAccessException(
        'Ask your parent to permanently delete saved work.');
  }

  @override
  Future<void> discard(OriginalVersion version) async {
    throw const ChildAccessException(
        'Ask your parent to discard this unfinished cloud upload.');
  }

  @override
  Future<Uint8List> read(OriginalVersion version) async {
    final data = await access
        .call({'action': 'download', 'asset_id': version.requestId});
    if (data is! Uint8List ||
        sha256.convert(data).toString() != version.checksum) {
      throw const FormatException('This saved drawing could not be verified.');
    }
    return data;
  }

  @override
  Future<void> save(OriginalDraft draft) async {
    final row = await access.call({
      'action': 'reserve',
      'request_id': draft.requestId,
      'child_id': draft.childId,
      'character_id': draft.characterId,
      'name': draft.name.trim(),
      'mime_type': draft.file.mimeType,
      'byte_size': draft.file.bytes.length,
      'sha256': draft.file.checksum
    });
    final version =
        OriginalVersion.fromJson(Map<String, dynamic>.from(row as Map));
    if (version.state == 'ready') return;
    await access.call({
      'action': 'upload',
      'asset_id': version.requestId,
      'bytes': base64Encode(draft.file.bytes)
    });
    await finish(version);
  }

  @override
  Future<void> finish(OriginalVersion version) async {
    await read(version);
    await access.call({'action': 'finish', 'asset_id': version.requestId});
  }
}

class ChildStoryProjectStore implements StoryProjectStore {
  const ChildStoryProjectStore(this.access);
  final ChildAccess access;
  @override
  Future<List<StoryProject>> load({int offset = 0}) async => (await access
          .call({'action': 'stories', 'offset': offset}) as List)
      .map((p) => StoryProject.fromJson(Map<String, dynamic>.from(p as Map)))
      .toList();
  @override
  Future<int> save(StoryProject story) async {
    final result = await access.call({
      'action': 'save_story',
      'id': story.id,
      'child_id': story.childId,
      'revision': story.revision,
      'title': story.title,
      'format': story.format.name,
      'panels': story.panels.map((p) => p.saveJson).toList()
    });
    if (result is! int || result < 1)
      throw const FormatException('Save not confirmed');
    return result;
  }

  @override
  Future<void> delete(StoryProject story) async {
    throw const ChildAccessException(
        'Ask your parent to permanently delete a saved story.');
  }
}

class ChildStoryDraftStore implements StoryDraftStore {
  const ChildStoryDraftStore(this.access);
  final ChildAccess access;
  @override
  Future<List<SavedStoryDraft>> load(StoryReference reference) async {
    final rows = await access
        .call({'action': 'pages', 'asset_id': reference.assetId}) as List;
    return rows
        .map((p) => SavedStoryDraft(
            pageId: p['page_id'] as String,
            reference: reference,
            scene: p['scene'] as String,
            dialogue: p['dialogue'] as String,
            narration: p['narration'] as String,
            revision: p['revision'] as int))
        .toList();
  }

  @override
  Future<int> save(SavedStoryDraft draft) async {
    final result = await access.call({
      'action': 'save_page',
      'asset_id': draft.reference.assetId,
      'page_id': draft.pageId,
      'revision': draft.revision,
      'scene': draft.scene,
      'dialogue': draft.dialogue,
      'narration': draft.narration
    });
    if (result is! int || result < 1)
      throw const FormatException('Save not confirmed');
    return result;
  }
}
