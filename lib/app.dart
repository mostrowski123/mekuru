import 'package:flutter/material.dart';

import 'features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'features/library/presentation/screens/library_screen.dart';
import 'features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'shared/theme/app_theme.dart';

/// Root application widget.
class MekuruApp extends StatelessWidget {
  const MekuruApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mekuru',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
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
    DictionaryManagerScreen(),
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
