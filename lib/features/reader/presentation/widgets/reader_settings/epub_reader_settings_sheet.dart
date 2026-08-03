import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/data/models/book_reading_config.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_brightness_row.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_setting_segments.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_settings_sheet_scaffold.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Quick-settings sheet for the EPUB reader, grouped into "This book"
/// (per-book overrides), "Display", and "Behavior" sections.
class EpubReaderSettingsSheet extends ConsumerWidget {
  const EpubReaderSettingsSheet({
    super.key,
    required this.bookLanguage,
    required this.pageProgressionDirection,
    required this.onSettingChanged,
    this.onOpenAllSettings,
  });

  /// The current book's language, used to gate vertical-text support.
  final String? bookLanguage;

  /// The current book's spine page-progression-direction, used to detect
  /// non-native display modes.
  final String? pageProgressionDirection;

  /// Telemetry callback fired once per completed setting change.
  final void Function(String setting, Object value) onSettingChanged;

  final VoidCallback? onOpenAllSettings;

  bool _isNonNativeDisplayMode(ReaderSettings settings) {
    final nativeVertical = defaultVerticalText(
      language: bookLanguage,
      pageProgressionDirection: pageProgressionDirection,
    );
    return settings.verticalText != nativeVertical;
  }

  String _nonNativeDisplayWarning(
    BuildContext context,
    ReaderSettings settings,
  ) {
    final l10n = context.l10n;
    if (settings.verticalText) {
      return l10n.readerVerticalTextNonNativeWarning;
    }
    return l10n.readerHorizontalTextNonNativeWarning;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final supportsVerticalText = bookSupportsVerticalText(bookLanguage);

    return ReaderSettingsSheetScaffold(
      title: l10n.readerQuickSettings,
      onOpenAllSettings: onOpenAllSettings,
      allSettingsTooltip: l10n.readerAllSettingsTooltip,
      children: [
        // ── This book ──
        SettingsSectionHeader.sheet(title: l10n.readerThisBook),
        SettingsSwitchRow(
          icon: Icons.text_rotation_angledown,
          title: l10n.readerVerticalTextTitle,
          subtitle: supportsVerticalText
              ? null
              : l10n.readerVerticalTextUnavailable,
          value: settings.verticalText,
          onChanged: supportsVerticalText
              ? (value) {
                  notifier.setVerticalText(value);
                  onSettingChanged('vertical_text', value);
                }
              : null,
        ),
        if (_isNonNativeDisplayMode(settings))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _nonNativeDisplayWarning(context, settings),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SettingsSegmentedRow<ReaderDirection>(
          label: l10n.readerReadingDirectionTitle,
          segments: readerDirectionSegments(l10n),
          selected: settings.readingDirection,
          onSelected: (direction) {
            notifier.setReadingDirection(direction);
            onSettingChanged('direction', direction.name);
          },
        ),
        const SizedBox(height: 16),
        SettingsSegmentedRow<FuriganaMode>(
          label: l10n.readerFuriganaTitle,
          segments: furiganaModeSegments(l10n),
          selected: settings.furiganaMode == FuriganaMode.aboveLevel
              ? FuriganaMode.all
              : settings.furiganaMode,
          onSelected: (chosen) {
            // Don't clobber a stored `aboveLevel` (which the UI displays as
            // `all`) when the user taps the already-active segment.
            if (chosen == FuriganaMode.all &&
                settings.furiganaMode == FuriganaMode.aboveLevel) {
              return;
            }
            notifier.setFuriganaMode(chosen);
            onSettingChanged('furigana_mode', chosen.name);
          },
        ),

        // ── Display ──
        SettingsSectionHeader.sheet(title: l10n.readerSettingsSectionDisplay),
        SettingsSliderRow(
          icon: Icons.text_fields,
          label: l10n.settingsFontSizeTitle,
          valueLabel: '${settings.fontSize.round()}',
          value: settings.fontSize,
          min: 12,
          max: 32,
          divisions: 20,
          onChanged: notifier.setFontSize,
          // onChangeEnd so a drag logs once, not per tick.
          onChangeEnd: (value) => onSettingChanged('font_size', value.round()),
        ),
        ReaderBrightnessRow(onSettingChanged: onSettingChanged),
        const SizedBox(height: 8),
        SettingsSegmentedRow<ColorMode>(
          segments: colorModeSegments(l10n),
          selected: settings.colorMode,
          onSelected: (mode) {
            notifier.setColorMode(mode);
            onSettingChanged('color_mode', mode.name);
          },
        ),
        if (settings.colorMode == ColorMode.sepia) ...[
          const SizedBox(height: 12),
          SettingsSliderRow(
            value: settings.sepiaIntensity,
            min: 0.0,
            max: 1.0,
            leadingSliderIcon: Icons.coffee,
            trailingSliderIcon: Icons.local_fire_department,
            onChanged: notifier.setSepiaIntensity,
            onChangeEnd: (value) =>
                onSettingChanged('sepia_intensity', (value * 100).round()),
          ),
        ],

        // ── Behavior ──
        SettingsSectionHeader.sheet(title: l10n.readerSettingsSectionBehavior),
        SettingsSwitchRow(
          icon: Icons.table_rows_outlined,
          title: l10n.readerSplitVerticalTextTitle,
          subtitle: l10n.readerSplitVerticalTextSubtitle,
          value: settings.splitVerticalText,
          onChanged: settings.verticalText
              ? (value) {
                  notifier.setSplitVerticalText(value);
                  onSettingChanged('split_vertical_text', value);
                }
              : null,
        ),
        SettingsSwitchRow(
          icon: Icons.link_off,
          title: l10n.readerDisableLinksTitle,
          subtitle: l10n.readerDisableLinksSubtitle,
          value: settings.disableLinks,
          onChanged: (value) {
            notifier.setDisableLinks(value);
            onSettingChanged('disable_links', value);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
