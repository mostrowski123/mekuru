import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'features/library/presentation/screens/library_screen.dart';
import 'features/settings/presentation/providers/app_settings_providers.dart';
import 'features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'shared/theme/app_theme.dart';

/// Root application widget.
class MekuruApp extends ConsumerWidget {
  const MekuruApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(appThemeModeProvider.notifier).loadPersistedSettings();
    ref.read(lookupFontSizeProvider.notifier).loadPersistedSettings();
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp(
      title: 'Mekuru',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const _MainShell(),
    );
  }
}

/// Main shell with bottom navigation.
class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _currentIndex = 0;

  static const _screens = <Widget>[
    LibraryScreen(),
    DictionarySearchScreen(),
    VocabularyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Dictionary',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Vocabulary',
          ),
        ],
      ),
    );
  }
}
