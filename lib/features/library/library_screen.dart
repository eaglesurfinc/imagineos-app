import 'package:flutter/material.dart';
import '../drawing/drawing_studio.dart';
import '../drawing/drawing_drafts.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('A home for your characters',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Text('Your drawings. Your characters. Your stories.'),
        const SizedBox(height: 32),
        const Icon(Icons.palette_outlined, size: 72),
        const SizedBox(height: 16),
        const Text('No characters yet.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: () => openDrawingStudio(context,
                draftKey: DrawingDraftStore.shared.key('offline', 'new')),
            icon: const Icon(Icons.draw),
            label: const Text('Try drawing studio')),
        const Text(
            'Use Save to device for a PNG copy. Parent access enables saving characters to your cloud library.'),
      ],
    );
  }
}
