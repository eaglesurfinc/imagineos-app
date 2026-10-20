import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'story_draft_store.dart';

/// A self-contained, printable original-artwork draft. Exact text is escaped,
/// never interpreted as markup. No network, scripts or generated art is used.
Uint8List exportStoryDraft(
    SavedStoryDraft draft, Uint8List artwork, String mime) {
  if (!const {'image/png', 'image/jpeg', 'image/webp'}.contains(mime) ||
      artwork.isEmpty) {
    throw const FormatException('Unsupported original artwork');
  }
  const escape = HtmlEscape();
  String e(String value) => escape.convert(value);
  final reference = draft.reference;
  return Uint8List.fromList(utf8.encode('''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="imagineos-character-id" content="${e(reference.characterId)}">
<meta name="imagineos-version-id" content="${e(reference.versionId)}">
<meta name="imagineos-asset-id" content="${e(reference.assetId)}">
<meta name="imagineos-source-sha256" content="${e(reference.sha)}">
<title>ImagineOS page draft</title>
<style>body{margin:0;background:#f4f6f5;color:#183844;font:20px/1.4 system-ui,sans-serif}main{box-sizing:border-box;max-width:680px;margin:24px auto;padding:32px;background:white}img{display:block;width:100%;height:360px;object-fit:contain}.words{white-space:pre-wrap;overflow-wrap:anywhere;margin-top:32px}footer{font-size:14px;margin-top:32px}@media print{body{background:white}main{margin:0;max-width:none;padding:16px}.words{break-inside:auto}}</style>
</head><body><main><img alt="Saved original drawing" src="data:$mime;base64,${base64Encode(artwork)}">
<div class="words" aria-label="Dialogue">${e(draft.dialogue)}</div>
<div class="words" aria-label="Narration">${e(draft.narration)}</div>
<footer>ImagineOS page draft — original artwork with your exact words.</footer>
</main></body></html>'''));
}

typedef SaveStoryDraft = Future<bool> Function(Uint8List bytes, String name);
Future<bool> saveStoryDraftToDevice(Uint8List bytes, String name) async {
  final file = XFile.fromData(bytes, mimeType: 'text/html', name: name);
  if (kIsWeb) {
    await file.saveTo(name);
    return true;
  }
  final location =
      await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [
    XTypeGroup(label: 'Printable story draft', extensions: ['html'])
  ]);
  if (location == null) return false;
  await file.saveTo(location.path);
  return true;
}
