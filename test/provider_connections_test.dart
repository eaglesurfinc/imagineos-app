import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/features/parent/provider_connections.dart';
import 'package:imagineos/features/parent/provider_connections_screen.dart';
import 'package:imagineos/theme.dart';

class FakeProviders implements ProviderConnections {
  bool connected = false, fail = false;
  int mutations = 0;
  String? lastKey, lastPassword;
  @override
  Future<List<ProviderOption>> load() async => [
        ProviderOption(
            id: 'openai',
            name: 'OpenAI',
            imageGeneration: true,
            subscription: 'Plan image usage unavailable.',
            billing: 'Parent API credits.',
            connected: connected),
        const ProviderOption(
            id: 'claude',
            name: 'Claude',
            imageGeneration: false,
            subscription: 'Subscription integration pending.',
            billing: 'Parent API credits.'),
        const ProviderOption(
            id: 'gemini',
            name: 'Gemini',
            imageGeneration: true,
            subscription: 'Eligible API project quota.',
            billing: 'Parent API credits.'),
      ];
  @override
  Future<void> connect(String provider, String key, String password) async {
    mutations++;
    lastKey = key;
    lastPassword = password;
    if (fail)
      throw const ProviderConnectionException('Check your parent password.');
    connected = true;
  }

  @override
  Future<void> disconnect(String provider, String password) async {
    mutations++;
    lastPassword = password;
    connected = false;
  }
}

void main() {
  Future<void> show(WidgetTester tester, FakeProviders store) async {
    await tester.pumpWidget(MaterialApp(
        theme: imagineOsTheme(),
        home: ProviderConnectionsScreen(connections: store)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'connect verifies, clears secrets, refreshes status and disconnect requires password',
      (tester) async {
    final store = FakeProviders();
    await show(tester, store);
    await tester.ensureVisible(find.text('Connect API key').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect API key').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(store.mutations, 0);
    await tester.enterText(
        find.byType(TextFormField).at(0), 'sk-fictional-not-a-real-key');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'fictional-parent-password');
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(store.lastKey, 'sk-fictional-not-a-real-key');
    expect(store.lastPassword, 'fictional-parent-password');
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('API connection verified'), findsOneWidget);
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField), 'fictional-parent-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(store.connected, false);
    expect(store.mutations, 2);
  });
  testWidgets(
      'failed connection clears both secret fields and cancel preserves the existing connection',
      (tester) async {
    final store = FakeProviders()..fail = true;
    await show(tester, store);
    await tester.ensureVisible(find.text('Connect API key').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect API key').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'sk-fictional-not-a-real-key');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'fictional-password');
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(find.text('Check your parent password.'), findsOneWidget);
    for (final field
        in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      expect(field.controller!.text, isEmpty);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.connected, false);
  });
  testWidgets(
      'provider capabilities reflow on a phone at 2x text without fake login',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: imagineOsTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: ProviderConnectionsScreen(connections: FakeProviders())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Gemini'), 400);
    expect(
        find.text('Image analysis only; illustration generation unavailable'),
        findsOneWidget);
    expect(find.text('Sign in with Claude'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
