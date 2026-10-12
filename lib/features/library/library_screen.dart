import 'package:flutter/material.dart';

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
      ],
    );
  }
}
