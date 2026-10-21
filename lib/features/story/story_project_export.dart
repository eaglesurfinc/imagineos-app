import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../library/character_store.dart';
import 'story_project.dart';

/// Original drawings only. No screenshotting, rewriting, cropping or AI calls.
Uint8List exportStoryProject(
    StoryProject story, Map<String, OriginalFile> artwork,
    {bool includeSceneNotes = false, bool includeUnavailableArtwork = false}) {
  if (story.panels.isEmpty)
    throw const FormatException('Add a page or panel first.');
  const escape = HtmlEscape();
  String e(String text) => escape.convert(text);
  final body = StringBuffer();
  var estimatedBytes = 0;
  for (var index = 0; index < story.panels.length; index++) {
    final panel = story.panels[index],
        file = artwork[story.panels[index].reference.assetId];
    final placeholder = !panel.sourceAvailable && includeUnavailableArtwork;
    if (!placeholder &&
        (!panel.sourceAvailable ||
            file == null ||
            !const {'image/png', 'image/jpeg', 'image/webp'}
                .contains(file.mimeType) ||
            sha256.convert(file.bytes).toString() != panel.reference.sha)) {
      throw const FormatException(
          'An original drawing is unavailable. Your words are kept. Reopen the story and check its drawings before exporting.');
    }
    estimatedBytes += (placeholder ? 0 : (file!.bytes.length * 4 / 3).ceil()) +
        utf8.encode(panel.scene + panel.dialogue + panel.narration).length * 6;
    if (estimatedBytes > 50 * 1024 * 1024)
      throw const FormatException(
          'This printable copy is too large for this export. Your saved story is kept.');
    if (index % story.format.perSheet == 0)
      body.write('<section class="sheet"><div class="panels">');
    body.write(
        '''<article class="panel" data-panel-id="${e(panel.id)}" data-asset-id="${e(panel.reference.assetId)}" data-character-id="${e(panel.reference.characterId)}" data-version-id="${e(panel.reference.versionId)}" data-sha256="${e(panel.reference.sha)}">
${placeholder ? '<div class="missing-art" role="note">Drawing unavailable. Your scene and words are kept.</div>' : '<img alt="${e(panel.characterName)} — original drawing" src="data:${file!.mimeType};base64,${base64Encode(file.bytes)}">'}
${includeSceneNotes && panel.scene.isNotEmpty ? '<div class="words scene" aria-label="Scene direction">${e(panel.scene)}</div>' : ''}
${panel.dialogue.isNotEmpty ? '<div class="words dialogue" aria-label="Dialogue">${e(panel.dialogue)}</div>' : ''}
${panel.narration.isNotEmpty ? '<div class="words narration" aria-label="Narration">${e(panel.narration)}</div>' : ''}
</article>''');
    if ((index + 1) % story.format.perSheet == 0 ||
        index == story.panels.length - 1) body.write('</div></section>');
  }
  return Uint8List.fromList(utf8.encode('''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="imagineos-story-id" content="${e(story.id)}"><title>${e(story.title)}</title>
<style>body{margin:0;color:#183844;background:#eef5f4;font:20px/1.5 system-ui,sans-serif}main{max-width:1000px;margin:auto;padding:16px}.story-title,.words{white-space:pre-wrap;overflow-wrap:anywhere}.story-title{font-size:2rem}.sheet{padding:24px;background:white;margin:24px 0}.panels{display:grid;grid-template-columns:1fr;gap:20px}.panel{min-width:0;padding:16px;box-sizing:border-box}.comic .panels{grid-template-columns:repeat(2,minmax(0,1fr))}.strip .panels{grid-template-columns:repeat(3,minmax(0,1fr))}.comic .panel,.strip .panel{border:2px solid #183844;border-radius:8px}img{display:block;width:100%;height:320px;object-fit:contain}.words{margin-top:16px}.dialogue{border:2px solid #53737c;border-radius:20px;padding:16px}.scene{font-style:italic}.draft-note{font-size:14px}@media(max-width:600px){.comic .panels,.strip .panels{grid-template-columns:1fr}.sheet{padding:8px}img{height:260px}}@media print{body{background:white}main{padding:0;max-width:none}.sheet{break-before:page;margin:0;padding:12px}.sheet:first-of-type{break-before:auto}.comic .panels{grid-template-columns:repeat(2,minmax(0,1fr))}.strip .panels{grid-template-columns:repeat(3,minmax(0,1fr))}.panel{break-inside:avoid}img{height:220px}.draft-note{font-size:10px}}@page{margin:15mm}</style>
</head><body><main class="${story.format.name}">${story.title.isNotEmpty ? '<h1 class="story-title">${e(story.title)}</h1>' : ''}
<p class="draft-note">Original-artwork draft. Drawings and words belong to the creator. No AI scene illustration is included.</p>
$body</main></body></html>'''));
}
