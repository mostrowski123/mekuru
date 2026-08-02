import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/manga/presentation/widgets/manga_settings_rows.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_brightness_row.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_settings_sheet_scaffold.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Quick-settings sheet for the manga reader, grouped into "Display",
/// "Reading", "Image", and "Lookup" sections — mirroring the EPUB sheet's
/// structure and using the same shared row widgets.
class MangaReaderSettingsSheet extends ConsumerWidget {
  const MangaReaderSettingsSheet({
    super.key,
    required this.hasComputedAutoCrop,
    required this.onAutoCropToggled,
    required this.onAutoCropRerun,
    required this.onUnlockPro,
    required this.onSettingChanged,
    this.onOpenAllSettings,
  });

  /// Whether this book already has computed crop bounds (enables re-run).
  final bool hasComputedAutoCrop;

  /// Called with the new value when the Pro auto-crop switch is toggled;
  /// owns the crop-computation flow.
  final ValueChanged<bool> onAutoCropToggled;

  final VoidCallback onAutoCropRerun;

  /// Called when a non-Pro user taps Unlock (after the sheet closes itself).
  final VoidCallback onUnlockPro;

  /// Telemetry callback fired once per completed setting change.
  final void Function(String setting, Object value) onSettingChanged;

  final VoidCallback? onOpenAllSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final debugOverlay = ref.watch(mangaDebugWordOverlayProvider);
    final isProUnlocked = proUnlockedValue(ref.watch(proUnlockedProvider));

    return ReaderSettingsSheetScaffold(
      title: l10n.mangaReaderSettingsTitle,
      onOpenAllSettings: onOpenAllSettings,
      allSettingsTooltip: l10n.readerAllSettingsTooltip,
      children: [
        // ── Display ──
        SettingsSectionHeader.sheet(title: l10n.readerSettingsSectionDisplay),
        ReaderBrightnessRow(onSettingChanged: onSettingChanged),
        const SizedBox(height: 8),
        MangaViewModeRow(onSettingChanged: onSettingChanged),

        // ── Reading ──
        SettingsSectionHeader.sheet(title: l10n.mangaSettingsSectionReading),
        MangaReadingDirectionRow(onSettingChanged: onSettingChanged),
        const SizedBox(height: 16),
        MangaEdgeZoneRow(onSettingChanged: onSettingChanged),
        MangaPageTurnAnimationRow(onSettingChanged: onSettingChanged),

        // ── Image ──
        SettingsSectionHeader.sheet(title: l10n.mangaSettingsSectionImage),
        if (isProUnlocked)
          SettingsSwitchRow(
            icon: Icons.crop,
            title: l10n.proFeatureAutoCropTitle,
            subtitle: l10n.mangaAutoCropSubtitle,
            value: settings.mangaAutoCrop,
            onChanged: (value) {
              onAutoCropToggled(value);
              onSettingChanged('auto_crop', value);
            },
          )
        else
          ListTile(
            enabled: false,
            leading: Icon(
              Icons.crop,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(l10n.proFeatureAutoCropTitle),
            subtitle: Text(l10n.mangaAutoCropSubtitle),
            trailing: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onUnlockPro();
              },
              child: Text(l10n.commonUnlock),
            ),
          ),
        if (isProUnlocked && settings.mangaAutoCrop && hasComputedAutoCrop)
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.mangaAutoCropRerunTitle),
            subtitle: Text(l10n.mangaAutoCropRerunSubtitle),
            onTap: () {
              AppHaptics.light();
              onAutoCropRerun();
            },
          ),

        // ── Lookup ──
        SettingsSectionHeader.sheet(title: l10n.mangaSettingsSectionLookup),
        MangaTransparentLookupRow(onSettingChanged: onSettingChanged),
        SettingsSwitchRow(
          icon: Icons.grid_on,
          title: l10n.mangaDebugWordOverlayTitle,
          subtitle: l10n.mangaDebugWordOverlaySubtitle,
          value: debugOverlay,
          onChanged: (value) {
            ref.read(mangaDebugWordOverlayProvider.notifier).setEnabled(value);
            onSettingChanged('debug_overlay', value);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
