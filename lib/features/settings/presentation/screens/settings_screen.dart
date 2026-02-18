import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/shared/theme/app_theme.dart';
import 'package:mekuru/features/settings/data/services/yomitan_dict_download_service.dart';
import 'package:mekuru/features/settings/presentation/providers/jmdict_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjidic_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/kanjivg_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/about_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/feedback_screen.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// General app settings screen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Check asset download statuses when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kanjiVgProvider.notifier).checkStatus();
      ref.read(jpdbFreqProvider.notifier).checkStatus();
      ref.read(jmdictProvider.notifier).checkStatus();
      ref.read(kanjidicProvider.notifier).checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);
    final colorTheme = ref.watch(appColorThemeProvider);
    final startupScreen = ref.watch(startupScreenProvider);
    final lookupFontSize = ref.watch(lookupFontSizeProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final readerNotifier = ref.read(readerSettingsProvider.notifier);
    final kanjiVgState = ref.watch(kanjiVgProvider);
    final jpdbFreqState = ref.watch(jpdbFreqProvider);
    final jmdictState = ref.watch(jmdictProvider);
    final kanjidicState = ref.watch(kanjidicProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── General ──
          _SectionHeader(title: 'General'),
          ListTile(
            leading: Icon(
              Icons.home_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Startup Screen'),
            subtitle: Text(startupScreen.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showStartupScreenPicker(context, ref, startupScreen);
            },
          ),
          const Divider(),

          // ── Appearance ──
          _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: Icon(
              _themeModeIcon(themeMode),
              color: theme.colorScheme.primary,
            ),
            title: const Text('Theme'),
            subtitle: Text(_themeModeLabel(themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showThemeModePicker(context, ref, themeMode);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.palette_outlined,
              color: colorTheme.seedColor,
            ),
            title: const Text('Color Theme'),
            subtitle: Text(colorTheme.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showColorThemePicker(context, ref, colorTheme);
            },
          ),
          const Divider(),

          // ── Reading Defaults ──
          _SectionHeader(title: 'Reading Defaults'),
          ListTile(
            leading: Icon(
              Icons.text_fields,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Font Size'),
            subtitle: Text('${readerSettings.fontSize.round()} pt'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: readerSettings.fontSize,
              min: 12,
              max: 32,
              divisions: 20,
              label: '${readerSettings.fontSize.round()}',
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
            title: const Text('Color Mode'),
            subtitle: Text(_colorModeLabel(readerSettings.colorMode)),
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
                  Icon(Icons.coffee, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Sepia Intensity'),
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
            title: const Text('Keep Screen On'),
            subtitle: const Text('Prevent screen from sleeping while reading'),
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
                  'Horizontal Margin: ${readerSettings.horizontalPadding}px',
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
                  'Vertical Margin: ${readerSettings.verticalPadding}px',
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
                    const Text('Swipe Sensitivity'),
                    const Spacer(),
                    Text('${(readerSettings.swipeSensitivity * 100).round()}%'),
                  ],
                ),
                Slider(
                  value: readerSettings.swipeSensitivity,
                  min: 0.01,
                  max: 0.20,
                  divisions: 19,
                  label: '${(readerSettings.swipeSensitivity * 100).round()}%',
                  onChanged: (value) {
                    AppHaptics.light();
                    readerNotifier.setSwipeSensitivity(value);
                  },
                ),
                Text(
                  'Lower = less finger movement needed to swipe',
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
          _SectionHeader(title: 'Dictionary'),
          ListTile(
            leading: Icon(
              Icons.book_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Manage Dictionaries'),
            subtitle: const Text('Import, reorder, enable/disable'),
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
            leading: Icon(
              Icons.text_fields,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Lookup Font Size'),
            subtitle: Text('${lookupFontSize.round()} pt'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: lookupFontSize,
              min: LookupFontSizeNotifier.minSize,
              max: LookupFontSizeNotifier.maxSize,
              divisions: 12,
              label: '${lookupFontSize.round()}',
              onChanged: (value) {
                AppHaptics.light();
                ref
                    .read(lookupFontSizeProvider.notifier)
                    .setFontSize(value);
              },
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.abc,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Filter Roman Letter Entries'),
            subtitle:
                const Text('Hide entries using English letters in headword'),
            value: ref.watch(filterRomanLettersProvider),
            onChanged: (value) {
              AppHaptics.light();
              ref
                  .read(filterRomanLettersProvider.notifier)
                  .setFilter(value);
            },
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.keyboard_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Auto-Focus Search'),
            subtitle:
                const Text('Open keyboard when dictionary tab is selected'),
            value: ref.watch(autoFocusSearchProvider),
            onChanged: (value) {
              AppHaptics.light();
              ref
                  .read(autoFocusSearchProvider.notifier)
                  .setAutoFocus(value);
            },
          ),
          const Divider(),

          // ── Vocabulary & Export ──
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            _SectionHeader(title: 'Vocabulary & Export'),
            ListTile(
              leading: Icon(
                Icons.electric_bolt_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('AnkiDroid Integration'),
              subtitle:
                  const Text('Configure note type, deck, and field mapping'),
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

          // ── Downloads ──
          _SectionHeader(title: 'Downloads'),

          // KanjiVG
          _KanjiVgTile(state: kanjiVgState, theme: theme),
          if (kanjiVgState.isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: kanjiVgState.progress),
                  const SizedBox(height: 4),
                  Text(
                    kanjiVgState.progress < 0.9
                        ? 'Downloading... ${(kanjiVgState.progress * 100).toInt()}%'
                        : 'Extracting files...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          if (kanjiVgState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                kanjiVgState.error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
          if (kanjiVgState.successMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                kanjiVgState.successMessage!,
                style: const TextStyle(color: Colors.green, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Kanji stroke order data by KanjiVG (Ulrich Apel), '
              'licensed under CC BY-SA 3.0.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // JPDB Frequency
          _JpdbFreqTile(state: jpdbFreqState, theme: theme),
          if (jpdbFreqState.isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: jpdbFreqState.progress),
                  const SizedBox(height: 4),
                  Text(
                    jpdbFreqState.progress < 0.7
                        ? 'Downloading... ${(jpdbFreqState.progress / 0.7 * 100).toInt()}%'
                        : 'Importing...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          if (jpdbFreqState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                jpdbFreqState.error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
          if (jpdbFreqState.successMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                jpdbFreqState.successMessage!,
                style: const TextStyle(color: Colors.green, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Word frequency data from JPDB (jpdb.io), '
              'distributed by Kuuuube.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // JMdict English
          _JmdictTile(state: jmdictState, theme: theme),
          if (jmdictState.isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: jmdictState.progress),
                  const SizedBox(height: 4),
                  Text(
                    jmdictState.progress < 0.05
                        ? 'Fetching latest release...'
                        : jmdictState.progress < 0.7
                            ? 'Downloading... ${((jmdictState.progress - 0.05) / 0.65 * 100).toInt()}%'
                            : 'Importing...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          if (jmdictState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                jmdictState.error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
          if (jmdictState.successMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                jmdictState.successMessage!,
                style: const TextStyle(color: Colors.green, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'JMdict by the Electronic Dictionary Research and '
              'Development Group (EDRDG), licensed under CC BY-SA 4.0.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // KANJIDIC
          _KanjidicTile(state: kanjidicState, theme: theme),
          if (kanjidicState.isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: kanjidicState.progress),
                  const SizedBox(height: 4),
                  Text(
                    kanjidicState.progress < 0.05
                        ? 'Fetching latest release...'
                        : kanjidicState.progress < 0.7
                            ? 'Downloading... ${((kanjidicState.progress - 0.05) / 0.65 * 100).toInt()}%'
                            : 'Importing...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          if (kanjidicState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                kanjidicState.error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
          if (kanjidicState.successMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                kanjidicState.successMessage!,
                style: const TextStyle(color: Colors.green, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'KANJIDIC by the Electronic Dictionary Research and '
              'Development Group (EDRDG), licensed under CC BY-SA 4.0.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(),

          // ── Feedback & About ──
          _SectionHeader(title: 'About & Feedback'),
          ListTile(
            leading: Icon(
              Icons.feedback_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Send Feedback'),
            subtitle: const Text('Report a bug or suggest a feature'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              AppHaptics.light();
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const FeedbackScreen(),
                ),
              );
              if (!context.mounted) return;
              if (result == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Thank you for your feedback!'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              } else if (result == false) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Failed to send feedback. Please try again.'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(
              Icons.info_outline,
              color: theme.colorScheme.primary,
            ),
            title: const Text('About Mekuru'),
            subtitle: const Text('Version, licenses, and more'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Helpers ──

  static String _colorModeLabel(ColorMode mode) => switch (mode) {
        ColorMode.normal => 'Normal',
        ColorMode.sepia => 'Sepia',
        ColorMode.dark => 'Dark',
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
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Color Mode',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final mode in ColorMode.values)
              ListTile(
                leading: Icon(_colorModeIcon(mode)),
                title: Text(_colorModeLabel(mode)),
                trailing: currentMode == mode
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  AppHaptics.medium();
                  ref
                      .read(readerSettingsProvider.notifier)
                      .setColorMode(mode);
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

  static String _themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System default',
      };

  void _showThemeModePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Theme',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            _ThemeModeOption(
              mode: ThemeMode.light,
              icon: Icons.light_mode,
              label: 'Light',
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
              label: 'Dark',
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
              label: 'System default',
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

  void _showColorThemePicker(
    BuildContext context,
    WidgetRef ref,
    AppColorTheme currentTheme,
  ) {
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
                  'Color Theme',
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
                        leading: Icon(
                          Icons.circle,
                          color: option.seedColor,
                        ),
                        title: Text(option.label),
                        trailing: currentTheme == option
                            ? Icon(Icons.check,
                                color:
                                    Theme.of(context).colorScheme.primary)
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
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Startup Screen',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final option in StartupScreen.values)
              ListTile(
                leading: Icon(_startupScreenIcon(option)),
                title: Text(option.label),
                trailing: current == option
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
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

/// Tile showing KanjiVG download status and actions.
class _KanjiVgTile extends ConsumerWidget {
  const _KanjiVgTile({required this.state, required this.theme});

  final KanjiVgState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = state.isDownloaded
        ? '${state.fileCount} stroke order files downloaded'
        : 'Download kanji stroke order data from KanjiVG';

    return ListTile(
      leading: Icon(
        Icons.brush_outlined,
        color: theme.colorScheme.primary,
      ),
      title: const Text('Kanji Stroke Order'),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isDownloaded) {
      return IconButton(
        icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
        tooltip: 'Delete kanji data',
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        ref.read(kanjiVgProvider.notifier).download();
      },
      child: const Text('Download'),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Kanji Data'),
        content: const Text(
          'Delete all downloaded kanji stroke order files? '
          'You can re-download them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(kanjiVgProvider.notifier).delete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Tile showing JPDB frequency dictionary download status and actions.
class _JpdbFreqTile extends ConsumerWidget {
  const _JpdbFreqTile({required this.state, required this.theme});

  final JpdbFreqState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = state.isImported
        ? 'Frequency data downloaded'
        : 'Download word frequency data for search ranking';

    return ListTile(
      leading: Icon(
        Icons.bar_chart_outlined,
        color: theme.colorScheme.primary,
      ),
      title: const Text('Word Frequency'),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isImported) {
      return IconButton(
        icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
        tooltip: 'Delete frequency data',
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        ref.read(jpdbFreqProvider.notifier).download();
      },
      child: const Text('Download'),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Frequency Data'),
        content: const Text(
          'Delete word frequency data? '
          'Search results will no longer be ranked by frequency. '
          'You can re-download it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(jpdbFreqProvider.notifier).delete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Tile showing JMdict English download status and actions.
class _JmdictTile extends ConsumerWidget {
  const _JmdictTile({required this.state, required this.theme});

  final JmdictState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = state.isImported
        ? 'Japanese-English dictionary downloaded'
        : 'Download Japanese-English dictionary';

    return ListTile(
      leading: Icon(
        Icons.translate,
        color: theme.colorScheme.primary,
      ),
      title: const Text('JMdict English'),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isImported) {
      return IconButton(
        icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
        tooltip: 'Delete JMdict',
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        _showVariantPicker(context, ref);
      },
      child: const Text('Download'),
    );
  }

  void _showVariantPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choose JMdict variant',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('JMdict English'),
              subtitle: const Text('Standard dictionary (~15 MB)'),
              onTap: () {
                Navigator.of(ctx).pop();
                AppHaptics.light();
                ref.read(jmdictProvider.notifier).download(
                      YomitanDictType.jmdictEnglish,
                    );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('JMdict English with Examples'),
              subtitle: const Text('Includes example sentences (~18 MB)'),
              onTap: () {
                Navigator.of(ctx).pop();
                AppHaptics.light();
                ref.read(jmdictProvider.notifier).download(
                      YomitanDictType.jmdictEnglishWithExamples,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete JMdict'),
        content: const Text(
          'Delete JMdict and all its entries? '
          'You can re-download it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(jmdictProvider.notifier).delete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Tile showing KANJIDIC download status and actions.
class _KanjidicTile extends ConsumerWidget {
  const _KanjidicTile({required this.state, required this.theme});

  final KanjidicState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = state.isImported
        ? 'Kanji dictionary downloaded'
        : 'Download kanji dictionary';

    return ListTile(
      leading: Icon(
        Icons.font_download_outlined,
        color: theme.colorScheme.primary,
      ),
      title: const Text('KANJIDIC'),
      subtitle: Text(subtitle),
      trailing: _buildTrailing(context, ref),
    );
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref) {
    if (state.isDownloading || state.isDeleting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (state.isImported) {
      return IconButton(
        icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
        tooltip: 'Delete KANJIDIC',
        onPressed: () => _confirmDelete(context, ref),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        AppHaptics.light();
        ref.read(kanjidicProvider.notifier).download();
      },
      child: const Text('Download'),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete KANJIDIC'),
        content: const Text(
          'Delete KANJIDIC and all its entries? '
          'You can re-download it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(kanjidicProvider.notifier).delete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
