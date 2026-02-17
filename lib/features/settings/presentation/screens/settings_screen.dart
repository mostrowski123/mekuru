import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/ankidroid/presentation/screens/ankidroid_settings_screen.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/providers/jpdb_freq_providers.dart';
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);
    final startupScreen = ref.watch(startupScreenProvider);
    final lookupFontSize = ref.watch(lookupFontSizeProvider);
    final kanjiVgState = ref.watch(kanjiVgProvider);
    final jpdbFreqState = ref.watch(jpdbFreqProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
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
                const Text('Open keyboard when dictionary page is loaded'),
            value: ref.watch(autoFocusSearchProvider),
            onChanged: (value) {
              AppHaptics.light();
              ref
                  .read(autoFocusSearchProvider.notifier)
                  .setAutoFocus(value);
            },
          ),
          const Divider(),

          // ── AnkiDroid (Android only) ──
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            _SectionHeader(title: 'AnkiDroid'),
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

          // ── Assets ──
          _SectionHeader(title: 'Assets'),

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
          const Divider(),

          // ── Feedback ──
          _SectionHeader(title: 'Feedback'),
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
          const Divider(),

          // ── About ──
          _SectionHeader(title: 'About'),
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
