import 'package:flutter/material.dart';

class ParentInformationScreen extends StatelessWidget {
  const ParentInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Kids create. AI illustrates.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Text(
          'ImagineOS is being built to help children keep their original '
          'characters and continue their own stories. Their words belong to '
          'them. AI must never rewrite their dialogue.',
        ),
        const SizedBox(height: 24),
        const Text(
          'This early preview does not accept drawings, create accounts, '
          'save work, or generate illustrations yet.',
        ),
      ],
    );
  }
}
