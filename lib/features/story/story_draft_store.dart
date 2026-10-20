import 'package:supabase_flutter/supabase_flutter.dart';

import 'illustration_contract.dart';

class SavedStoryDraft {
  const SavedStoryDraft(
      {required this.pageId,
      required this.reference,
      required this.scene,
      required this.dialogue,
      required this.narration,
      this.revision = 0});
  final String pageId, scene, dialogue, narration;
  final StoryReference reference;
  final int revision;
}

abstract class StoryDraftStore {
  Future<List<SavedStoryDraft>> load(StoryReference reference);
  Future<int> save(SavedStoryDraft draft);
}

class SupabaseStoryDraftStore implements StoryDraftStore {
  const SupabaseStoryDraftStore(this.client);
  final SupabaseClient client;
  @override
  Future<List<SavedStoryDraft>> load(StoryReference reference) async {
    final identity = client.auth.currentUser?.id;
    if (identity == null) throw StateError('Sign in first');
    final rows = await client
        .from('saved_story_drafts')
        .select()
        .eq('source_id', reference.assetId)
        .order('updated_at', ascending: false)
        .limit(20);
    if (identity != client.auth.currentUser?.id)
      throw StateError('Session changed');
    return rows.map((row) {
      final pinned = StoryReference(
          row['character_id'] as String,
          row['version_id'] as String,
          row['source_id'] as String,
          row['sha256'] as String);
      if (!pinned.sameAs(reference))
        throw const FormatException('Source mismatch');
      return SavedStoryDraft(
          pageId: row['page_id'] as String,
          reference: pinned,
          scene: row['scene'] as String,
          dialogue: row['dialogue'] as String,
          narration: row['narration'] as String,
          revision: row['revision'] as int);
    }).toList(growable: false);
  }

  @override
  Future<int> save(SavedStoryDraft draft) async {
    final identity = client.auth.currentUser?.id;
    if (identity == null) throw StateError('Sign in first');
    final revision = await client.rpc('save_story_draft', params: {
      'p_page_id': draft.pageId,
      'p_source_id': draft.reference.assetId,
      'p_revision': draft.revision,
      'p_scene': draft.scene,
      'p_dialogue': draft.dialogue,
      'p_narration': draft.narration,
    });
    if (identity != client.auth.currentUser?.id ||
        revision is! int ||
        revision < 1) {
      throw StateError('Save not confirmed');
    }
    return revision;
  }
}
