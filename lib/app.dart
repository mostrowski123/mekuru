import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'features/backup/presentation/providers/backup_providers.dart';
import 'features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'features/library/data/repositories/book_repository.dart';
import 'features/library/presentation/screens/library_screen.dart';
import 'features/manga/presentation/providers/pro_access_provider.dart';
import 'features/reader/presentation/providers/reader_providers.dart';
import 'features/reader/presentation/screens/reader_screen.dart';
import 'features/settings/data/services/app_settings_storage.dart';
import 'features/settings/presentation/providers/app_settings_providers.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'main.dart' show navigatorKey, scaffoldMessengerKey, databaseProvider;
import 'shared/theme/app_theme.dart';

/// Root application widget.
class MekuruApp extends ConsumerStatefulWidget {
  const MekuruApp({super.key});

  @override
  ConsumerState<MekuruApp> createState() => _MekuruAppState();
}

class _MekuruAppState extends ConsumerState<MekuruApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapAppState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _bootstrapAppState() {
    unawaited(ref.read(appLanguageProvider.notifier).loadPersistedSettings());
    unawaited(ref.read(appThemeModeProvider.notifier).loadPersistedSettings());
    unawaited(ref.read(appColorThemeProvider.notifier).loadPersistedSettings());
    unawaited(
      ref.read(lookupFontSizeProvider.notifier).loadPersistedSettings(),
    );
    unawaited(ref.read(searchHistoryProvider.notifier).loadPersistedSettings());
    unawaited(
      ref.read(filterRomanLettersProvider.notifier).loadPersistedSettings(),
    );
    unawaited(
      ref.read(ankidroidConfigProvider.notifier).loadPersistedSettings(),
    );
    unawaited(ref.read(startupScreenProvider.notifier).loadPersistedSettings());
    unawaited(
      ref.read(autoFocusSearchProvider.notifier).loadPersistedSettings(),
    );
    unawaited(
      ref.read(autoCropWhiteThresholdProvider.notifier).loadPersistedSettings(),
    );
    unawaited(ref.read(ocrServerUrlProvider.notifier).loadPersistedSettings());
    unawaited(
      ref.read(readerSettingsProvider.notifier).loadPersistedSettings(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Backups can do meaningful file I/O, so let the first frame land first.
      ref.read(autoBackupCheckerProvider);
      unawaited(ref.read(proUnlockedProvider.notifier).refreshIfDue());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(proUnlockedProvider.notifier).refreshIfDue());
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLanguage = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final colorTheme = ref.watch(appColorThemeProvider);

    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(colorTheme.seedColor),
      darkTheme: AppTheme.darkTheme(colorTheme.seedColor),
      themeMode: themeMode,
      locale: appLanguageLocaleOverride(appLanguage),
      localeResolutionCallback: resolveSupportedAppLocale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
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
  static const _screenCount = 4;

  int _currentIndex = 0;
  bool _hasAppliedStartup = false;
  final _dictionaryKey = GlobalKey<DictionarySearchScreenState>();
  final Map<int, Widget> _loadedScreens = <int, Widget>{};

  Widget _buildScreen(int index) {
    return switch (index) {
      0 => const LibraryScreen(),
      1 => DictionarySearchScreen(key: _dictionaryKey),
      2 => const VocabularyScreen(),
      3 => const SettingsScreen(),
      _ => throw ArgumentError.value(index, 'index', 'Unknown main screen'),
    };
  }

  void _ensureScreenLoaded(int index) {
    _loadedScreens.putIfAbsent(index, () => _buildScreen(index));
  }

  List<Widget> _indexedScreens() {
    return List<Widget>.generate(
      _screenCount,
      (index) => _loadedScreens[index] ?? const SizedBox.shrink(),
      growable: false,
    );
  }

  void _setCurrentIndex(int index) {
    _hasAppliedStartup = true;
    setState(() => _currentIndex = index);
    if (index == 1) {
      _focusDictionarySearchIfNeeded();
    }
  }

  void _focusDictionarySearchIfNeeded() {
    if (!ref.read(autoFocusSearchProvider)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dictionaryKey.currentState?.requestSearchFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
          _focusDictionarySearchIfNeeded();
        case StartupScreen.lastRead:
          _currentIndex = 0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _openLastReadBook();
          });
      }
    }

    _ensureScreenLoaded(_currentIndex);

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _indexedScreens()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          _setCurrentIndex(index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.auto_stories_outlined),
            selectedIcon: const Icon(Icons.auto_stories),
            label: l10n.navLibrary,
          ),
          NavigationDestination(
            icon: const Icon(Icons.book_outlined),
            selectedIcon: const Icon(Icons.book),
            label: l10n.navDictionary,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_border),
            selectedIcon: const Icon(Icons.bookmark),
            label: l10n.navVocabulary,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
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
