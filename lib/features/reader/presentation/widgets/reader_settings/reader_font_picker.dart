import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/data/models/reader_settings.dart';
import 'package:mekuru/features/reader/data/services/user_font_store.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/features/reader/presentation/providers/user_font_providers.dart';
import 'package:mekuru/features/reader/presentation/widgets/reader_settings/reader_setting_segments.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// What shows as chosen: an added font only while its file is there, else
/// the book's own fonts (which is what the reader then shows).
({ReaderFontFamily family, UserFont? font}) selectedReaderFont(
  ReaderSettings settings,
  List<UserFont> fonts,
) {
  if (settings.fontFamily != ReaderFontFamily.custom) {
    return (family: settings.fontFamily, font: null);
  }
  for (final font in fonts) {
    if (font.fileName == settings.customFontFile) {
      return (family: ReaderFontFamily.custom, font: font);
    }
  }
  return (family: ReaderFontFamily.book, font: null);
}

String readerFontChoiceLabel(
  AppLocalizations l10n,
  ReaderSettings settings,
  List<UserFont> fonts,
) {
  final selected = selectedReaderFont(settings, fonts);
  return selected.font?.displayName ??
      readerFontFamilyLabel(l10n, selected.family);
}

/// The fonts Mekuru offers, the user's added fonts (each removable) and
/// "Add font…". Shared by the EPUB quick-settings sheet and Settings →
/// Reading.
Future<void> showReaderFontPicker(
  BuildContext context, {
  void Function(String setting, Object value)? onSettingChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReaderFontPickerSheet(onSettingChanged: onSettingChanged),
  );
}

class _ReaderFontPickerSheet extends ConsumerWidget {
  const _ReaderFontPickerSheet({this.onSettingChanged});

  final void Function(String setting, Object value)? onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final fonts = ref.watch(userFontsProvider).value ?? const <UserFont>[];
    final selected = selectedReaderFont(settings, fonts);
    final check = Icon(Icons.check, color: theme.colorScheme.primary);
    final notifier = ref.read(readerSettingsProvider.notifier);

    void choose(void Function() apply) {
      AppHaptics.medium();
      apply();
      onSettingChanged?.call(
        'font_family',
        ref.read(readerSettingsProvider).fontFamily.name,
      );
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.settingsFontFamilyTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final family in builtInReaderFontFamilies)
                  ListTile(
                    title: Text(readerFontFamilyLabel(l10n, family)),
                    trailing: selected.font == null && selected.family == family
                        ? check
                        : null,
                    onTap: () => choose(() => notifier.setFontFamily(family)),
                  ),
                for (final font in fonts)
                  ListTile(
                    title: Text(font.displayName),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected.font == font) check,
                        IconButton(
                          tooltip: l10n.settingsFontRemoveTooltip,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(context, font),
                        ),
                      ],
                    ),
                    onTap: () =>
                        choose(() => notifier.setCustomFont(font.fileName)),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l10n.settingsFontAdd),
                  onTap: () => _add(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    // Read before the picker opens: on Android it answers only once it has
    // copied the file, and the sheet is closed by then.
    final container = ProviderScope.containerOf(context, listen: false);
    final l10n = context.l10n;
    final path = await container.read(userFontFilePickerProvider)();
    if (path == null) return;

    String? error;
    try {
      final font = await container.read(userFontStoreProvider).import(path);
      container.invalidate(userFontsProvider);
      container
          .read(readerSettingsProvider.notifier)
          .setCustomFont(font.fileName);
      onSettingChanged?.call('font_family', ReaderFontFamily.custom.name);
    } on UserFontImportException catch (e) {
      error = switch (e.error) {
        UserFontImportError.notAFont => l10n.settingsFontAddNotAFont,
        UserFontImportError.collection => l10n.settingsFontAddCollection,
        UserFontImportError.tooLarge => l10n.settingsFontAddTooLarge,
      };
    } on FileSystemException {
      error = l10n.settingsFontAddFailed;
    }
    if (!context.mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    // A dialog, not a snack bar: in the reader this sheet sits on the
    // quick-settings sheet, which would cover one.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(error!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, UserFont font) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsFontRemoveTitle),
        content: Text(l10n.settingsFontRemoveBody(name: font.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Stop naming the font before its file goes.
    final settings = container.read(readerSettingsProvider);
    if (settings.fontFamily == ReaderFontFamily.custom &&
        settings.customFontFile == font.fileName) {
      container
          .read(readerSettingsProvider.notifier)
          .setFontFamily(ReaderFontFamily.book);
    }
    await container.read(userFontStoreProvider).delete(font.fileName);
    container.invalidate(userFontsProvider);
  }
}
