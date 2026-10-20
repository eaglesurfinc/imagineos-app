import 'package:supabase_flutter/supabase_flutter.dart';

import 'story_project.dart';

abstract class StoryProjectStore {
  Future<List<StoryProject>> load({int offset = 0});
  Future<int> save(StoryProject story);
  Future<void> delete(StoryProject story);
}

class SupabaseStoryProjectStore implements StoryProjectStore {
  const SupabaseStoryProjectStore(this.client);
  final SupabaseClient client;
  String _identity() =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in first'));
  void _confirm(String identity) {
    if (_identity() != identity) throw StateError('Session changed');
  }

  @override
  Future<List<StoryProject>> load({int offset = 0}) async {
    final identity = _identity();
    final rows = await client
        .from('story_project_snapshots')
        .select()
        .order('updated_at', ascending: false)
        .order('id')
        .range(offset, offset + 19);
    _confirm(identity);
    return rows.map(StoryProject.fromJson).toList(growable: false);
  }

  @override
  Future<int> save(StoryProject story) async {
    final identity = _identity();
    final revision = await client.rpc('save_story_project', params: {
      'p_id': story.id,
      'p_child_id': story.childId,
      'p_revision': story.revision,
      'p_title': story.title,
      'p_format': story.format.name,
      'p_panels': story.panels.map((p) => p.saveJson).toList()
    });
    _confirm(identity);
    if (revision is! int || revision < 1)
      throw StateError('Save not confirmed');
    return revision;
  }

  @override
  Future<void> delete(StoryProject story) async {
    final identity = _identity();
    await client.rpc('delete_story_project',
        params: {'p_id': story.id, 'p_revision': story.revision});
    _confirm(identity);
  }
}
