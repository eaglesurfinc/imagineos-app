import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/main.dart';
import 'package:imagineos/supabase_config.dart';

void main() {
  const url = 'https://fictional-project.supabase.co';
  const key = 'sb_publishable_fictional_adult_test_value';

  test('unconfigured checkout can run the offline shell', () {
    expect(SupabaseConfig.parse('', ''), isNull);
  });

  test('configured client retains the intended URL and publishable key', () {
    final config = SupabaseConfig.parse(url, key)!;
    expect(config.url, url);
    expect(config.publishableKey, key);
  });

  test('partial configuration cannot silently fall back to offline mode', () {
    expect(() => SupabaseConfig.parse(url, ''), throwsFormatException);
    expect(() => SupabaseConfig.parse('', key), throwsFormatException);
  });

  test('server secrets cannot be accepted as client configuration', () {
    for (final secret in ['sb_secret_fictional_secret', 'legacy.jwt.value']) {
      expect(
        () => SupabaseConfig.parse(url, secret),
        throwsA(isA<FormatException>().having(
          (error) => error.toString(),
          'message omits rejected credential',
          isNot(contains(secret)),
        )),
      );
    }
  });

  test('insecure URLs, URL credentials, and sample values are rejected', () {
    for (final invalidUrl in [
      'http://fictional-project.supabase.co',
      'https://adult:password@fictional-project.supabase.co',
      'https://fictional-project.supabase.co/?token=example',
      'https://YOUR_PROJECT_REF.supabase.co',
    ]) {
      expect(
          () => SupabaseConfig.parse(invalidUrl, key), throwsFormatException);
    }
    expect(
      () => SupabaseConfig.parse(
          url, 'sb_publishable_REPLACE_WITH_YOUR_PROJECT_KEY'),
      throwsFormatException,
    );
  });

  testWidgets('startup failure displays a safe message instead of a blank page',
      (tester) async {
    await tester.pumpWidget(const StartupFailureApp());
    expect(
      find.text('This preview could not start. Please try again later.'),
      findsOneWidget,
    );
  });
}
