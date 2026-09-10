import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_setting_segments.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Provider-bound manga setting controls shared by the manga quick-settings
/// sheet and the Reading settings screen (same pattern as
/// `ReaderBrightnessRow`). [onSettingChanged] is the optional telemetry
/// callback used by the in-reader sheet.

class MangaViewModeRow extends ConsumerWidget {
  const MangaViewModeRow({super.key, this.onSettingChanged});

  final void Function(String setting, Object value)? onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewMode = ref.watch(
      readerSettingsProvider.select((s) => s.mangaViewMode),
    );
    return SettingsSegmentedRow<MangaViewMode>(
      label: l10n.mangaViewModeTitle,
      segments: mangaViewModeSegments(l10n),
      selected: viewMode,
      onSelected: (mode) {
        ref.read(readerSettingsProvider.notifier).setMangaViewMode(mode);
        onSettingChanged?.call('view_mode', mode.name);
      },
    );
  }
}

class MangaReadingDirectionRow extends ConsumerWidget {
  const MangaReadingDirectionRow({super.key, this.onSettingChanged});

  final void Function(String setting, Object value)? onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final direction = ref.watch(
      readerSettingsProvider.select((s) => s.mangaReadingDirection),
    );
    return SettingsSegmentedRow<ReaderDirection>(
      label: l10n.readerReadingDirectionTitle,
      segments: readerDirectionSegments(l10n),
      selected: direction,
      onSelected: (direction) {
        ref
            .read(readerSettingsProvider.notifier)
            .setMangaReadingDirection(direction);
        onSettingChanged?.call('direction', direction.name);
      },
    );
  }
}

class MangaEdgeZoneRow extends ConsumerWidget {
  const MangaEdgeZoneRow({super.key, this.onSettingChanged});

  final void Function(String setting, Object value)? onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final edgeZoneWidthFraction = ref.watch(
      readerSettingsProvider.select(
        (s) => s.mangaPageTurnEdgeZoneWidthFraction,
      ),
    );
    final percentLabel = l10n.settingsPercentValue(
      percent: (edgeZoneWidthFraction * 100).round(),
    );
    return SettingsSliderRow(
      icon: Icons.touch_app,
      label: l10n.mangaPageTurnEdgeZoneTitle,
      valueLabel: percentLabel,
      value: edgeZoneWidthFraction,
      min: kMinMangaPageTurnEdgeZoneWidthFraction,
      max: kMaxMangaPageTurnEdgeZoneWidthFraction,
      divisions: 20,
      helperText: l10n.mangaPageTurnEdgeZoneSubtitle,
      onChanged: ref
          .read(readerSettingsProvider.notifier)
          .setMangaPageTurnEdgeZoneWidthFraction,
      onChangeEnd: (value) =>
          onSettingChanged?.call('edge_zone', (value * 100).round()),
    );
  }
}

class MangaTransparentLookupRow extends ConsumerWidget {
  const MangaTransparentLookupRow({super.key, this.onSettingChanged});

  final void Function(String setting, Object value)? onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final transparent = ref.watch(
      readerSettingsProvider.select((s) => s.mangaTransparentLookup),
    );
    return SettingsSwitchRow(
      icon: Icons.opacity,
      title: l10n.mangaTransparentLookupTitle,
      subtitle: l10n.mangaTransparentLookupSubtitle,
      value: transparent,
      onChanged: (value) {
        ref
            .read(readerSettingsProvider.notifier)
            .setMangaTransparentLookup(value);
        onSettingChanged?.call('transparent_lookup', value);
      },
    );
  }
}
