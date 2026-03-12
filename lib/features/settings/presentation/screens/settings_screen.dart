import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/firebase_runtime.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/manga/data/services/ocr_auth_secret_storage.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_health_client.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/about_screen.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/feedback_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/theme/app_theme.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:url_launcher/url_launcher.dart';

/// General app settings screen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final OcrAuthSecretStorage _ocrAuthSecretStorage = OcrAuthSecretStorage();

  Future<void> _openProUpgrade() async {
    await openProUpgrade(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final appLanguage = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final colorTheme = ref.watch(appColorThemeProvider);
    final startupScreen = ref.watch(startupScreenProvider);
    final lookupFontSize = ref.watch(lookupFontSizeProvider);
    final autoCropWhiteThreshold = ref.watch(autoCropWhiteThresholdProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final readerNotifier = ref.read(readerSettingsProvider.notifier);
    final hasFirebaseApp = FirebaseRuntime.instance.hasFirebaseApp;
    final isProUnlocked = proUnlockedValue(ref.watch(proUnlockedProvider));
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final resolvedLocale = Localizations.localeOf(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          // ── General ──
          _SectionHeader(title: l10n.settingsSectionGeneral),
          ListTile(
            leading: Icon(
              Icons.translate_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsAppLanguageTitle),
            subtitle: Text(
              _currentAppLanguageLabel(l10n, appLanguage, resolvedLocale),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showAppLanguagePicker(context, ref, appLanguage);
            },
          ),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.home_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsStartupScreenTitle),
            subtitle: Text(_startupScreenLabel(l10n, startupScreen)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showStartupScreenPicker(context, ref, startupScreen);
            },
          ),
          const Divider(),

          // ── Appearance ──
          _SectionHeader(title: l10n.settingsSectionAppearance),
          ListTile(
            leading: Icon(
              _themeModeIcon(themeMode),
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsThemeTitle),
            subtitle: Text(_themeModeLabel(l10n, themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showThemeModePicker(context, ref, themeMode);
            },
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined, color: colorTheme.seedColor),
            title: Text(l10n.settingsColorThemeTitle),
            subtitle: Text(_colorThemeLabel(l10n, colorTheme)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showColorThemePicker(context, ref, colorTheme);
            },
          ),
          const Divider(),

          // ── Reading Defaults ──
          _SectionHeader(title: l10n.settingsSectionReadingDefaults),
          ListTile(
            leading: Icon(Icons.text_fields, color: theme.colorScheme.primary),
            title: Text(l10n.settingsFontSizeTitle),
            subtitle: Text(
              l10n.settingsPointsValue(points: readerSettings.fontSize.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: readerSettings.fontSize,
              min: 12,
              max: 32,
              divisions: 20,
              label: readerSettings.fontSize.round().toString(),
              onChanged: (value) {
                AppHaptics.light();
                readerNotifier.setFontSize(value);
              },
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.color_lens_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsColorModeTitle),
            subtitle: Text(_colorModeLabel(l10n, readerSettings.colorMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showColorModePicker(context, ref, readerSettings.colorMode);
            },
          ),
          if (readerSettings.colorMode == ColorMode.sepia) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.coffee,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.settingsSepiaIntensityTitle),
                  Expanded(
                    child: Slider(
                      value: readerSettings.sepiaIntensity,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (value) {
                        AppHaptics.light();
                        readerNotifier.setSepiaIntensity(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          SwitchListTile(
            secondary: Icon(
              Icons.lightbulb_outline,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsKeepScreenOnTitle),
            subtitle: Text(l10n.settingsKeepScreenOnSubtitle),
            value: readerSettings.keepScreenOn,
            onChanged: (value) {
              AppHaptics.light();
              readerNotifier.setKeepScreenOn(value);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsHorizontalMarginValue(
                    pixels: readerSettings.horizontalPadding,
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                Slider(
                  value: readerSettings.horizontalPadding.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (value) {
                    AppHaptics.light();
                    readerNotifier.setHorizontalPadding(value.round());
                  },
                ),
                Text(
                  l10n.settingsVerticalMarginValue(
                    pixels: readerSettings.verticalPadding,
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                Slider(
                  value: readerSettings.verticalPadding.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (value) {
                    AppHaptics.light();
                    readerNotifier.setVerticalPadding(value.round());
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.swipe, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(l10n.settingsSwipeSensitivityTitle),
                    const Spacer(),
                    Text(
                      l10n.settingsPercentValue(
                        percent: (readerSettings.swipeSensitivity * 100)
                            .round(),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: readerSettings.swipeSensitivity,
                  min: 0.01,
                  max: 0.20,
                  divisions: 19,
                  label: l10n.settingsPercentValue(
                    percent: (readerSettings.swipeSensitivity * 100).round(),
                  ),
                  onChanged: (value) {
                    AppHaptics.light();
                    readerNotifier.setSwipeSensitivity(value);
                  },
                ),
                Text(
                  l10n.settingsSwipeSensitivityHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Divider(),

          // ── Dictionary ──
          _SectionHeader(title: l10n.settingsSectionDictionary),
          ListTile(
            leading: Icon(
              Icons.book_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.commonManageDictionaries),
            subtitle: Text(l10n.settingsManageDictionariesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DictionaryManagerScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.text_fields, color: theme.colorScheme.primary),
            title: Text(l10n.settingsLookupFontSizeTitle),
            subtitle: Text(
              l10n.settingsPointsValue(points: lookupFontSize.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: lookupFontSize,
              min: LookupFontSizeNotifier.minSize,
              max: LookupFontSizeNotifier.maxSize,
              divisions: 12,
              label: lookupFontSize.round().toString(),
              onChanged: (value) {
                AppHaptics.light();
                ref.read(lookupFontSizeProvider.notifier).setFontSize(value);
              },
            ),
          ),
          SwitchListTile(
            secondary: Icon(Icons.abc, color: theme.colorScheme.primary),
            title: Text(l10n.settingsFilterRomanLetterEntriesTitle),
            subtitle: Text(l10n.settingsFilterRomanLetterEntriesSubtitle),
            value: ref.watch(filterRomanLettersProvider),
            onChanged: (value) {
              AppHaptics.light();
              ref.read(filterRomanLettersProvider.notifier).setFilter(value);
            },
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.keyboard_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsAutoFocusSearchTitle),
            subtitle: Text(l10n.settingsAutoFocusSearchSubtitle),
            value: ref.watch(autoFocusSearchProvider),
            onChanged: (value) {
              AppHaptics.light();
              ref.read(autoFocusSearchProvider.notifier).setAutoFocus(value);
            },
          ),
          const Divider(),

          // ── Vocabulary & Export ──
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            _SectionHeader(title: l10n.settingsSectionVocabularyExport),
            ListTile(
              leading: Icon(
                Icons.electric_bolt_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l10n.settingsAnkiDroidIntegrationTitle),
              subtitle: Text(l10n.settingsAnkiDroidIntegrationSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                AppHaptics.light();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AnkidroidSettingsScreen(),
                  ),
                );
              },
            ),
            const Divider(),
          ],

          // ── Manga OCR ──
          _SectionHeader(title: l10n.settingsSectionPro),
          if (!hasFirebaseApp)
            ListTile(
              enabled: false,
              leading: Icon(
                Icons.shopping_bag_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(l10n.proTitle),
              subtitle: Text(l10n.settingsProUnavailableSubtitle),
              trailing: const Icon(Icons.chevron_right),
            )
          else
            ListTile(
              leading: Icon(
                Icons.shopping_bag_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(l10n.proTitle),
              subtitle: Text(l10n.settingsProSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                AppHaptics.light();
                _openProUpgrade();
              },
            ),
          const Divider(),
          if (isProUnlocked) ...[
            _SectionHeader(title: l10n.settingsSectionMangaAutoCrop),
            ListTile(
              leading: Icon(Icons.tune, color: theme.colorScheme.primary),
              title: Text(l10n.settingsWhiteThresholdTitle),
              subtitle: Text(
                l10n.settingsWhiteThresholdSubtitle(
                  threshold: autoCropWhiteThreshold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider(
                value: autoCropWhiteThreshold.toDouble(),
                min: AutoCropWhiteThresholdNotifier.minThreshold.toDouble(),
                max: AutoCropWhiteThresholdNotifier.maxThreshold.toDouble(),
                divisions:
                    AutoCropWhiteThresholdNotifier.maxThreshold -
                    AutoCropWhiteThresholdNotifier.minThreshold,
                label: '$autoCropWhiteThreshold',
                onChanged: (value) {
                  ref
                      .read(autoCropWhiteThresholdProvider.notifier)
                      .setThreshold(value);
                },
              ),
            ),
            const Divider(),
            _SectionHeader(title: l10n.settingsSectionMangaOcr),
            if (!hasFirebaseApp)
              ListTile(
                enabled: false,
                leading: Icon(
                  Icons.document_scanner_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(l10n.settingsCustomOcrServerTitle),
                subtitle: Text(l10n.settingsCustomOcrServerUnavailableSubtitle),
              )
            else
              Builder(
                builder: (context) {
                  final currentOcrServerUrl = ref.watch(ocrServerUrlProvider);
                  final usesBuiltInServer = isUnsetOrBuiltInOcrServerUrl(
                    currentOcrServerUrl,
                  );
                  final subtitle = usesBuiltInServer
                      ? l10n.settingsCustomOcrServerNotConfigured
                      : l10n.settingsCustomOcrServerConfigured(
                          url: currentOcrServerUrl,
                        );

                  return ListTile(
                    leading: Icon(
                      Icons.document_scanner_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(l10n.settingsCustomOcrServerTitle),
                    subtitle: Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      AppHaptics.light();
                      _showOcrServerUrlDialog(context, ref);
                    },
                  );
                },
              ),
            const Divider(),
          ],

          // ── Downloads ──
          _SectionHeader(title: l10n.settingsSectionDownloads),
          ListTile(
            leading: Icon(
              Icons.download_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.downloadsTitle),
            subtitle: Text(l10n.settingsDownloadsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
          const Divider(),

          // ── Backup & Restore ──
          _SectionHeader(title: l10n.settingsSectionBackupRestore),
          ListTile(
            leading: Icon(
              Icons.backup_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsBackupRestoreTitle),
            subtitle: Text(l10n.settingsBackupRestoreSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupSettingsScreen()),
              );
            },
          ),
          const Divider(),

          // ── Feedback & About ──
          _SectionHeader(title: l10n.settingsSectionAboutFeedback),
          ListTile(
            leading: Icon(
              Icons.feedback_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.feedbackTitle),
            subtitle: Text(l10n.settingsSendFeedbackSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              AppHaptics.light();
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
              );
              if (!context.mounted) return;
              if (result == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.settingsFeedbackThanks),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else if (result == false) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.settingsFeedbackFailed),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(
              Icons.menu_book_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsDocumentationTitle),
            subtitle: Text(l10n.settingsDocumentationSubtitle),
            trailing: const Icon(Icons.open_in_new, size: 20),
            onTap: () {
              AppHaptics.light();
              launchUrl(
                Uri.parse('https://mekuru.matthew.moe/documentation/'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
            title: Text(l10n.settingsAboutMekuruTitle),
            subtitle: Text(l10n.settingsAboutMekuruSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Helpers ──

  static String _colorModeLabel(AppLocalizations l10n, ColorMode mode) =>
      switch (mode) {
        ColorMode.normal => l10n.settingsColorModeNormal,
        ColorMode.sepia => l10n.settingsColorModeSepia,
        ColorMode.dark => l10n.settingsColorModeDark,
      };

  static IconData _colorModeIcon(ColorMode mode) => switch (mode) {
    ColorMode.normal => Icons.brightness_5,
    ColorMode.sepia => Icons.filter_vintage,
    ColorMode.dark => Icons.dark_mode,
  };

  void _showColorModePicker(
    BuildContext context,
    WidgetRef ref,
    ColorMode currentMode,
  ) {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.settingsColorModeTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final mode in ColorMode.values)
              ListTile(
                leading: Icon(_colorModeIcon(mode)),
                title: Text(_colorModeLabel(l10n, mode)),
                trailing: currentMode == mode
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  AppHaptics.medium();
                  ref.read(readerSettingsProvider.notifier).setColorMode(mode);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  static IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
    ThemeMode.system => Icons.brightness_auto,
  };

  static String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.light => l10n.settingsThemeLight,
        ThemeMode.dark => l10n.settingsThemeDark,
        ThemeMode.system => l10n.settingsThemeSystemDefault,
      };

  static String _startupScreenLabel(
    AppLocalizations l10n,
    StartupScreen screen,
  ) => switch (screen) {
    StartupScreen.library => l10n.settingsStartupScreenLibrary,
    StartupScreen.dictionary => l10n.settingsStartupScreenDictionary,
    StartupScreen.lastRead => l10n.settingsStartupScreenLastRead,
  };

  static String _currentAppLanguageLabel(
    AppLocalizations l10n,
    AppLanguage language,
    Locale resolvedLocale,
  ) {
    return switch (language) {
      AppLanguage.system => l10n.settingsAppLanguageSystemValue(
        language: _resolvedAppLanguageLabel(l10n, resolvedLocale),
      ),
      _ => _appLanguageLabel(l10n, language),
    };
  }

  static String _resolvedAppLanguageLabel(
    AppLocalizations l10n,
    Locale locale,
  ) {
    return switch (locale.languageCode) {
      'es' => l10n.settingsAppLanguageSpanish,
      'id' => l10n.settingsAppLanguageIndonesian,
      'zh' => l10n.settingsAppLanguageSimplifiedChinese,
      _ => l10n.settingsAppLanguageEnglish,
    };
  }

  static String _appLanguageLabel(
    AppLocalizations l10n,
    AppLanguage language,
  ) => switch (language) {
    AppLanguage.system => l10n.settingsThemeSystemDefault,
    AppLanguage.english => l10n.settingsAppLanguageEnglish,
    AppLanguage.spanish => l10n.settingsAppLanguageSpanish,
    AppLanguage.indonesian => l10n.settingsAppLanguageIndonesian,
    AppLanguage.simplifiedChinese => l10n.settingsAppLanguageSimplifiedChinese,
  };

  static String _colorThemeLabel(AppLocalizations l10n, AppColorTheme theme) =>
      switch (theme) {
        AppColorTheme.mekuruRed => l10n.settingsColorThemeMekuruRed,
        AppColorTheme.indigo => l10n.settingsColorThemeIndigo,
        AppColorTheme.teal => l10n.settingsColorThemeTeal,
        AppColorTheme.deepPurple => l10n.settingsColorThemeDeepPurple,
        AppColorTheme.blue => l10n.settingsColorThemeBlue,
        AppColorTheme.green => l10n.settingsColorThemeGreen,
        AppColorTheme.orange => l10n.settingsColorThemeOrange,
        AppColorTheme.pink => l10n.settingsColorThemePink,
        AppColorTheme.blueGrey => l10n.settingsColorThemeBlueGrey,
      };

  void _showThemeModePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.settingsThemeTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            _ThemeModeOption(
              mode: ThemeMode.light,
              icon: Icons.light_mode,
              label: l10n.settingsThemeLight,
              isSelected: currentMode == ThemeMode.light,
              onTap: () {
                AppHaptics.medium();
                ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light);
                Navigator.of(sheetContext).pop();
              },
            ),
            _ThemeModeOption(
              mode: ThemeMode.dark,
              icon: Icons.dark_mode,
              label: l10n.settingsThemeDark,
              isSelected: currentMode == ThemeMode.dark,
              onTap: () {
                AppHaptics.medium();
                ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.dark);
                Navigator.of(sheetContext).pop();
              },
            ),
            _ThemeModeOption(
              mode: ThemeMode.system,
              icon: Icons.brightness_auto,
              label: l10n.settingsThemeSystemDefault,
              isSelected: currentMode == ThemeMode.system,
              onTap: () {
                AppHaptics.medium();
                ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.system);
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAppLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    AppLanguage currentLanguage,
  ) {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.settingsAppLanguageTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final language in AppLanguage.values)
              ListTile(
                title: Text(_appLanguageLabel(l10n, language)),
                trailing: currentLanguage == language
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  AppHaptics.medium();
                  ref
                      .read(appLanguageProvider.notifier)
                      .setAppLanguage(language);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showColorThemePicker(
    BuildContext context,
    WidgetRef ref,
    AppColorTheme currentTheme,
  ) {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.settingsColorThemeTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    for (final option in AppColorTheme.values)
                      ListTile(
                        leading: Icon(Icons.circle, color: option.seedColor),
                        title: Text(_colorThemeLabel(l10n, option)),
                        trailing: currentTheme == option
                            ? Icon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          AppHaptics.medium();
                          ref
                              .read(appColorThemeProvider.notifier)
                              .setColorTheme(option);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStartupScreenPicker(
    BuildContext context,
    WidgetRef ref,
    StartupScreen current,
  ) {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.settingsStartupScreenTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final option in StartupScreen.values)
              ListTile(
                leading: Icon(_startupScreenIcon(option)),
                title: Text(_startupScreenLabel(l10n, option)),
                trailing: current == option
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  AppHaptics.medium();
                  ref
                      .read(startupScreenProvider.notifier)
                      .setStartupScreen(option);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  static IconData _startupScreenIcon(StartupScreen screen) => switch (screen) {
    StartupScreen.library => Icons.auto_stories_outlined,
    StartupScreen.dictionary => Icons.book_outlined,
    StartupScreen.lastRead => Icons.menu_book_outlined,
  };

  Future<void> _showOcrServerUrlDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final savedCustomBearerKey =
        await _ocrAuthSecretStorage.loadCustomServerBearerKey() ?? '';
    final currentUrl = ref.read(ocrServerUrlProvider);
    final initialUrl = isUnsetOrBuiltInOcrServerUrl(currentUrl)
        ? ''
        : currentUrl;

    if (!context.mounted) return;

    final result = await showDialog<({String url, String? bearerKey})>(
      context: context,
      builder: (_) => _OcrServerUrlDialog(
        initialUrl: initialUrl,
        initialBearerKey: savedCustomBearerKey,
      ),
    );

    if (result != null) {
      await _ocrAuthSecretStorage.saveCustomServerBearerKey(result.bearerKey!);
      ref.read(ocrServerUrlProvider.notifier).setUrl(result.url);
    }
  }
}

// ── Custom OCR Server Dialog ──

class _OcrServerUrlDialog extends StatefulWidget {
  const _OcrServerUrlDialog({
    required this.initialUrl,
    required this.initialBearerKey,
  });

  final String initialUrl;
  final String initialBearerKey;

  @override
  State<_OcrServerUrlDialog> createState() => _OcrServerUrlDialogState();
}

class _OcrServerUrlDialogState extends State<_OcrServerUrlDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late final OcrServerHealthClient _healthClient;
  bool _obscureKey = true;
  bool _isTestingConnection = false;
  bool? _testSucceeded;
  String? _testMessage;
  String? _urlError;
  String? _keyError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _keyController = TextEditingController(text: widget.initialBearerKey);
    _healthClient = OcrServerHealthClient();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _healthClient.dispose();
    super.dispose();
  }

  void _onSave() {
    final l10n = context.l10n;
    final url = ocr_server_config.normalizeOcrServerUrl(_urlController.text);
    final customKey = _keyController.text.trim();

    if (url.isEmpty || customKey.isEmpty) {
      setState(() {
        _urlError = url.isEmpty
            ? l10n.settingsCustomOcrServerUrlRequired
            : null;
        _keyError = customKey.isEmpty
            ? l10n.settingsCustomOcrServerKeyRequired
            : null;
      });
      return;
    }

    if (ocr_server_config.tryParseOcrServerUrl(url) == null) {
      setState(() {
        _urlError = l10n.settingsCustomOcrServerUrlInvalid;
        _keyError = null;
      });
      return;
    }

    Navigator.of(context).pop((url: url, bearerKey: customKey));
  }

  Future<void> _onTestConnection() async {
    final l10n = context.l10n;
    final url = ocr_server_config.normalizeOcrServerUrl(_urlController.text);
    if (ocr_server_config.tryParseOcrServerUrl(url) == null) {
      setState(() {
        _urlError = url.isEmpty
            ? l10n.settingsCustomOcrServerUrlRequired
            : l10n.settingsCustomOcrServerUrlInvalid;
        _testSucceeded = false;
        _testMessage = null;
      });
      return;
    }

    setState(() {
      _urlError = null;
      _isTestingConnection = true;
      _testSucceeded = null;
      _testMessage = l10n.settingsCustomOcrServerTesting;
    });

    try {
      final result = await _healthClient.checkHealth(url);
      if (!mounted) return;
      setState(() {
        _isTestingConnection = false;
        _testSucceeded = true;
        _testMessage = l10n.settingsCustomOcrServerHealthy(
          status: result.status,
        );
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is OcrServerHealthException ? e.message : '$e';
      setState(() {
        _isTestingConnection = false;
        _testSucceeded = false;
        _testMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.settingsCustomOcrServerTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _urlController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.settingsCustomOcrServerUrlLabel,
                  hintText: l10n.settingsCustomOcrServerUrlHint,
                  border: const OutlineInputBorder(),
                  errorText: _urlError,
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {
                  _urlError = null;
                  _testSucceeded = null;
                  _testMessage = null;
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(ocr_server_config.mekuruOcrRepoUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(l10n.settingsCustomOcrServerLearnHow),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isTestingConnection ? null : _onTestConnection,
                    icon: _isTestingConnection
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.health_and_safety_outlined),
                    label: Text(
                      _isTestingConnection
                          ? l10n.settingsCustomOcrServerTesting
                          : l10n.settingsCustomOcrServerTestAction,
                    ),
                  ),
                ],
              ),
              if (_testMessage != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testSucceeded == true
                          ? Icons.check_circle_outline
                          : _testSucceeded == false
                          ? Icons.error_outline
                          : Icons.info_outline,
                      size: 18,
                      color: _testSucceeded == true
                          ? theme.colorScheme.primary
                          : _testSucceeded == false
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _testSucceeded == true
                              ? theme.colorScheme.primary
                              : _testSucceeded == false
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: l10n.settingsCustomOcrServerKeyLabel,
                  hintText: l10n.settingsCustomOcrServerKeyHint,
                  border: const OutlineInputBorder(),
                  errorText: _keyError,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _obscureKey = !_obscureKey;
                          });
                        },
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      if (_keyController.text.trim().isNotEmpty)
                        IconButton(
                          onPressed: () {
                            _keyController.clear();
                            setState(() {
                              _keyError = null;
                            });
                          },
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                ),
                onChanged: (_) => setState(() {
                  _keyError = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.settingsCustomOcrServerDescription,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _urlController.clear();
            _keyController.clear();
            setState(() {
              _testSucceeded = null;
              _testMessage = null;
              _urlError = null;
              _keyError = null;
            });
          },
          child: Text(l10n.commonClear),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _onSave, child: Text(l10n.commonSave)),
      ],
    );
  }
}

// ── Private widgets ──

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final ThemeMode mode;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
