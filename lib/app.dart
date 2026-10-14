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
import 'features/manga/data/services/ocr_billing_client.dart';
import 'features/manga/data/services/ocr_store_service.dart';
import 'features/manga/presentation/providers/pro_access_provider.dart';
import 'features/reader/data/services/gemma_translation.dart';
import 'features/reader/presentation/providers/gemma_download_provider.dart';
import 'features/reader/presentation/providers/reader_providers.dart';
import 'features/settings/data/models/home_tab_layout.dart';
import 'features/settings/data/services/app_settings_storage.dart';
import 'features/settings/presentation/providers/app_settings_providers.dart';
import 'features/settings/presentation/widgets/home_tab_ui.dart';
import 'features/sync/presentation/providers/sync_providers.dart';
import 'features/wanikani/presentation/providers/wanikani_providers.dart';
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
    // Cap Flutter's image cache to reduce memory pressure on low-end devices.
    // Defaults are 1000 images / 100 MB which is excessive for a manga reader
    // where each decoded page can be several MB. Low RAM mode lowers it
    // further, at once when it is turned on.
    ref.listenManual(lowRamModeProvider, fireImmediately: true, (_, lowRam) {
      PaintingBinding.instance.imageCache
        ..maximumSizeBytes = (lowRam ? 20 : 50) * 1024 * 1024
        ..maximumSize = 50;
    });
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
    unawaited(ref.read(pureBlackProvider.notifier).loadPersistedSettings());
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
    unawaited(ref.read(homeTabsProvider.notifier).loadPersistedSettings());
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
    unawaited(ref.read(lowRamModeProvider.notifier).loadPersistedSettings());
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
          tabs: [
            for (final tab in ref.read(homeTabsProvider).visible) tab.name,
          ],
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
    final pureBlack = ref.watch(pureBlackProvider);
    final lowRamMode = ref.watch(lowRamModeProvider);
    // Low RAM mode: no ink ripples, and Android pages change at once.
    ThemeData applyLowRamMode(ThemeData theme) => lowRamMode
        ? theme.copyWith(
            splashFactory: NoSplash.splashFactory,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {TargetPlatform.android: _InstantPageTransitions()},
            ),
          )
        : theme;

    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: applyLowRamMode(AppTheme.lightTheme(colorTheme.seedColor)),
      darkTheme: applyLowRamMode(
        AppTheme.darkTheme(colorTheme.seedColor, pureBlack: pureBlack),
      ),
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
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        // Low RAM mode stills what follows the system's reduce motion
        // setting: the cover tilt, manga page turns, the stats charts.
        // Always wrapped, so turning it on keeps the navigator's state.
        return MediaQuery(
          data: mediaQuery.copyWith(
            disableAnimations: mediaQuery.disableAnimations || lowRamMode,
          ),
          // Covers every route and dialog while a full backup or restore
          // runs.
          child: FullBackupJobGate(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const _MainShell(),
    );
  }
}

/// Low RAM mode's Android page transition: none, and no frames spent on it.
class _InstantPageTransitions extends PageTransitionsBuilder {
  const _InstantPageTransitions();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// Main shell with bottom navigation.
class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  /// Tabs dropped when the user leaves them, as their screens are when
  /// pushed. The You hub (for its this-week subtitle) and Stats watch the
  /// unwindowed session stream and re-aggregate on every write, and the
  /// IndexedStack would keep a hidden child doing that forever; evicting
  /// one closes the subscription, and the fresh mount on return counts
  /// "this week" from today rather than from the last write. Free books
  /// holds the Aozora catalog (about 8 MB), freed only when it closes.
  static const _evictedOnLeave = {
    HomeTab.you,
    HomeTab.stats,
    HomeTab.freeBooks,
  };

  HomeTab _currentTab = HomeTab.library;
  bool _hasAppliedStartup = false;
  final _dictionaryKey = GlobalKey<DictionarySearchScreenState>();
  final Map<HomeTab, Widget> _loadedScreens = <HomeTab, Widget>{};

  @override
  void initState() {
    super.initState();
    // A route above the shell from the start is a reader the navigator
    // restored after the system killed the app. The startup screen is for
    // fresh launches, and must not wait to apply until that reader closes.
    _hasAppliedStartup = Navigator.of(context).canPop();
  }

  Widget _buildScreen(HomeTab tab) =>
      tab.page(key: tab == HomeTab.dictionary ? _dictionaryKey : null);

  void _selectTab(HomeTab tab) {
    if (_currentTab == HomeTab.dictionary && tab != HomeTab.dictionary) {
      _dictionaryKey.currentState?.commitHistoryIfNeeded();
    }
    if (_currentTab != tab && _evictedOnLeave.contains(_currentTab)) {
      _loadedScreens.remove(_currentTab);
    }
    _hasAppliedStartup = true;
    setState(() => _currentTab = tab);
    // The tabs are an IndexedStack, not routes, so the navigator observers
    // never see them; this is the only screen-usage signal for the tabs.
    logUsage('screen.tab_selected', attrs: {'tab': tab.name});
    if (tab == HomeTab.dictionary) {
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
    final tabs = ref.watch(homeTabsProvider).visible;

    // Apply startup screen once after the provider has finished loading
    // the persisted value from SharedPreferences.
    final startupScreen = ref.watch(effectiveStartupScreenProvider);
    final notifier = ref.read(startupScreenProvider.notifier);
    if (!_hasAppliedStartup && notifier.hasLoaded) {
      _hasAppliedStartup = true;
      _currentTab = startupScreen.tab;
      if (_currentTab == HomeTab.dictionary) {
        _focusDictionarySearchIfNeeded();
      }
      if (startupScreen == StartupScreen.lastRead) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openLastReadBook();
        });
      }
    }

    // Hiding the current tab in settings leaves Library showing.
    if (!tabs.contains(_currentTab)) _currentTab = HomeTab.library;
    // Low RAM mode keeps only the current tab built; a tab comes back fresh.
    final lowRamMode = ref.watch(lowRamModeProvider);
    _loadedScreens.removeWhere(
      (tab, _) => !tabs.contains(tab) || (lowRamMode && tab != _currentTab),
    );
    _loadedScreens.putIfAbsent(_currentTab, () => _buildScreen(_currentTab));

    final selectedIndex = tabs.indexOf(_currentTab);
    // Library alone needs no bar.
    final showBar = tabs.length > 1;
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: [
          // Keyed, so a reordered bar moves each tab's state with it.
          for (final tab in tabs)
            KeyedSubtree(
              key: ValueKey(tab),
              child: _loadedScreens[tab] ?? const SizedBox.shrink(),
            ),
        ],
      ),
      // The glass bar floats over the tabs, which scroll under it.
      extendBody: showBar && usesGlassTabBar,
      bottomNavigationBar: !showBar
          ? null
          : usesGlassTabBar
          ? GlassTabBar.bottom(
              selectedIndex: selectedIndex,
              onTabSelected: (index) => _selectTab(tabs[index]),
              tabs: [
                for (final tab in tabs)
                  GlassTab(
                    icon: Icon(tab.icon),
                    activeIcon: Icon(tab.selectedIcon),
                    label: tab.label(l10n),
                  ),
              ],
            )
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) => _selectTab(tabs[index]),
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.label(l10n),
                  ),
              ],
            ),
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
