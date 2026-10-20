import 'package:flutter/material.dart';

import 'provider_connections.dart';

class ProviderConnectionsScreen extends StatefulWidget {
  const ProviderConnectionsScreen({super.key, required this.connections});
  final ProviderConnections connections;
  @override
  State<ProviderConnectionsScreen> createState() =>
      _ProviderConnectionsScreenState();
}

class _ProviderConnectionsScreenState extends State<ProviderConnectionsScreen> {
  late Future<List<ProviderOption>> _options = widget.connections.load();

  Future<void> _edit(ProviderOption provider, {bool disconnect = false}) async {
    final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ConnectionDialog(
            connections: widget.connections,
            provider: provider,
            disconnect: disconnect));
    if (changed == true && mounted)
      setState(() {
        _options = widget.connections.load();
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('AI provider accounts')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Connect your own provider account',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text(
            'Eligible subscription allowances and API credits belong to your provider account. Each connection explains what it can use. Children stay the creators; their exact dialogue is never rewritten.'),
        const SizedBox(height: 12),
        const Card(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Live illustration is not enabled yet. Connecting checks API access without generating content or spending AI credits. A verified key does not establish your balance or image-model permissions.'))),
        const SizedBox(height: 12),
        FutureBuilder<List<ProviderOption>>(
            future: _options,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Could not load provider connections.'),
                      TextButton(
                          onPressed: () => setState(() {
                                _options = widget.connections.load();
                              }),
                          child: const Text('Retry')),
                    ]);
              }
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              return Column(children: [
                for (final p in snapshot.data!)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8),
                                Text(p.connected
                                    ? 'API connection verified'
                                    : 'Not connected'),
                                Text(p.imageGeneration
                                    ? 'Image generation provider'
                                    : 'Image analysis only; illustration generation unavailable'),
                                const SizedBox(height: 8),
                                Text(p.billing),
                                const SizedBox(height: 8),
                                Text(p.subscription),
                                const SizedBox(height: 8),
                                const Text(
                                    'Provider login is not available for this connection. Use a provider-issued API key.'),
                                const SizedBox(height: 12),
                                Wrap(spacing: 12, runSpacing: 8, children: [
                                  FilledButton(
                                      onPressed: () => _edit(p),
                                      child: Text(p.connected
                                          ? 'Replace API key'
                                          : 'Connect API key')),
                                  if (p.connected)
                                    OutlinedButton(
                                        onPressed: () =>
                                            _edit(p, disconnect: true),
                                        child: const Text('Disconnect')),
                                ]),
                              ]))),
              ]);
            }),
      ])));
}

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog(
      {required this.connections,
      required this.provider,
      required this.disconnect});
  final ProviderConnections connections;
  final ProviderOption provider;
  final bool disconnect;
  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController(), _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _key.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Clear the form immediately; neither secret is written to device drafts.
    final key = _key.text.trim(), password = _password.text;
    _key.clear();
    _password.clear();
    try {
      if (widget.disconnect) {
        await widget.connections.disconnect(widget.provider.id, password);
      } else {
        await widget.connections.connect(widget.provider.id, key, password);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() => _error = error is ProviderConnectionException
            ? error.message
            : 'Could not update this connection. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          scrollable: true,
          title: Text(
              '${widget.disconnect ? 'Disconnect' : 'Connect'} ${widget.provider.name}'),
          content: SizedBox(
              width: 440,
              child: Form(
                  key: _form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.disconnect
                            ? 'Remove this connection from ImagineOS. You can also revoke the API key in your provider account.'
                            : '${widget.provider.billing} Your API key is encrypted on the server and is never returned to the app.'),
                        if (!widget.disconnect) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: _key,
                              enabled: !_busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                  labelText: 'Provider API key'),
                              validator: (value) =>
                                  (value?.trim().length ?? 0) >= 16
                                      ? null
                                      : 'Enter your provider API key.'),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                                labelText: 'ImagineOS parent password'),
                            validator: (value) => (value?.isNotEmpty ?? false)
                                ? null
                                : 'Confirm your parent password.',
                            onFieldSubmitted: (_) {
                              if (!_busy) _submit();
                            }),
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                  liveRegion: true, child: Text(_error!))),
                      ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(
                    widget.disconnect ? 'Disconnect' : 'Verify and connect')),
          ]));
}
