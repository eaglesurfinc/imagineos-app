import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'story_project.dart';

class StoryProjectPreview extends StatelessWidget {
  const StoryProjectPreview(
      {super.key,
      required this.story,
      required this.images,
      this.includeSceneNotes = false});
  final StoryProject story;
  final Map<String, Uint8List> images;
  final bool includeSceneNotes;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (story.title.isNotEmpty)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(story.title,
                  style: Theme.of(context).textTheme.headlineMedium)),
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'Original-artwork draft. Your drawings and exact words; AI illustration is not enabled yet.')),
        if (story.panels.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Add a page or panel when you are ready.')),
        for (var start = 0;
            start < story.panels.length;
            start += story.format.perSheet)
          Card(
              color: Colors.white,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final count = story.format == StoryFormat.illustrated ||
                            constraints.maxWidth < 500
                        ? 1
                        : story.format == StoryFormat.strip
                            ? 3
                            : 2;
                    final end = (start + story.format.perSheet)
                        .clamp(0, story.panels.length);
                    return Wrap(spacing: 16, runSpacing: 16, children: [
                      for (var index = start; index < end; index++)
                        SizedBox(
                            width: (constraints.maxWidth - (count - 1) * 16) /
                                count,
                            child: _PanelPreview(
                                panel: story.panels[index],
                                image: images[
                                    story.panels[index].reference.assetId],
                                number: index + 1,
                                comic: story.format != StoryFormat.illustrated,
                                includeSceneNotes: includeSceneNotes))
                    ]);
                  }))),
      ]);
}

class _PanelPreview extends StatelessWidget {
  const _PanelPreview(
      {required this.panel,
      required this.image,
      required this.number,
      required this.comic,
      required this.includeSceneNotes});
  final StoryPanel panel;
  final Uint8List? image;
  final int number;
  final bool comic, includeSceneNotes;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '${comic ? 'Panel' : 'Page'} $number',
      container: true,
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              border: comic
                  ? Border.all(
                      color: Theme.of(context).colorScheme.outline, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (image != null && panel.sourceAvailable)
              Image.memory(image!,
                  height: 260,
                  fit: BoxFit.contain,
                  semanticLabel:
                      '${panel.characterName}, saved original drawing')
            else
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Drawing unavailable. Your scene and words are kept.')),
            if (includeSceneNotes && panel.scene.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(panel.scene,
                      style: const TextStyle(fontStyle: FontStyle.italic))),
            if (panel.dialogue.isNotEmpty)
              Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(panel.dialogue)),
            if (panel.narration.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(panel.narration)),
          ])));
}
