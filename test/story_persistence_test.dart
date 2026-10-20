import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/features/story/story_composer.dart';
import 'package:imagineos/features/story/story_draft_store.dart';
import 'package:imagineos/features/story/story_draft_screen.dart';
import 'package:imagineos/features/story/story_export.dart';
import 'package:imagineos/features/story/illustration_contract.dart';
import 'package:imagineos/features/library/character_store.dart';

import 'support/memory_drawing_drafts.dart';

const ref = StoryReference('character', 'version', 'asset', 'checksum');
const exact = '  Keep  “my words” 🌈\n\n<script>alert("hi")</script>\nمرحبا  ';
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGNw09iCFTEMLQkAOOxIgSesf3AAAAAASUVORK5CYII=');

class FakeStories implements StoryDraftStore {
  SavedStoryDraft? saved;
  bool fail = false;
  @override
  Future<List<SavedStoryDraft>> load(StoryReference reference) async =>
      saved == null ? [] : [saved!];
  @override
  Future<int> save(SavedStoryDraft draft) async {
    if (fail) throw StateError('network unavailable');
    saved = draft;
    return 1;
  }
}

void main() {
  test(
      'printable export escapes markup and embeds original bytes and pinned references',
      () {
    const draft = SavedStoryDraft(
        pageId: 'page',
        reference: ref,
        scene: 'jump',
        dialogue: exact,
        narration: '\n END  ');
    final html = utf8.decode(exportStoryDraft(draft, png, 'image/png'));
    expect(html, contains('base64,${base64Encode(png)}'));
    expect(html, contains(const HtmlEscape().convert(exact)));
    expect(html, isNot(contains('<script>alert')));
    expect(html, contains('content="version"'));
    expect(html, contains('content="checksum"'));
    expect(html, contains('white-space:pre-wrap'));
    expect(html, contains('original artwork with your exact words'));
    expect(() => exportStoryDraft(draft, Uint8List(1), 'image/svg+xml'),
        throwsFormatException);
  });
  test(
      'saved revision and exact cloud words survive device recovery without retargeting',
      () async {
    final drafts = MemoryDrawingDrafts();
    StoryComposer make() => StoryComposer(
        reference: ref,
        drafts: drafts,
        draftKey: 'story',
        gateway: const DisabledIllustrationGateway());
    final composer = make();
    await composer.load();
    const page = SavedStoryDraft(
        pageId: 'page',
        reference: ref,
        scene: 'jump',
        dialogue: exact,
        narration: '  End\n',
        revision: 3);
    expect(await composer.restoreSaved(page), true);
    composer.dispose();
    final restored = make();
    await restored.load();
    expect(restored.snapshot.pageId, 'page');
    expect(restored.snapshot.revision, 3);
    expect(restored.dialogue, exact);
    expect(restored.narration, '  End\n');
    expect(
        await restored.restoreSaved(const SavedStoryDraft(
            pageId: 'bad',
            reference: StoryReference('other', 'version', 'asset', 'checksum'),
            scene: '',
            dialogue: '',
            narration: '')),
        false);
    expect(restored.dialogue, exact);
    restored.dispose();
  });
  testWidgets(
      'failed cloud saves keep exact fields and retries use the same page identity',
      (tester) async {
    final stories = FakeStories()..fail = true;
    final drafts = MemoryDrawingDrafts();
    final version = OriginalVersion.fromJson({
      'request_id': 'asset',
      'character_id': 'character',
      'child_profile_id': 'creator',
      'version_id': 'version',
      'version_number': 1,
      'name': 'Moon friend',
      'object_path': 'original',
      'sha256': 'checksum',
      'state': 'ready'
    });
    await tester.pumpWidget(MaterialApp(
        home: StoryDraftScreen(
            version: version,
            image: png,
            draftScope: 'adult',
            drafts: drafts,
            store: stories)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'jump');
    await tester.enterText(find.byType(TextField).at(1), exact);
    await tester.scrollUntilVisible(find.text('Save page draft'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save page draft'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not confirm this save'), findsOneWidget);
    final checkpoint =
        jsonDecode((await drafts.read(drafts.key('adult', 'story.version')))!)
            as Map;
    expect(checkpoint['dialogue'], exact);
    stories.fail = false;
    await tester.tap(find.text('Save page draft'));
    await tester.pumpAndSettle();
    expect(stories.saved!.dialogue, exact);
    expect(stories.saved!.pageId, checkpoint['page_id']);
    expect(stories.saved!.reference.sameAs(ref), true);
    expect(
        find.text('Page draft saved to your family account.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
