import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/platform/device_memory.dart';
import 'core/services/analytics_service.dart';
import 'core/services/background_work.dart';
import 'core/services/usage_telemetry.dart';
import 'features/ankidroid/presentation/providers/ankidroid_providers.dart';
import 'features/backup/data/services/staged_full_restore.dart';
import 'features/backup/presentation/providers/backup_providers.dart';
import 'features/backup/presentation/providers/full_backup_job_provider.dart';
import 'features/backup/presentation/screens/full_backup_job_screen.dart';
import 'features/dictionary/presentation/screens/dictionary_search_screen.dart';
import 'features/library/data/repositories/book_repository.dart';
import 'features/library/presentation/providers/library_providers.dart';
import 'features/library/presentation/screens/library_screen.dart';
import 'features/manga/data/services/ocr_billing_client.dart';
import 'features/manga/data/services/ocr_store_service.dart';
import 'features/manga/presentation/providers/pro_access_provider.dart';
import 'features/reader/data/services/gemma_translation.dart';
import 'features/reader/presentation/providers/gemma_download_provider.dart';
import 'features/reader/presentation/providers/reader_providers.dart';
import 'features/settings/data/services/app_settings_storage.dart';
import 'features/settings/presentation/providers/app_settings_providers.dart';
import 'features/sync/presentation/providers/sync_providers.dart';
import 'features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'features/wanikani/presentation/providers/wanikani_providers.dart';
import 'features/you/presentation/screens/you_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'main.dart'
    show appL10n, navigatorKey, scaffoldMessengerKey, databaseProvider;
import 'shared/theme/app_theme.dart';
import 'shared/utils/app_routes.dart';
import 'shared/widgets/glass_tab_bar.dart';

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
    BackgroundWork.instance.text = _backgroundWorkText;
    _bootstrapAppState();
  }

  /// iOS Live Activity text for downloads and scans running in the
  /// background, in the app's language.
  static ({String title, String subtitle}) _backgroundWorkText({
    required int downloads,
    required int scans,
    required int dictionaries,
    required int percent,
  }) {
    final l10n = appL10n();
    return (
      title: [
        if (downloads > 0) l10n.backgroundWorkDownloading(count: downloads),
        if (scans > 0) l10n.backgroundWorkScanning(count: scans),
        if (dictionaries > 0)
          l10n.backgroundWorkDictionaries(count: dictionaries),
      ].join(' · '),
      subtitle: l10n.backgroundWorkPercent(percent: percent),
    );
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
      ref
          .read(sentenceTranslationModeProvider.notifier)
          .loadPersistedSettings(),
    );
    unawaited(
      ref.read(translationModelProvider.notifier).loadPersistedSettings(),
    );
    unawaited(
      ref.read(autoFocusSearchProvider.notifier).loadPersistedSettings(),
    );
    unawaited(
      ref.read(autoCropWhiteThresholdProvider.notifier).loadPersistedSettings(),
    );
    unawaited(ref.read(ocrServerUrlProvider.notifier).loadPersistedSettings());
    unawaited(
      ref
          .read(ocrServerAllowSelfSignedProvider.notifier)
          .loadPersistedSettings(),
    );
    unawaited(
      ref.read(readerSettingsProvider.notifier).loadPersistedSettings(),
    );
    unawaited(
      ref
          .read(enhancedFuriganaDictEnabledProvider.notifier)
          .loadPersistedSettings(),
    );
    unawaited(ref.read(wanikaniProvider.notifier).loadPersistedSettings());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Backups can do meaningful file I/O, so let the first frame land first.
      ref.read(autoBackupCheckerProvider);
      unawaited(_announceFullRestoreResult());
      unawaited(ref.read(bookRepositoryProvider).sweepOrphanImportDirs());
      unawaited(
        ref
            .read(serverDownloadProvider.notifier)
            .resumeBackgroundDownloads()
            .catchError(
              (Object e, StackTrace st) =>
                  logFailure('sync.downloads_resumed', e, stackTrace: st),
            ),
      );
      unawaited(ref.read(proUnlockedProvider.notifier).refreshIfDue());
      // A Gemma download job outlives the app: the notifier takes one that
      // finished while Mekuru was closed (choosing High) and follows one
      // still running.
      if (GemmaTranslation.supported) ref.read(gemmaDownloadProvider);
      // Silent WaniKani refresh; failures stay in telemetry and never
      // reach the user.
      unawaited(
        ref.read(wanikaniProvider.notifier).refreshIfDue(trigger: 'startup'),
      );
      unawaited(
        emitInstallGauges(
          ref.read(databaseProvider),
          isPro: PreloadedProEntitlement.isInitiallyUnlocked,
        ),
      );
      unawaited(reportMemoryAtLaunch());
    });
  }

  /// First launch after a full restore: tell the user how it went and
  /// re-check Pro with Google Play (the entitlement never travels).
  Future<void> _announceFullRestoreResult() async {
    final result = await consumeFullRestoreResult();
    if (result == null || !mounted) return;
    final messenger = scaffoldMessengerKey.currentState;
    final messengerContext = scaffoldMessengerKey.currentContext;
    if (messenger == null ||
        messengerContext == null ||
        !messengerContext.mounted) {
      return;
    }
    final l10n = AppLocalizations.of(messengerContext);

    if (result == StagedFullRestore.resultOk) {
      logUsage('backup.full_restore_applied');
      unawaited(_restorePurchasesAfterFullRestore());
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupFullRestoreComplete)),
      );
    } else {
      final code = result.replaceFirst(StagedFullRestore.resultErrorPrefix, '');
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.backupFullRestoreBootFailed(details: code)),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _restorePurchasesAfterFullRestore() async {
    try {
      await OcrStoreService.instance.restorePurchasesUnprompted();
      if (mounted) ref.invalidate(proUnlockedProvider);
    } catch (e) {
      debugPrint('[Backup] Purchase restoration after full restore failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(proUnlockedProvider.notifier).refreshIfDue());
      unawaited(
        ref.read(wanikaniProvider.notifier).refreshIfDue(trigger: 'resume'),
      );
      // A full backup may have finished (or paused) while the app was away.
      unawaited(ref.read(fullBackupJobProvider.notifier).refresh());
    }
  }

  /// The job page sits above the Navigator, so Back must be swallowed here
  /// rather than by a PopScope: nothing underneath may be reached while a
  /// full backup or restore is in flight.
  @override
  Future<bool> didPopRoute() async {
    if (ref.read(fullBackupJobProvider).blocksApp) return true;
    return super.didPopRoute();
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
      // Brings an open book back after the system kills the app in the
      // background (state restoration; see openBookReader).
      restorationScopeId: 'app',
      onGenerateRoute: onGenerateAppRoute,
      navigatorObservers: [
        SentryNavigatorObserver(),
        ?AnalyticsService.instance.navigatorObserver,
      ],
      // Covers every route and dialog while a full backup or restore runs.
      builder: (context, child) =>
          FullBackupJobGate(child: child ?? const SizedBox.shrink()),
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
  static const _tabNames = ['library', 'dictionary', 'vocabulary', 'stats'];

  int _currentIndex = 0;
  bool _hasAppliedStartup = false;
  final _dictionaryKey = GlobalKey<DictionarySearchScreenState>();
  final Map<int, Widget> _loadedScreens = <int, Widget>{};

  @override
  void initState() {
    super.initState();
    // A route above the shell from the start is a reader the navigator
    // restored after the system killed the app. The startup screen is for
    // fresh launches, and must not wait to apply until that reader closes.
    _hasAppliedStartup = Navigator.of(context).canPop();
  }

  Widget _buildScreen(int index) {
    return switch (index) {
      0 => const LibraryScreen(),
      1 => DictionarySearchScreen(key: _dictionaryKey),
      2 => const VocabularyScreen(),
      3 => const YouScreen(),
      _ => throw ArgumentError.value(index, 'index', 'Unknown main screen'),
    };
  }

  void _ensureScreenLoaded(int index) {
    _loadedScreens.putIfAbsent(index, () => _buildScreen(index));
  }

  List<Widget> _indexedScreens() {
    return List<Widget>.generate(
      _tabNames.length,
      (index) => _loadedScreens[index] ?? const SizedBox.shrink(),
      growable: false,
    );
  }

  void _setCurrentIndex(int index) {
    if (_currentIndex == 1 && index != 1) {
      _dictionaryKey.currentState?.commitHistoryIfNeeded();
    }
    if (_currentIndex == 3 && index != 3) {
      // The You hub watches the unwindowed session stream for its this-week
      // subtitle and re-aggregates on every write, and the IndexedStack would
      // keep a hidden child doing that forever. Evicting it closes the
      // subscription, and the fresh mount on return counts "this week" from
      // today rather than from the last write.
      _loadedScreens.remove(3);
    }
    _hasAppliedStartup = true;
    setState(() => _currentIndex = index);
    // The tabs are an IndexedStack, not routes, so the navigator observers
    // never see them; this is the only screen-usage signal for the tabs.
    logUsage('screen.tab_selected', attrs: {'tab': _tabNames[index]});
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
      // The glass bar floats over the tabs, which scroll under it.
      extendBody: usesGlassTabBar,
      bottomNavigationBar: usesGlassTabBar
          ? _buildGlassTabBar(l10n)
          : NavigationBar(
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
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: l10n.navYou,
                ),
              ],
            ),
    );
  }

  Widget _buildGlassTabBar(AppLocalizations l10n) {
    return GlassTabBar.bottom(
      selectedIndex: _currentIndex,
      onTabSelected: _setCurrentIndex,
      tabs: [
        GlassTab(
          icon: const Icon(Icons.auto_stories_outlined),
          activeIcon: const Icon(Icons.auto_stories),
          label: l10n.navLibrary,
        ),
        GlassTab(
          icon: const Icon(Icons.book_outlined),
          activeIcon: const Icon(Icons.book),
          label: l10n.navDictionary,
        ),
        GlassTab(
          icon: const Icon(Icons.bookmark_border),
          activeIcon: const Icon(Icons.bookmark),
          label: l10n.navVocabulary,
        ),
        GlassTab(
          icon: const Icon(Icons.person_outline),
          activeIcon: const Icon(Icons.person),
          label: l10n.navYou,
        ),
      ],
    );
  }

  Future<void> _openLastReadBook() async {
    final repo = BookRepository(ref.read(databaseProvider));
    final book = await repo.getMostRecentlyReadBook();
    if (book != null && mounted) {
      // Any book type can be the most recent one.
      openBookReader(Navigator.of(context), book);
    }
  }
}
