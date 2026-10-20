import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/device_drafts.dart';
import 'story_project.dart';
import 'story_project_store.dart';

/// No generation dependency: guidance/layout cannot change a child's words.
class StoryProjectComposer extends ChangeNotifier {
  StoryProjectComposer(
      {required this.story,
      required this.store,
      required this.drafts,
      required this.draftKey})
      : session = drafts.generation;
  StoryProject story;
  final StoryProjectStore store;
  final DeviceDraftStore drafts;
  final String draftKey;
  final int session;
  bool ready = false, busy = false, corrupt = false, recoveryFailed = false;
  bool dirty = false, _disposed = false;
  String? message;
  int _edits = 0;
  bool get active => !_disposed && drafts.generation == session;

  Future<void> load() async {
    try {
      final raw = await drafts.read(draftKey);
      if (!active) return;
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final restored = StoryProject.fromJson(
            Map<String, dynamic>.from(json['story'] as Map));
        if (json['schema'] != 1 ||
            restored.id != story.id ||
            restored.childId != story.childId) {
          throw const FormatException('Recovery mismatch');
        }
        // Never silently overwrite a newer cloud revision with a stale device copy.
        if (restored.revision != story.revision) {
          message =
              'This device has a different draft. Choose which copy to open; your device draft is kept.';
          corrupt = true;
        } else {
          story = restored;
          dirty = json['dirty'] == true;
          message =
              'Your device draft is back. Saved copies stay in My stories.';
        }
      }
    } catch (_) {
      corrupt = true;
      message = 'This device draft could not be opened. It has been kept.';
    }
    if (active) {
      ready = true;
      notifyListeners();
    }
  }

  void update(StoryProject next) {
    if (!active ||
        !ready ||
        corrupt ||
        next.id != story.id ||
        next.childId != story.childId) return;
    story = next;
    dirty = true;
    _edits++;
    message = null;
    notifyListeners();
    unawaited(checkpoint());
  }

  Future<bool> checkpoint() async {
    if (!active || corrupt) return false;
    try {
      await drafts.write(
          draftKey,
          jsonEncode({'schema': 1, 'dirty': dirty, 'story': story.toJson()}),
          session);
      if (!active) return false;
      recoveryFailed = false;
      notifyListeners();
      return true;
    } catch (_) {
      if (active) {
        recoveryFailed = true;
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> save() async {
    if (!active || !ready || busy || corrupt) return;
    if (!story.withinSaveLimits) {
      message =
          'Your words are kept. Check the field counters before saving: title up to 160, scene notes up to 2,000, and dialogue or narration up to 20,000 characters per page or panel. Only you can edit your words.';
      notifyListeners();
      return;
    }
    busy = true;
    message = null;
    notifyListeners();
    final snapshot = story, edits = _edits;
    try {
      final revision = await store.save(snapshot);
      if (!active) return;
      story = story.copy(revision: revision);
      dirty = _edits != edits;
      message = dirty
          ? 'Saved that copy. Your newer edits still need saving.'
          : 'Your story is saved. Your words stay exactly yours.';
      await checkpoint();
    } catch (_) {
      if (active)
        message =
            'Could not confirm the save. Your story is kept here. Try again, or check the saved copy in My stories if another device changed it.';
    } finally {
      if (active) {
        busy = false;
        notifyListeners();
      }
    }
  }

  /// Explicit resolution only; the screen must confirm before replacing recovery.
  Future<void> useSavedCopy(StoryProject saved) async {
    if (!active ||
        busy ||
        saved.id != story.id ||
        saved.childId != story.childId) return;
    story = saved;
    corrupt = false;
    dirty = false;
    _edits++;
    message = 'Saved copy opened.';
    await checkpoint();
  }

  Future<void> useDeviceCopy() async {
    if (!active || busy || !corrupt) return;
    try {
      final raw = await drafts.read(draftKey);
      if (!active || raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final restored = StoryProject.fromJson(
          Map<String, dynamic>.from(json['story'] as Map));
      if (json['schema'] != 1 ||
          restored.id != story.id ||
          restored.childId != story.childId) throw const FormatException();
      story = restored;
      corrupt = false;
      dirty = true;
      message =
          'Device copy opened. A newer saved copy may need reviewing before you can save.';
      notifyListeners();
    } catch (_) {
      if (active) {
        message = 'Device copy could not be read. It is still kept.';
        notifyListeners();
      }
    }
  }

  Future<void> keepAsNewStory() async {
    if (!active || !ready || busy || corrupt) return;
    story = StoryProject(
        id: const Uuid().v4(),
        childId: story.childId,
        title: story.title,
        format: story.format,
        panels: story.panels
            .map((p) => StoryPanel(
                id: const Uuid().v4(),
                reference: p.reference,
                characterName: p.characterName,
                versionNumber: p.versionNumber,
                scene: p.scene,
                dialogue: p.dialogue,
                narration: p.narration,
                sourceAvailable: p.sourceAvailable))
            .toList());
    dirty = true;
    _edits++;
    message =
        'A separate working story keeps all your words and drawings. Save it when you are ready.';
    await checkpoint();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
