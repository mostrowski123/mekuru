import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/config/app_links.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/manga/presentation/screens/pro_upgrade_screen.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_settings_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/about_screen.dart';
import 'package:mekuru/features/backup/presentation/screens/backup_settings_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/feedback_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/reading_settings_screen.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/theme/app_theme.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:url_launcher/url_launcher.dart';

/// General app settings screen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final resolvedLocale = Localizations.localeOf(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          // ── General ──
          SettingsSectionHeader(title: l10n.settingsSectionGeneral),
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
              _showAppLanguagePicker(appLanguage);
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
              _showStartupScreenPicker(startupScreen);
            },
          ),
          const Divider(),

          // ── Appearance ──
          SettingsSectionHeader(title: l10n.settingsSectionAppearance),
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
              _showThemeModePicker(themeMode);
            },
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined, color: colorTheme.seedColor),
            title: Text(l10n.settingsColorThemeTitle),
            subtitle: Text(_colorThemeLabel(l10n, colorTheme)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showColorThemePicker(colorTheme);
            },
          ),
          const Divider(),

          // ── Reading ──
          SettingsSectionHeader(title: l10n.settingsSectionReading),
          ListTile(
            leading: Icon(
              Icons.menu_book_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsReadingTitle),
            subtitle: Text(l10n.settingsReadingSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'reading_settings'),
                  builder: (_) => const ReadingSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // ── Dictionary ──
          SettingsSectionHeader(title: l10n.settingsSectionDictionary),
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
                  settings: const RouteSettings(name: 'dictionary_manager'),
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
            SettingsSectionHeader(title: l10n.settingsSectionVocabularyExport),
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
                    settings: const RouteSettings(name: 'anki_settings'),
                    builder: (_) => const AnkidroidSettingsScreen(),
                  ),
                );
              },
            ),
            const Divider(),
          ],

          // ── Server sync ──
          SettingsSectionHeader(title: l10n.settingsSectionServerSync),
          ListTile(
            leading: Icon(Icons.dns_outlined, color: theme.colorScheme.primary),
            title: Text(l10n.settingsServerSyncTitle),
            subtitle: Text(l10n.settingsServerSyncSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'server_settings'),
                  builder: (_) => const ServerSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // ── Manga OCR ──
          SettingsSectionHeader(title: l10n.settingsSectionPro),
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

          // ── Downloads ──
          SettingsSectionHeader(title: l10n.settingsSectionDownloads),
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
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'downloads'),
                  builder: (_) => const DownloadsScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // ── Backup & Restore ──
          SettingsSectionHeader(title: l10n.settingsSectionBackupRestore),
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
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'backup_settings'),
                  builder: (_) => const BackupSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // ── Feedback & About ──
          SettingsSectionHeader(title: l10n.settingsSectionAboutFeedback),
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
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'feedback'),
                  builder: (_) => const FeedbackScreen(),
                ),
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
                AppLinks.documentation,
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'about'),
                  builder: (_) => const AboutScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Helpers ──

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

  void _showThemeModePicker(ThemeMode currentMode) {
    final l10n = context.l10n;

    showSettingsOptionPickerSheet(
      context: context,
      title: l10n.settingsThemeTitle,
      values: ThemeMode.values,
      selected: currentMode,
      labelOf: (mode) => _themeModeLabel(l10n, mode),
      iconOf: _themeModeIcon,
      onSelected: (mode) =>
          ref.read(appThemeModeProvider.notifier).setThemeMode(mode),
    );
  }

  void _showAppLanguagePicker(AppLanguage currentLanguage) {
    final l10n = context.l10n;

    showSettingsOptionPickerSheet(
      context: context,
      title: l10n.settingsAppLanguageTitle,
      values: AppLanguage.values,
      selected: currentLanguage,
      labelOf: (language) => _appLanguageLabel(l10n, language),
      onSelected: (language) =>
          ref.read(appLanguageProvider.notifier).setAppLanguage(language),
    );
  }

  void _showColorThemePicker(AppColorTheme currentTheme) {
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

  void _showStartupScreenPicker(StartupScreen current) {
    final l10n = context.l10n;

    showSettingsOptionPickerSheet(
      context: context,
      title: l10n.settingsStartupScreenTitle,
      values: StartupScreen.values,
      selected: current,
      labelOf: (option) => _startupScreenLabel(l10n, option),
      iconOf: _startupScreenIcon,
      onSelected: (option) =>
          ref.read(startupScreenProvider.notifier).setStartupScreen(option),
    );
  }

  static IconData _startupScreenIcon(StartupScreen screen) => switch (screen) {
    StartupScreen.library => Icons.auto_stories_outlined,
    StartupScreen.dictionary => Icons.book_outlined,
    StartupScreen.lastRead => Icons.menu_book_outlined,
  };
}
