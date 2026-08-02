import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/firebase_runtime.dart';
import 'package:mekuru/features/manga/data/services/ocr_auth_secret_storage.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/features/settings/presentation/widgets/ocr_server_url_dialog.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Reading defaults for both readers, sectioned into settings shared by all
/// books, EPUB-only, and manga-only. Binds the same providers as the
/// in-reader quick-settings sheets — one source of truth, two surfaces.
class ReadingSettingsScreen extends ConsumerStatefulWidget {
  const ReadingSettingsScreen({super.key});

  @override
  ConsumerState<ReadingSettingsScreen> createState() =>
      _ReadingSettingsScreenState();
}

class _ReadingSettingsScreenState extends ConsumerState<ReadingSettingsScreen> {
  final OcrAuthSecretStorage _ocrAuthSecretStorage = OcrAuthSecretStorage();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final autoCropWhiteThreshold = ref.watch(autoCropWhiteThresholdProvider);
    final isProUnlocked = proUnlockedValue(ref.watch(proUnlockedProvider));
    final hasFirebaseApp = FirebaseRuntime.instance.hasFirebaseApp;
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsReadingTitle)),
      body: ListView(
        children: [
          // ── All books ──
          SettingsSectionHeader(title: l10n.settingsReadingSectionShared),
          ListTile(
            leading: Icon(Icons.text_fields, color: theme.colorScheme.primary),
            title: Text(l10n.settingsFontSizeTitle),
            subtitle: Text(
              l10n.settingsPointsValue(points: settings.fontSize.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SettingsSliderRow(
              value: settings.fontSize,
              min: 12,
              max: 32,
              divisions: 20,
              sliderLabel: settings.fontSize.round().toString(),
              onChanged: notifier.setFontSize,
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.color_lens_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.settingsColorModeTitle),
            subtitle: Text(_colorModeLabel(l10n, settings.colorMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppHaptics.light();
              _showColorModePicker(context, ref, settings.colorMode);
            },
          ),
          if (settings.colorMode == ColorMode.sepia)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SettingsSliderRow(
                icon: Icons.coffee,
                label: l10n.settingsSepiaIntensityTitle,
                value: settings.sepiaIntensity,
                min: 0.0,
                max: 1.0,
                onChanged: notifier.setSepiaIntensity,
              ),
            ),
          SettingsSwitchRow(
            icon: Icons.lightbulb_outline,
            title: l10n.settingsKeepScreenOnTitle,
            subtitle: l10n.settingsKeepScreenOnSubtitle,
            value: settings.keepScreenOn,
            onChanged: notifier.setKeepScreenOn,
          ),
          const Divider(),

          // ── EPUB ──
          SettingsSectionHeader(title: l10n.settingsReadingSectionEpub),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsSliderRow(
                  label: l10n.settingsHorizontalMarginValue(
                    pixels: settings.horizontalPadding,
                  ),
                  value: settings.horizontalPadding.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (value) =>
                      notifier.setHorizontalPadding(value.round()),
                ),
                SettingsSliderRow(
                  label: l10n.settingsVerticalMarginValue(
                    pixels: settings.verticalPadding,
                  ),
                  value: settings.verticalPadding.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (value) =>
                      notifier.setVerticalPadding(value.round()),
                ),
                SettingsSliderRow(
                  icon: Icons.swipe,
                  label: l10n.settingsSwipeSensitivityTitle,
                  valueLabel: l10n.settingsPercentValue(
                    percent: (settings.swipeSensitivity * 100).round(),
                  ),
                  value: settings.swipeSensitivity,
                  min: 0.01,
                  max: 0.20,
                  divisions: 19,
                  sliderLabel: l10n.settingsPercentValue(
                    percent: (settings.swipeSensitivity * 100).round(),
                  ),
                  helperText: l10n.settingsSwipeSensitivityHint,
                  onChanged: notifier.setSwipeSensitivity,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SettingsSwitchRow(
            icon: Icons.table_rows_outlined,
            title: l10n.readerSplitVerticalTextTitle,
            subtitle: l10n.readerSplitVerticalTextSubtitle,
            value: settings.splitVerticalText,
            onChanged: notifier.setSplitVerticalText,
          ),
          SettingsSwitchRow(
            icon: Icons.link_off,
            title: l10n.readerDisableLinksTitle,
            subtitle: l10n.readerDisableLinksSubtitle,
            value: settings.disableLinks,
            onChanged: notifier.setDisableLinks,
          ),
          const Divider(),

          // ── Manga ──
          SettingsSectionHeader(title: l10n.settingsReadingSectionManga),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  onSelected: notifier.setMangaViewMode,
                ),
                const SizedBox(height: 16),
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
                  onSelected: notifier.setMangaReadingDirection,
                ),
                const SizedBox(height: 16),
                SettingsSliderRow(
                  icon: Icons.touch_app,
                  label: l10n.mangaPageTurnEdgeZoneTitle,
                  valueLabel: l10n.settingsPercentValue(
                    percent: (settings.mangaPageTurnEdgeZoneWidthFraction * 100)
                        .round(),
                  ),
                  value: settings.mangaPageTurnEdgeZoneWidthFraction,
                  min: kMinMangaPageTurnEdgeZoneWidthFraction,
                  max: kMaxMangaPageTurnEdgeZoneWidthFraction,
                  divisions: 20,
                  helperText: l10n.mangaPageTurnEdgeZoneSubtitle,
                  onChanged: notifier.setMangaPageTurnEdgeZoneWidthFraction,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SettingsSwitchRow(
            icon: Icons.opacity,
            title: l10n.mangaTransparentLookupTitle,
            subtitle: l10n.mangaTransparentLookupSubtitle,
            value: settings.mangaTransparentLookup,
            onChanged: notifier.setMangaTransparentLookup,
          ),
          if (isProUnlocked) ...[
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
              child: SettingsSliderRow(
                value: autoCropWhiteThreshold.toDouble(),
                min: AutoCropWhiteThresholdNotifier.minThreshold.toDouble(),
                max: AutoCropWhiteThresholdNotifier.maxThreshold.toDouble(),
                divisions:
                    AutoCropWhiteThresholdNotifier.maxThreshold -
                    AutoCropWhiteThresholdNotifier.minThreshold,
                sliderLabel: '$autoCropWhiteThreshold',
                onChanged: (value) {
                  ref
                      .read(autoCropWhiteThresholdProvider.notifier)
                      .setThreshold(value);
                },
              ),
            ),
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
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

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

  Future<void> _showOcrServerUrlDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final savedCustomBearerKey =
        await _ocrAuthSecretStorage.loadCustomServerBearerKey() ?? '';
    final currentUrl = ref.read(ocrServerUrlProvider);
    final initialUrl =
        ocr_server_config.isUnsetOrBuiltInOcrServerUrl(currentUrl)
        ? ''
        : currentUrl;

    if (!context.mounted) return;

    final result = await showDialog<({String url, String? bearerKey})>(
      context: context,
      builder: (_) => OcrServerUrlDialog(
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
