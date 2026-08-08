import 'package:flutter/material.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

/// Segment lists and enum label/icon mappings shared by every surface that
/// renders these settings (reader sheets and the Reading settings screen) —
/// the presentation of an enum lives here, once.
List<ButtonSegment<ReaderDirection>> readerDirectionSegments(
  AppLocalizations l10n,
) {
  return [
    ButtonSegment(
      value: ReaderDirection.rtl,
      label: Text(l10n.readerReadingDirectionRtl),
    ),
    ButtonSegment(
      value: ReaderDirection.ltr,
      label: Text(l10n.readerReadingDirectionLtr),
    ),
  ];
}

List<ButtonSegment<FuriganaMode>> furiganaModeSegments(AppLocalizations l10n) {
  return [
    ButtonSegment(
      value: FuriganaMode.hide,
      label: Text(l10n.readerFuriganaOff),
      icon: const Icon(Icons.visibility_off),
    ),
    ButtonSegment(
      value: FuriganaMode.book,
      label: Text(l10n.readerFuriganaBook),
      icon: const Icon(Icons.menu_book),
    ),
    ButtonSegment(
      value: FuriganaMode.all,
      label: Text(l10n.readerFuriganaAllKanji),
      icon: const Icon(Icons.visibility),
    ),
    ButtonSegment(
      value: FuriganaMode.aboveLevel,
      label: Text(l10n.readerFuriganaAboveLevel),
      icon: const Icon(Icons.school_outlined),
    ),
  ];
}

/// N5 (easiest) → N1 (hardest); values are the numeric JLPT level used by
/// [ReaderSettings.furiganaJlptLevel].
List<ButtonSegment<int>> furiganaJlptLevelSegments() {
  return [
    for (var level = 5; level >= 1; level--)
      ButtonSegment(value: level, label: Text('N$level')),
  ];
}

List<ButtonSegment<MangaViewMode>> mangaViewModeSegments(
  AppLocalizations l10n,
) {
  return [
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
  ];
}

String colorModeLabel(AppLocalizations l10n, ColorMode mode) => switch (mode) {
  ColorMode.normal => l10n.settingsColorModeNormal,
  ColorMode.sepia => l10n.settingsColorModeSepia,
  ColorMode.dark => l10n.settingsColorModeDark,
};

IconData colorModeIcon(ColorMode mode) => switch (mode) {
  ColorMode.normal => Icons.brightness_5,
  ColorMode.sepia => Icons.filter_vintage,
  ColorMode.dark => Icons.dark_mode,
};

List<ButtonSegment<ColorMode>> colorModeSegments(AppLocalizations l10n) {
  return [
    for (final mode in ColorMode.values)
      ButtonSegment(
        value: mode,
        icon: Icon(colorModeIcon(mode)),
        label: Text(colorModeLabel(l10n, mode)),
      ),
  ];
}
