import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../library/character_store.dart';

/// Immutable saved source; never resolve a page reference to 'latest'.
class StoryReference {
  const StoryReference(
      this.characterId, this.versionId, this.assetId, this.sha);
  factory StoryReference.fromVersion(OriginalVersion version) => StoryReference(
      version.characterId,
      version.versionId,
      version.requestId,
      version.checksum);
  factory StoryReference.fromJson(Map<String, dynamic> json) => StoryReference(
      json['character_id'] as String,
      json['version_id'] as String,
      json['asset_id'] as String,
      json['sha256'] as String);
  final String characterId, versionId, assetId, sha;
  Map<String, dynamic> toJson() => {
        'character_id': characterId,
        'version_id': versionId,
        'asset_id': assetId,
        'sha256': sha,
      };
  bool sameAs(StoryReference other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

/// Text for the page is intentionally absent from this illustration contract.
class IllustrationRequest {
  IllustrationRequest(
      {required this.pageId,
      required this.reference,
      required this.scene,
      String? requestId,
      String? traceId})
      : requestId = requestId ?? const Uuid().v4(),
        traceId = traceId ?? const Uuid().v4();
  factory IllustrationRequest.fromJson(Map<String, dynamic> json) {
    if (json['contract_version'] != 1 || json['layout'] != 'portrait') {
      throw const FormatException('Unsupported illustration contract.');
    }
    return IllustrationRequest(
        pageId: json['page_id'] as String,
        reference:
            StoryReference.fromJson(json['character'] as Map<String, dynamic>),
        scene: json['scene_direction'] as String,
        requestId: json['request_id'] as String,
        traceId: json['trace_id'] as String);
  }
  final String pageId, scene, requestId, traceId;
  final StoryReference reference;
  String get fingerprint => sha256
      .convert(utf8.encode(jsonEncode([
        1,
        pageId,
        reference.characterId,
        reference.versionId,
        reference.assetId,
        reference.sha,
        scene,
        'portrait',
      ])))
      .toString();
  Map<String, dynamic> toJson() => {
        'contract_version': 1,
        'request_id': requestId,
        'trace_id': traceId,
        'page_id': pageId,
        'character': reference.toJson(),
        'scene_direction': scene,
        'layout': 'portrait',
      };
}

enum IllustrationState { draft, submitting, disabled, rejected, failed }

class IllustrationResult {
  const IllustrationResult(this.state, this.code, {this.retryable = false});
  final IllustrationState state;
  final String code;
  final bool retryable;

  factory IllustrationResult.parse(Object? data, IllustrationRequest request) {
    if (data is! Map ||
        data.length != 10 ||
        data['contract_version'] != 1 ||
        data['request_id'] != request.requestId ||
        data['trace_id'] != request.traceId ||
        data['fingerprint'] != request.fingerprint ||
        !data.containsKey('output') ||
        data['output'] != null ||
        data['cost_micros'] != 0 ||
        data['provider_attempts'] != 0) {
      throw const FormatException('Invalid gateway result.');
    }
    final state = data['status'],
        code = data['code'],
        retry = data['retryable'];
    if (state == 'disabled' &&
        code == 'GENERATION_DISABLED' &&
        retry == false) {
      return const IllustrationResult(
          IllustrationState.disabled, 'GENERATION_DISABLED');
    }
    if (state == 'rejected' &&
        retry == false &&
        const ['AUTH_REQUIRED', 'REFERENCE_UNAVAILABLE'].contains(code)) {
      return IllustrationResult(IllustrationState.rejected, code as String);
    }
    if (state == 'failed' && code == 'BACKEND_UNAVAILABLE' && retry == true) {
      return const IllustrationResult(
          IllustrationState.failed, 'BACKEND_UNAVAILABLE',
          retryable: true);
    }
    throw const FormatException('Unsupported gateway result.');
  }

  String get message => switch (code) {
        'GENERATION_DISABLED' =>
          'Illustration is turned off. Your page draft and exact words are kept on this device.',
        'AUTH_REQUIRED' =>
          'Sign in again before checking illustration availability. Your draft is kept.',
        'REFERENCE_UNAVAILABLE' =>
          'This saved drawing is unavailable. Your words are kept; reopen the character to check it.',
        'INVALID_RESPONSE' =>
          'The illustration response could not be verified. Your draft is kept.',
        'INTERRUPTED' =>
          'The previous check was interrupted. Your draft is kept.',
        _ =>
          'The illustration service could not be reached. Your draft is kept.',
      };
}

abstract interface class IllustrationGateway {
  Future<IllustrationResult> check(IllustrationRequest request);
}

/// Offline/test fallback is explicitly disabled, never a simulated image.
class DisabledIllustrationGateway implements IllustrationGateway {
  const DisabledIllustrationGateway();
  @override
  Future<IllustrationResult> check(IllustrationRequest request) async =>
      const IllustrationResult(
          IllustrationState.disabled, 'GENERATION_DISABLED');
}

class SupabaseIllustrationGateway implements IllustrationGateway {
  const SupabaseIllustrationGateway(this.client);
  final SupabaseClient client;
  @override
  Future<IllustrationResult> check(IllustrationRequest request) async {
    Object? body;
    try {
      final response = await client.functions
          .invoke('illustration-gateway', body: request.toJson())
          .timeout(const Duration(seconds: 15));
      body = response.data;
    } on FunctionException catch (error) {
      // Platform authentication errors may precede the versioned handler.
      if (error.status == 401) {
        return const IllustrationResult(
            IllustrationState.rejected, 'AUTH_REQUIRED');
      }
      body = error.details;
    } catch (_) {
      return const IllustrationResult(
          IllustrationState.failed, 'TRANSPORT_FAILED',
          retryable: true);
    }
    try {
      return IllustrationResult.parse(body, request);
    } catch (_) {
      return const IllustrationResult(
          IllustrationState.rejected, 'INVALID_RESPONSE');
    }
  }
}
