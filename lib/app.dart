import 'package:flutter/material.dart';

import 'features/library/library_screen.dart';
import 'features/parent/parent_information_screen.dart';
import 'features/parent/parent_access_screen.dart';
import 'features/parent/parent_account.dart';

class ImagineOsApp extends StatelessWidget {
  const ImagineOsApp({super.key, this.account});
  final ParentAccount? account;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ImagineOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6554A4)),
      ),
      home: _StudioShell(account: account),
    );
  }
}

class _StudioShell extends StatefulWidget {
  const _StudioShell({this.account});
  final ParentAccount? account;

  @override
  State<_StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<_StudioShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.account?.addListener(_onAccountChanged);
    if (widget.account?.recoveringPassword ?? false) _selectedIndex = 1;
  }

  void _onAccountChanged() {
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
            const LibraryScreen(),
            if (widget.account != null)
              ParentAccessScreen(account: widget.account!)
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
