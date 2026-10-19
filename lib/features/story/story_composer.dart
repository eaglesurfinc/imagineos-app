import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/device_drafts.dart';
import 'illustration_contract.dart';

/// Local one-page planning checkpoint, not a cloud-saved completed story.
class StoryComposer extends ChangeNotifier {
  StoryComposer(
      {required this.reference,
      required this.drafts,
      required this.draftKey,
      required this.gateway})
      : session = drafts.generation;
  static const maxAttempts = 2;
  final StoryReference reference;
  final DeviceDraftStore drafts;
  final String draftKey;
  final IllustrationGateway gateway;
  final int session;
  String pageId = const Uuid().v4();
  String scene = '', dialogue = '', narration = '';
  IllustrationRequest? request;
  IllustrationResult? result;
  int attempts = 0;
  bool ready = false,
      busy = false,
      recoveryFailed = false,
      corruptDraft = false;
  bool _disposed = false;
  bool get active => !_disposed && session == drafts.generation;
  bool get canCheck =>
      ready &&
      !busy &&
      !corruptDraft &&
      scene.trim().isNotEmpty &&
      scene.length <= 2000 &&
      attempts < maxAttempts &&
      (result == null || result!.retryable);

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'page_id': pageId,
        'reference': reference.toJson(),
        'scene': scene,
        'dialogue': dialogue,
        'narration': narration,
        'job': request == null
            ? null
            : {
                'request': request!.toJson(),
                'attempts': attempts,
                'state': busy ? 'submitting' : result?.state.name,
                'code': result?.code,
                'retryable': result?.retryable ?? false,
              },
      };

  Future<void> load() async {
    try {
      final raw = await drafts.read(draftKey);
      if (!active) return;
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['schema'] != 1 ||
            !reference.sameAs(StoryReference.fromJson(json['reference']))) {
          throw const FormatException('Draft reference mismatch.');
        }
        pageId = json['page_id'] as String;
        scene = json['scene'] as String;
        dialogue = json['dialogue'] as String;
        narration = json['narration'] as String;
        final job = json['job'];
        if (job != null) {
          request = IllustrationRequest.fromJson(job['request']);
          if (request!.pageId != pageId ||
              request!.scene != scene ||
              !request!.reference.sameAs(reference)) {
            throw const FormatException('Draft job mismatch.');
          }
          attempts = job['attempts'] as int;
          if (attempts < 1 || attempts > maxAttempts)
            throw const FormatException('Invalid retry count.');
          result = job['state'] == 'submitting'
              ? const IllustrationResult(
                  IllustrationState.failed, 'INTERRUPTED', retryable: true)
              : IllustrationResult(
                  IllustrationState.values.byName(job['state']),
                  job['code'] as String,
                  retryable: job['retryable'] == true);
        }
      }
    } catch (_) {
      // Do not overwrite an unreadable or newer-format recovery record.
      corruptDraft = true;
      recoveryFailed = true;
    }
    if (active) {
      ready = true;
      notifyListeners();
    }
  }

  void update({String? scene, String? dialogue, String? narration}) {
    if (!active || !ready || busy || corruptDraft) return;
    if (scene != null && scene != this.scene) {
      this.scene = scene;
      request = null;
      result = null;
      attempts = 0;
    }
    if (dialogue != null) this.dialogue = dialogue;
    if (narration != null) this.narration = narration;
    notifyListeners();
    // Each edit is queued, with no debounce window for committed field changes.
    unawaited(checkpoint());
  }

  Future<bool> checkpoint() async {
    if (!active || corruptDraft) return false;
    try {
      await drafts.write(draftKey, jsonEncode(toJson()), session);
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

  Future<void> check() async {
    if (!canCheck) return;
    final previousResult = result;
    request ??=
        IllustrationRequest(pageId: pageId, reference: reference, scene: scene);
    busy = true;
    attempts++;
    result = null;
    notifyListeners();
    // Checkpoint the stable identity/attempt BEFORE any network call.
    if (!await checkpoint()) {
      if (active) {
        busy = false;
        attempts--;
        result = previousResult;
        if (attempts == 0) request = null;
        notifyListeners();
      }
      return;
    }
    IllustrationResult next;
    try {
      next = await gateway.check(request!).timeout(const Duration(seconds: 16));
    } catch (_) {
      next = const IllustrationResult(
          IllustrationState.failed, 'TRANSPORT_FAILED',
          retryable: true);
    }
    if (!active) return;
    result = next;
    busy = false;
    notifyListeners();
    await checkpoint();
  }

  Future<bool> discard() async {
    if (!active || busy) return false;
    try {
      await drafts.drop(draftKey, session);
      if (!active) return false;
      scene = '';
      dialogue = '';
      narration = '';
      pageId = const Uuid().v4();
      request = null;
      result = null;
      attempts = 0;
      corruptDraft = false;
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
