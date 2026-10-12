import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'supabase_config.dart';

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
    runApp(const ImagineOsApp());
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
