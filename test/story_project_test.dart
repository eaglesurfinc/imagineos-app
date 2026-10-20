import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/features/library/character_store.dart';
import 'package:imagineos/features/story/illustration_contract.dart';
import 'package:imagineos/features/story/story_project.dart';
import 'package:imagineos/features/story/story_project_composer.dart';
import 'package:imagineos/features/story/story_project_export.dart';
import 'package:imagineos/features/story/story_project_preview.dart';
import 'package:imagineos/features/story/story_project_screen.dart';
import 'package:imagineos/features/story/story_project_store.dart';

import 'character_library_test.dart' as originals;
import 'support/memory_drawing_drafts.dart';

const exactWords =
    '  Keep  MY words 🌈\n\n<script>not markup</script>\nمرحبا  ';
StoryPanel panel(String id) => StoryPanel(
    id: id,
    reference: StoryReference.fromVersion(originals.version(1)),
    characterName: 'Space friend',
    versionNumber: 1,
    scene: '  Walk.\n ',
    dialogue: exactWords,
    narration: '\n  My ending.  ');
StoryProject project({int revision = 0}) => StoryProject(
    id: 'story',
    childId: 'creator-1',
    title: '  My  title\n',
    revision: revision,
    panels: [panel('first'), panel('second')]);

class MemoryProjects implements StoryProjectStore {
  final saved = <StoryProject>[];
  Completer<int>? pending;
  bool fail = false;
  @override
  Future<List<StoryProject>> load({int offset = 0}) async => saved;
  @override
  Future<int> save(StoryProject story) async {
    saved.add(story);
    if (fail) throw StateError('offline');
    return pending?.future ?? Future.value(story.revision + 1);
  }

  @override
  Future<void> delete(StoryProject story) async {}
}

void main() {
  testWidgets('all story layouts reflow on a narrow screen with enlarged text',
      (tester) async {
    tester.view.reset();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final format in StoryFormat.values) {
      final story = project().copy(format: format);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: StoryProjectPreview(
                          story: story,
                          images: {
                            story.panels.first.reference.assetId:
                                originals.imageBytes
                          },
                          includeSceneNotes: true))))));
      await tester.pumpAndSettle();
      expect(find.text(exactWords), findsNWidgets(2));
      expect(find.text(story.panels.first.scene), findsNWidgets(2));
      expect(tester.takeException(), null);
    }
  });
  test(
      'format changes and explicit reordering preserve exact story and references',
      () {
    final original = project();
    for (final format in StoryFormat.values) {
      final changed = original.copy(
          format: format, panels: original.panels.reversed.toList());
      expect(changed.title, original.title);
      expect(changed.panels.map((p) => p.id), ['second', 'first']);
      for (final p in changed.panels) {
        expect(p.dialogue, exactWords);
        expect(p.reference.sameAs(original.panels.first.reference), true);
        expect(p.scene, original.panels.first.scene);
      }
      expect(
          StoryProject.fromJson(changed.toJson()).toJson(), changed.toJson());
    }
  });
  test(
      'save snapshots preserve newer edits and session changes fence late writes',
      () async {
    final drafts = MemoryDrawingDrafts(), store = MemoryProjects();
    final composer = StoryProjectComposer(
        story: project(), store: store, drafts: drafts, draftKey: 'project');
    await composer.load();
    store.pending = Completer<int>();
    final saving = composer.save();
    composer.update(composer.story.copy(title: 'My newer title'));
    store.pending!.complete(1);
    await saving;
    expect(store.saved.single.title, project().title);
    expect(composer.story.title, 'My newer title');
    expect(composer.story.revision, 1);
    expect(composer.dirty, true);
    store.pending = Completer<int>();
    final second = composer.save();
    await drafts.invalidate();
    store.pending!.complete(2);
    await second;
    expect(drafts.values, isEmpty);
    expect(composer.active, false);
    composer.dispose();
  });
  test(
      'cloud conflict never overwrites recovery and a separate story keeps every word',
      () async {
    final drafts = MemoryDrawingDrafts(), store = MemoryProjects();
    final old = project(revision: 1);
    await drafts.write('project',
        jsonEncode({'schema': 1, 'dirty': true, 'story': old.toJson()}), 0);
    final retained = drafts.values['project'];
    final composer = StoryProjectComposer(
        story: project(revision: 2),
        store: store,
        drafts: drafts,
        draftKey: 'project');
    await composer.load();
    expect(composer.corrupt, true);
    expect(await composer.checkpoint(), false);
    expect(drafts.values['project'], retained);
    await composer.useDeviceCopy();
    await composer.keepAsNewStory();
    expect(composer.story.id, isNot(old.id));
    expect(composer.story.revision, 0);
    expect(composer.story.title, old.title);
    expect(composer.story.panels.first.id, isNot(old.panels.first.id));
    expect(composer.story.panels.first.dialogue, exactWords);
    expect(
        composer.story.panels.first.reference
            .sameAs(old.panels.first.reference),
        true);
    await composer.save();
    expect(store.saved.single.panels.first.dialogue, exactWords);
    composer.dispose();
  });
  test('failed save and over-limit text stay recoverable without truncation',
      () async {
    final drafts = MemoryDrawingDrafts(), store = MemoryProjects()..fail = true;
    final composer = StoryProjectComposer(
        story: project(), store: store, drafts: drafts, draftKey: 'project');
    await composer.load();
    await composer.save();
    expect(composer.story.panels.first.dialogue, exactWords);
    final long = 'x' * 20001;
    composer.update(composer.story
        .copy(panels: [composer.story.panels.first.words(dialogue: long)]));
    await composer.checkpoint();
    await composer.save();
    expect(store.saved.length, 1);
    composer.dispose();
    final reopened = StoryProjectComposer(
        story: project(), store: store, drafts: drafts, draftKey: 'project');
    await reopened.load();
    expect(reopened.corrupt, false);
    expect(reopened.story.panels.single.dialogue, long);
    expect(reopened.story.withinSaveLimits, false);
    reopened.dispose();
  });
  test(
      'all printable formats embed original bytes, exact words and immutable pins',
      () {
    final file = OriginalFile(originals.imageBytes, 'image/png');
    for (final format in StoryFormat.values) {
      final story = project().copy(format: format);
      final html = utf8.decode(exportStoryProject(
          story, {story.panels.first.reference.assetId: file}));
      expect(html, contains(const HtmlEscape().convert(exactWords)));
      expect(html, contains('data-version-id="version-1"'));
      expect(html, contains('base64,${base64Encode(file.bytes)}'));
      expect(html, contains('object-fit:contain'));
      expect(html, contains('white-space:pre-wrap'));
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('aria-label="Scene direction"')));
      final withScenes = utf8.decode(exportStoryProject(
          story, {story.panels.first.reference.assetId: file},
          includeSceneNotes: true));
      expect(withScenes,
          contains(const HtmlEscape().convert(story.panels.first.scene)));
      expect(() => exportStoryProject(story, {}), throwsFormatException);
      expect(
          () => exportStoryProject(story, {
                story.panels.first.reference.assetId:
                    OriginalFile(Uint8List(1), 'image/png')
              }),
          throwsFormatException);
    }
  });
  testWidgets(
      'guide starts blank, reuses a character, changes layout and saves only typed content',
      (tester) async {
    final store = MemoryProjects(),
        characters = originals.FakeStore()..versions.add(originals.version(1));
    final library = await characters.load();
    await tester.pumpWidget(MaterialApp(
        home: StoryProjectScreen(
            story: StoryProject(id: 'guided', childId: 'creator-1'),
            store: store,
            characters: characters,
            library: library,
            drafts: MemoryDrawingDrafts(),
            draftKey: 'guided')));
    await tester.pumpAndSettle();
    Future<void> tap(String text) async {
      final target = find.text(text).last;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    expect(find.text('You are the creator.'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(tester.widget<TextField>(find.byType(TextField)).autocorrect, false);
    expect(tester.widget<TextField>(find.byType(TextField)).enableSuggestions,
        false);
    await tap('Comic pages');
    await tester.enterText(find.byType(TextField), '  My own title  ');
    await tester.pumpAndSettle();
    await tap('Next step');
    await tap('Add panel');
    await tap('Space friend — version 1');
    await tap('Add panel');
    await tap('Space friend — version 1');
    await tap('Next step');
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    for (final field in tester.widgetList<TextField>(fields)) {
      expect(field.controller!.text, '');
      expect(field.autocorrect, false);
      expect(field.enableSuggestions, false);
      expect(field.textCapitalization, TextCapitalization.none);
    }
    await tester.ensureVisible(fields.at(0));
    await tester.enterText(fields.at(0), '  Walking.\n ');
    await tester.pumpAndSettle();
    await tester.ensureVisible(fields.at(1));
    await tester.enterText(fields.at(1), exactWords);
    await tester.pumpAndSettle();
    await tap('Next step');
    final arrow = find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
    await tester.scrollUntilVisible(arrow, 180,
        scrollable: find.byType(Scrollable).first);
    await Scrollable.ensureVisible(tester.element(arrow), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(arrow);
    await tester.pumpAndSettle();
    await tap('Save for later');
    expect(store.saved.single.title, '  My own title  ');
    expect(store.saved.single.format, StoryFormat.comic);
    expect(store.saved.single.panels.first.dialogue, exactWords);
    expect(store.saved.single.panels.last.dialogue, '');
    expect(
        store.saved.single.panels.first.reference
            .sameAs(store.saved.single.panels.last.reference),
        true);
    expect(tester.takeException(), null);
  });
}
