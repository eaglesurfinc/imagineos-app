import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'supabase_config.dart';
import 'features/parent/parent_account.dart';
import 'features/parent/provider_connections.dart';
import 'features/library/character_store.dart';
import 'features/story/illustration_contract.dart';
import 'features/story/story_draft_store.dart';
import 'features/story/story_project_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = SupabaseConfig.fromEnvironment();
    if (config != null) {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
      );
    }
    runApp(ImagineOsApp(
      storyProjects: config == null
          ? null
          : SupabaseStoryProjectStore(Supabase.instance.client),
      storyDrafts: config == null
          ? null
          : SupabaseStoryDraftStore(Supabase.instance.client),
      providers: config == null
          ? null
          : SupabaseProviderConnections(Supabase.instance.client),
      storyGateway: config == null
          ? const DisabledIllustrationGateway()
          : SupabaseIllustrationGateway(Supabase.instance.client),
      characterStore: config == null
          ? null
          : SupabaseCharacterStore(Supabase.instance.client),
      account: config == null
          ? null
          : SupabaseParentAccount(Supabase.instance.client),
    ));
  } catch (_) {
    // Keep configuration values and underlying errors out of the public UI.
    runApp(const StartupFailureApp());
  }
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This preview could not start. Please try again later.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
