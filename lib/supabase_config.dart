class SupabaseConfig {
  const SupabaseConfig._(this.url, this.publishableKey);

  final String url;
  final String publishableKey;

  static SupabaseConfig? fromEnvironment() {
    return parse(
      const String.fromEnvironment('SUPABASE_URL'),
      const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  static SupabaseConfig? parse(String url, String key) {
    if (url.isEmpty && key.isEmpty) return null; // Offline shell preview.

    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        url.contains('YOUR_PROJECT_REF') ||
        !key.startsWith('sb_publishable_') ||
        key.length <= 'sb_publishable_'.length ||
        key.contains('REPLACE_WITH') ||
        key.trim() != key) {
      throw const FormatException(
        'Set a valid HTTPS Supabase URL and a modern publishable key.',
      );
    }

    return SupabaseConfig._(url, key);
  }
}
