import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as image;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const originalBucket = 'character-originals';
const maxOriginalBytes = 5 * 1024 * 1024;

bool isMissingOriginal(StorageException error) {
  if (error.statusCode == '404' || error.error == 'not_found') return true;
  // Binary downloads deliberately preserve the error body instead of parsing
  // it. Storage wraps NoSuchKey in HTTP 400; do not swallow other 400/403 errors.
  if (error.statusCode != '400') return false;
  try {
    final body = jsonDecode(error.message);
    return body is Map &&
        body['statusCode']?.toString() == '404' &&
        body['code'] == 'NoSuchKey';
  } catch (_) {
    return false;
  }
}

class OriginalFile {
  OriginalFile(this.bytes, this.mimeType)
      : checksum = sha256.convert(bytes).toString();
  final Uint8List bytes;
  final String mimeType;
  final String checksum;
}

Future<OriginalFile> validateOriginal(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > maxOriginalBytes) {
    throw const FormatException('Choose an image up to 5 MB.');
  }
  final String mime;
  if (bytes.length >= 8 &&
      bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
    mime = 'image/png';
  } else if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    mime = 'image/jpeg';
  } else if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    mime = 'image/webp';
  } else {
    throw const FormatException('Choose a PNG, JPEG, or WebP image.');
  }
  ui.Codec? codec;
  try {
    // ImageDescriptor's encoded width/height are unsupported on Flutter Web.
    // Read header dimensions without expanding pixels, then validate rendering.
    final image.Decoder decoder = switch (mime) {
      'image/png' => image.PngDecoder(),
      'image/jpeg' => image.JpegDecoder(),
      _ => image.WebPDecoder(),
    };
    final info = decoder.startDecode(bytes);
    if (info == null || info.width < 1 || info.height < 1) {
      throw const FormatException(
          'This image could not be opened. Choose another image.');
    }
    if (info.width * info.height > 16000000 ||
        info.width > 8192 ||
        info.height > 8192) {
      throw const FormatException(
          'Choose an image no larger than 16 megapixels.');
    }
    codec = await ui.instantiateImageCodec(bytes,
        targetWidth: info.width > 1024 ? 1024 : null, allowUpscaling: false);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
        'This image could not be opened. Choose another image.');
  } finally {
    codec?.dispose();
  }
  return OriginalFile(bytes, mime);
}

Future<OriginalFile?> pickOriginal() async {
  final file = await openFile(acceptedTypeGroups: const [
    XTypeGroup(
        label: 'Original drawing',
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
        mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
        uniformTypeIdentifiers: ['public.image']),
  ]);
  if (file == null) return null;
  if (await file.length() > maxOriginalBytes) {
    throw const FormatException('Choose an image up to 5 MB.');
  }
  return validateOriginal(await file.readAsBytes());
}

class CreatorProfile {
  const CreatorProfile(this.id, this.nickname);
  final String id;
  final String nickname;
}

class OriginalVersion {
  OriginalVersion.fromJson(Map<String, dynamic> json)
      : requestId = json['request_id'] as String,
        characterId = json['character_id'] as String,
        childId = json['child_profile_id'] as String,
        versionId = json['version_id'] as String,
        number = json['version_number'] as int,
        name = json['name'] as String,
        objectPath = json['object_path'] as String,
        checksum = json['sha256'] as String,
        deletingCharacter = json['deleting_character'] as bool? ?? false,
        state = json['state'] as String;
  final bool deletingCharacter;
  final String requestId,
      characterId,
      childId,
      versionId,
      name,
      objectPath,
      checksum,
      state;
  final int number;
}

class CharacterLibrary {
  const CharacterLibrary(this.creators, this.versions);
  final List<CreatorProfile> creators;
  final List<OriginalVersion> versions;
}

class OriginalDraft {
  OriginalDraft(
      {required this.childId,
      required this.name,
      required this.file,
      this.characterId,
      String? requestId})
      : requestId = requestId ?? const Uuid().v4();
  final String childId, name, requestId;
  final String? characterId;
  final OriginalFile file;
}

abstract class CharacterStore {
  Future<CharacterLibrary> load();
  Future<void> addCreator(String nickname);
  Future<void> save(OriginalDraft draft);
  Future<void> finish(OriginalVersion version);
  Future<void> discard(OriginalVersion version);
  Future<void> deleteCharacter(String characterId, {String? versionId});
  Future<Uint8List> read(OriginalVersion version);
}

class SupabaseCharacterStore implements CharacterStore {
  SupabaseCharacterStore(this.client);
  final SupabaseClient client;

  @override
  Future<void> deleteCharacter(String characterId, {String? versionId}) async {
    final params = {'p_character_id': characterId, 'p_version_id': versionId};
    final paths = List<String>.from(
        await client.rpc('begin_character_deletion', params: params) as List);
    // Storage must remove the actual files before SQL references can disappear.
    for (var start = 0; start < paths.length; start += 100) {
      final end = (start + 100).clamp(0, paths.length);
      await client.storage
          .from(originalBucket)
          .remove(paths.sublist(start, end));
    }
    await client.rpc('finish_character_deletion', params: params);
  }

  @override
  Future<CharacterLibrary> load() async {
    final creators = await client
        .from('child_profiles')
        .select('id,nickname')
        .order('created_at');
    final versions = await client
        .from('original_uploads')
        .select()
        .neq('state', 'cancelled')
        .order('version_number', ascending: false);
    return CharacterLibrary(
      creators
          .map((row) =>
              CreatorProfile(row['id'] as String, row['nickname'] as String))
          .toList(),
      versions.map(OriginalVersion.fromJson).toList(),
    );
  }

  @override
  Future<void> addCreator(String nickname) async {
    final family = await client.from('families').select('id').single();
    await client
        .from('child_profiles')
        .insert({'family_id': family['id'], 'nickname': nickname.trim()});
  }

  @override
  Future<void> save(OriginalDraft draft) async {
    final row = await client.rpc('reserve_original', params: {
      'p_request_id': draft.requestId,
      'p_child_id': draft.childId,
      'p_character_id': draft.characterId,
      'p_name': draft.name.trim(),
      'p_mime_type': draft.file.mimeType,
      'p_byte_size': draft.file.bytes.length,
      'p_sha256': draft.file.checksum,
    });
    final version =
        OriginalVersion.fromJson(Map<String, dynamic>.from(row as Map));
    if (version.state == 'ready') return;
    // A lost upload response must not cause overwrite or duplicate versions.
    Uint8List? existing;
    try {
      existing = await client.storage
          .from(originalBucket)
          .download(version.objectPath);
    } on StorageException catch (error) {
      if (!isMissingOriginal(error)) rethrow;
    }
    if (existing != null) {
      if (sha256.convert(existing).toString() != draft.file.checksum) {
        throw const FormatException(
            'The unfinished file differs from this original. Discard it and start again.');
      }
    } else {
      await client.storage.from(originalBucket).uploadBinary(
          version.objectPath, draft.file.bytes,
          fileOptions:
              FileOptions(contentType: draft.file.mimeType, upsert: false));
    }
    await finish(version);
  }

  @override
  Future<void> finish(OriginalVersion version) async {
    // Verify exact bytes before publication, including recovered uploads.
    await read(version);
    await client
        .rpc('finish_original', params: {'p_request_id': version.requestId});
  }

  @override
  Future<void> discard(OriginalVersion version) async {
    await client.storage.from(originalBucket).remove([version.objectPath]);
    await client
        .rpc('cancel_original', params: {'p_request_id': version.requestId});
  }

  @override
  Future<Uint8List> read(OriginalVersion version) async {
    final bytes =
        await client.storage.from(originalBucket).download(version.objectPath);
    if (sha256.convert(bytes).toString() != version.checksum) {
      throw const FormatException(
          'The saved image could not be verified. Please try again.');
    }
    return bytes;
  }
}
