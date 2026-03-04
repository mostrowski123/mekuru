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
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/about_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/downloads_screen.dart';
import 'package:mekuru/features/settings/presentation/screens/feedback_screen.dart';
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
            leading: Icon(Icons.palette_outlined, color: colorTheme.seedColor),
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
            leading: Icon(Icons.text_fields, color: theme.colorScheme.primary),
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
                  Icon(
                    Icons.coffee,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
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
            leading: Icon(Icons.text_fields, color: theme.colorScheme.primary),
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
                ref.read(lookupFontSizeProvider.notifier).setFontSize(value);
              },
            ),
          ),
          SwitchListTile(
            secondary: Icon(Icons.abc, color: theme.colorScheme.primary),
            title: const Text('Filter Roman Letter Entries'),
            subtitle: const Text(
              'Hide entries using English letters in headword',
            ),
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
            title: const Text('Auto-Focus Search'),
            subtitle: const Text(
              'Open keyboard when dictionary tab is selected',
            ),
            value: ref.watch(autoFocusSearchProvider),
            onChanged: (value) {
              AppHaptics.light();
              ref.read(autoFocusSearchProvider.notifier).setAutoFocus(value);
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
              subtitle: const Text(
                'Configure note type, deck, and field mapping',
              ),
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
          _SectionHeader(title: 'Pro'),
          if (!hasFirebaseApp)
            ListTile(
              enabled: false,
              leading: Icon(
                Icons.shopping_bag_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: const Text('Pro'),
              subtitle: const Text('Pro services are temporarily unavailable.'),
              trailing: const Icon(Icons.chevron_right),
            )
          else
            ListTile(
              leading: Icon(
                Icons.shopping_bag_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Pro'),
              subtitle: const Text(
                'Unlock auto-crop, book highlights, and custom OCR',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                AppHaptics.light();
                _openProUpgrade();
              },
            ),
          const Divider(),
          if (isProUnlocked) ...[
            _SectionHeader(title: 'Manga Auto-Crop'),
            ListTile(
              leading: Icon(Icons.tune, color: theme.colorScheme.primary),
              title: const Text('White Threshold'),
              subtitle: Text(
                '$autoCropWhiteThreshold (lower values ignore more near-white artifacts)',
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
            _SectionHeader(title: 'Manga OCR'),
            if (!hasFirebaseApp)
              ListTile(
                enabled: false,
                leading: Icon(
                  Icons.document_scanner_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: const Text('Custom OCR Server'),
                subtitle: const Text(
                  'OCR services are temporarily unavailable.',
                ),
              )
            else
              Builder(
                builder: (context) {
                  final currentOcrServerUrl = ref.watch(ocrServerUrlProvider);
                  final usesBuiltInServer = isBuiltInOcrServerUrl(
                    currentOcrServerUrl,
                  );
                  final subtitle = usesBuiltInServer
                      ? 'Not configured. Add your own server URL and shared key.'
                      : '$currentOcrServerUrl\nUse the same shared key configured on your server.';

                  return ListTile(
                    leading: Icon(
                      Icons.document_scanner_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Custom OCR Server'),
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
          _SectionHeader(title: 'Downloads'),
          ListTile(
            leading: Icon(
              Icons.download_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Downloads'),
            subtitle: const Text('Dictionaries, kanji data, and more'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
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
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
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
                    content: Text('Failed to send feedback. Please try again.'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
            title: const Text('About Mekuru'),
            subtitle: const Text('Version, licenses, and more'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          ListTile(
            leading: Icon(
              Icons.menu_book_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Documentation'),
            subtitle: const Text('Guides and how-to articles'),
            trailing: const Icon(Icons.open_in_new, size: 20),
            onTap: () {
              AppHaptics.light();
              launchUrl(
                Uri.parse('https://mekuru.matthew.moe/documentation/'),
                mode: LaunchMode.externalApplication,
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
                        leading: Icon(Icons.circle, color: option.seedColor),
                        title: Text(option.label),
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
    final initialUrl = isBuiltInOcrServerUrl(currentUrl) ? '' : currentUrl;

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
  bool _obscureKey = true;
  String? _urlError;
  String? _keyError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _keyController = TextEditingController(text: widget.initialBearerKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _onSave() {
    final url = _urlController.text.trim();
    final customKey = _keyController.text.trim();
    if (url.isEmpty || customKey.isEmpty) {
      setState(() {
        _urlError = url.isEmpty ? 'Enter your server URL.' : null;
        _keyError = customKey.isEmpty
            ? 'A shared key is required for custom servers.'
            : null;
      });
      return;
    }

    Navigator.of(context).pop((url: url, bearerKey: customKey));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Custom OCR Server'),
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
                  labelText: 'Server URL',
                  hintText:
                      'http://192.168.1.100:8000',
                  border: const OutlineInputBorder(),
                  errorText: _urlError,
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {
                  _urlError = null;
                }),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(ocr_server_config.mekuruOcrRepoUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Learn how to run your own server'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'Custom shared key',
                  hintText: 'Required AUTH_API_KEY',
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
                'Enter the same shared AUTH_API_KEY used by your OCR '
                'server. Mekuru sends it as Authorization: Bearer <key> '
                'for remote manga OCR requests.',
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
              _urlError = null;
              _keyError = null;
            });
          },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _onSave, child: const Text('Save')),
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
