import 'package:supabase_flutter/supabase_flutter.dart';

class ProviderOption {
  const ProviderOption(
      {required this.id,
      required this.name,
      required this.imageGeneration,
      required this.subscription,
      required this.billing,
      this.connected = false});
  final String id, name, subscription, billing;
  final bool imageGeneration, connected;
}

abstract class ProviderConnections {
  Future<List<ProviderOption>> load();
  Future<void> connect(String provider, String key, String password);
  Future<void> disconnect(String provider, String password);
}

class ProviderConnectionException implements Exception {
  const ProviderConnectionException(this.message);
  final String message;
}

class SupabaseProviderConnections implements ProviderConnections {
  const SupabaseProviderConnections(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final identity = client.auth.currentUser?.id;
    if (identity == null) {
      throw const ProviderConnectionException(
          'Sign in to your parent account first.');
    }
    try {
      final result =
          await client.functions.invoke('parent-providers', body: body);
      if (identity != client.auth.currentUser?.id)
        throw StateError('Session changed');
      final data = result.data;
      if (data is! Map<String, dynamic> ||
          data['contract_version'] != 1 ||
          data['code'] != 'OK') {
        throw StateError('Unexpected connection response');
      }
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      throw ProviderConnectionException(switch (code) {
        'PARENT_CONFIRMATION_REQUIRED' =>
          'Check your ImagineOS parent password and try again.',
        'PROVIDER_CREDENTIAL_REJECTED' =>
          'The provider could not verify that API key. Check the key and its permissions.',
        'TOO_MANY_ATTEMPTS' =>
          'Too many connection attempts. Please try again in an hour.',
        'AUTH_REQUIRED' => 'Your session has ended. Sign in again.',
        _ =>
          'Could not confirm this update. Reload provider settings to check the connection before retrying.',
      });
    } catch (_) {
      throw const ProviderConnectionException(
          'Could not reach your provider settings. Please try again.');
    }
  }

  @override
  Future<List<ProviderOption>> load() async {
    final response = await _call({'action': 'list'});
    final data = response['data'] as Map;
    // Live generation cannot be enabled by a connection-management response.
    if (data['generation_enabled'] != false)
      throw const FormatException('Unsupported settings');
    final connected = (data['connections'] as List)
        .map((value) => (value as Map)['provider'])
        .toSet();
    return (data['providers'] as List).map((value) {
      final p = value as Map;
      if (p['connection'] != 'api_key' ||
          p['login_available'] != false ||
          !const {'openai', 'claude', 'gemini'}.contains(p['id'])) {
        throw const FormatException('Unsupported provider connection');
      }
      return ProviderOption(
          id: p['id'] as String,
          name: p['name'] as String,
          imageGeneration: p['image_generation'] as bool,
          subscription: p['subscription'] as String,
          billing: p['billing'] as String,
          connected: connected.contains(p['id']));
    }).toList(growable: false);
  }

  @override
  Future<void> connect(String provider, String key, String password) async {
    await _call({
      'action': 'connect',
      'provider': provider,
      'api_key': key,
      'password': password
    });
  }

  @override
  Future<void> disconnect(String provider, String password) async {
    await _call(
        {'action': 'disconnect', 'provider': provider, 'password': password});
  }
}
