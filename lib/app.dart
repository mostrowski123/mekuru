import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'features/library/data/repositories/book_repository.dart';
import 'features/library/presentation/screens/library_screen.dart';
import 'features/reader/presentation/providers/reader_providers.dart';
import 'features/reader/presentation/screens/reader_screen.dart';
import 'features/settings/presentation/providers/app_settings_providers.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'main.dart' show navigatorKey, scaffoldMessengerKey, databaseProvider;
import 'shared/theme/app_theme.dart';

/// Root application widget.
class MekuruApp extends ConsumerWidget {
  const MekuruApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(appThemeModeProvider.notifier).loadPersistedSettings();
    ref.read(appColorThemeProvider.notifier).loadPersistedSettings();
    ref.read(lookupFontSizeProvider.notifier).loadPersistedSettings();
    ref.read(searchHistoryProvider.notifier).loadPersistedSettings();
    ref.read(filterRomanLettersProvider.notifier).loadPersistedSettings();
    ref.read(ankidroidConfigProvider.notifier).loadPersistedSettings();
    ref.read(startupScreenProvider.notifier).loadPersistedSettings();
    ref.read(autoFocusSearchProvider.notifier).loadPersistedSettings();
    ref.read(readerSettingsProvider.notifier).loadPersistedSettings();
    final themeMode = ref.watch(appThemeModeProvider);
    final colorTheme = ref.watch(appColorThemeProvider);

    return MaterialApp(
      title: 'Mekuru',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(colorTheme.seedColor),
      darkTheme: AppTheme.darkTheme(colorTheme.seedColor),
      themeMode: themeMode,
      scaffoldMessengerKey: scaffoldMessengerKey,
      navigatorKey: navigatorKey,
      navigatorObservers: [SentryNavigatorObserver()],
      home: const _MainShell(),
    );
  }
}

/// Main shell with bottom navigation.
class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int _currentIndex = 0;
  bool _hasAppliedStartup = false;
  final _dictionaryKey = GlobalKey<DictionarySearchScreenState>();

  late final List<Widget> _screens = <Widget>[
    const LibraryScreen(),
    DictionarySearchScreen(key: _dictionaryKey),
    const VocabularyScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Apply startup screen once after the provider has finished loading
    // the persisted value from SharedPreferences.
    final startupScreen = ref.watch(startupScreenProvider);
    final notifier = ref.read(startupScreenProvider.notifier);
    if (!_hasAppliedStartup && notifier.hasLoaded) {
      _hasAppliedStartup = true;
      switch (startupScreen) {
        case StartupScreen.library:
          _currentIndex = 0;
        case StartupScreen.dictionary:
          _currentIndex = 1;
          if (ref.read(autoFocusSearchProvider)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _dictionaryKey.currentState?.requestSearchFocus();
            });
          }
        case StartupScreen.lastRead:
          _currentIndex = 0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _openLastReadBook();
          });
      }
    }

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          _hasAppliedStartup = true;
          setState(() => _currentIndex = index);
          if (index == 1 && ref.read(autoFocusSearchProvider)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _dictionaryKey.currentState?.requestSearchFocus();
            });
          }
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
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Vocabulary',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _openLastReadBook() async {
    final repo = BookRepository(ref.read(databaseProvider));
    final book = await repo.getMostRecentlyReadBook();
    if (book != null && mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
    }
  }
}
