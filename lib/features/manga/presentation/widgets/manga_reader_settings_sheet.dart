import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/manga/presentation/providers/manga_reader_providers.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_brightness_row.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_settings_sheet_scaffold.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Section header padding matching the sheet's 24px content inset.
const _sheetSectionPadding = EdgeInsets.fromLTRB(0, 16, 0, 8);

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
    final notifier = ref.read(readerSettingsProvider.notifier);
    final debugOverlay = ref.watch(mangaDebugWordOverlayProvider);
    final isProUnlocked = proUnlockedValue(ref.watch(proUnlockedProvider));
    final pageTurnEdgeZonePercent =
        (settings.mangaPageTurnEdgeZoneWidthFraction * 100).round();

    return ReaderSettingsSheetScaffold(
      title: l10n.mangaReaderSettingsTitle,
      onOpenAllSettings: onOpenAllSettings,
      allSettingsTooltip: l10n.readerAllSettingsTooltip,
      children: [
        // ── Display ──
        SettingsSectionHeader(
          title: l10n.readerSettingsSectionDisplay,
          padding: _sheetSectionPadding,
        ),
        ReaderBrightnessRow(onSettingChanged: onSettingChanged),
        const SizedBox(height: 8),
        SettingsSegmentedRow<MangaViewMode>(
          label: l10n.mangaViewModeTitle,
          segments: [
            ButtonSegment(
              value: MangaViewMode.singlePage,
              icon: const Icon(Icons.looks_one),
              label: Text(l10n.mangaViewModeSingle),
            ),
            ButtonSegment(
              value: MangaViewMode.twoPageSpread,
              icon: const Icon(Icons.looks_two),
              label: Text(l10n.mangaViewModeSpread),
            ),
            ButtonSegment(
              value: MangaViewMode.scroll,
              icon: const Icon(Icons.view_day),
              label: Text(l10n.mangaViewModeScroll),
            ),
          ],
          selected: settings.mangaViewMode,
          onSelected: (mode) {
            notifier.setMangaViewMode(mode);
            onSettingChanged('view_mode', mode.name);
          },
        ),

        // ── Reading ──
        SettingsSectionHeader(
          title: l10n.mangaSettingsSectionReading,
          padding: _sheetSectionPadding,
        ),
        SettingsSegmentedRow<ReaderDirection>(
          label: l10n.readerReadingDirectionTitle,
          segments: [
            ButtonSegment(
              value: ReaderDirection.rtl,
              label: Text(l10n.readerReadingDirectionRtl),
            ),
            ButtonSegment(
              value: ReaderDirection.ltr,
              label: Text(l10n.readerReadingDirectionLtr),
            ),
          ],
          selected: settings.mangaReadingDirection,
          onSelected: (direction) {
            notifier.setMangaReadingDirection(direction);
            onSettingChanged('direction', direction.name);
          },
        ),
        const SizedBox(height: 16),
        SettingsSliderRow(
          icon: Icons.touch_app,
          label: l10n.mangaPageTurnEdgeZoneTitle,
          valueLabel: l10n.settingsPercentValue(
            percent: pageTurnEdgeZonePercent,
          ),
          value: settings.mangaPageTurnEdgeZoneWidthFraction,
          min: kMinMangaPageTurnEdgeZoneWidthFraction,
          max: kMaxMangaPageTurnEdgeZoneWidthFraction,
          divisions: 20,
          sliderLabel: l10n.settingsPercentValue(
            percent: pageTurnEdgeZonePercent,
          ),
          helperText: l10n.mangaPageTurnEdgeZoneSubtitle,
          onChanged: notifier.setMangaPageTurnEdgeZoneWidthFraction,
          onChangeEnd: (value) =>
              onSettingChanged('edge_zone', (value * 100).round()),
        ),

        // ── Image ──
        SettingsSectionHeader(
          title: l10n.mangaSettingsSectionImage,
          padding: _sheetSectionPadding,
        ),
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
        SettingsSectionHeader(
          title: l10n.mangaSettingsSectionLookup,
          padding: _sheetSectionPadding,
        ),
        SettingsSwitchRow(
          icon: Icons.opacity,
          title: l10n.mangaTransparentLookupTitle,
          subtitle: l10n.mangaTransparentLookupSubtitle,
          value: settings.mangaTransparentLookup,
          onChanged: (value) {
            notifier.setMangaTransparentLookup(value);
            onSettingChanged('transparent_lookup', value);
          },
        ),
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
