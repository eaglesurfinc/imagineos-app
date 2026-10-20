import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

import 'features/drawing/drawing_drafts.dart';
import 'features/story/illustration_contract.dart';
import 'features/story/story_draft_store.dart';

import 'features/library/library_screen.dart';
import 'features/library/character_store.dart';
import 'features/library/character_library_screen.dart';
import 'features/parent/parent_information_screen.dart';
import 'features/parent/parent_access_screen.dart';
import 'features/parent/parent_account.dart';
import 'features/parent/provider_connections.dart';

class ImagineOsApp extends StatelessWidget {
  const ImagineOsApp(
      {super.key,
      this.account,
      this.characterStore,
      this.providers,
      this.storyDrafts,
      this.storyGateway = const DisabledIllustrationGateway()});
  final ParentAccount? account;
  final CharacterStore? characterStore;
  final ProviderConnections? providers;
  final StoryDraftStore? storyDrafts;
  final IllustrationGateway storyGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ImagineOS',
      debugShowCheckedModeBanner: false,
      theme: imagineOsTheme(),
      home: _StudioShell(
          account: account,
          providers: providers,
          storyDrafts: storyDrafts,
          characterStore: characterStore,
          storyGateway: storyGateway),
    );
  }
}

class _StudioShell extends StatefulWidget {
  const _StudioShell(
      {this.account,
      this.characterStore,
      this.providers,
      this.storyDrafts,
      required this.storyGateway});
  final ParentAccount? account;
  final CharacterStore? characterStore;
  final ProviderConnections? providers;
  final StoryDraftStore? storyDrafts;
  final IllustrationGateway storyGateway;

  @override
  State<_StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<_StudioShell> {
  int _selectedIndex = 0;
  String? _sessionEmail;

  @override
  void initState() {
    super.initState();
    _sessionEmail = widget.account?.email;
    widget.account?.addListener(_onAccountChanged);
    if (widget.account?.recoveringPassword ?? false) _selectedIndex = 1;
  }

  void _onAccountChanged() {
    if (mounted && _sessionEmail != widget.account?.email) {
      unawaited(
          DrawingDraftStore.shared.invalidate().catchError((Object _) {}));
      Navigator.of(context).popUntil((route) => route.isFirst);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      setState(() => _sessionEmail = widget.account?.email);
    }
    if (mounted && (widget.account?.recoveringPassword ?? false)) {
      setState(() => _selectedIndex = 1);
    }
  }

  @override
  void dispose() {
    widget.account?.removeListener(_onAccountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ImagineOS')),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            if (widget.characterStore != null)
              CharacterLibraryScreen(
                  key: ValueKey(_sessionEmail),
                  store: widget.characterStore!,
                  storyGateway: widget.storyGateway,
                  storyDrafts: widget.storyDrafts,
                  draftScope: _sessionEmail ?? 'signed-out',
                  signedIn: _sessionEmail != null)
            else
              const LibraryScreen(),
            if (widget.account != null)
              ParentAccessScreen(
                  account: widget.account!, providers: widget.providers)
            else
              const ParentInformationScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'My characters',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom),
            label: 'For parents',
          ),
        ],
      ),
    );
  }
}
