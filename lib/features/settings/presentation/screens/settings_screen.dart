import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/dictionary/presentation/screens/dictionary_manager_screen.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/screens/about_screen.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// General app settings screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final lookupFontSize = ref.watch(lookupFontSizeProvider);
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
