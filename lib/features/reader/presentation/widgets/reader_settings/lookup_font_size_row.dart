import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// The dictionary popup's text size (furigana scales with it), offered in the
/// readers' quick settings as well as on the Settings screen.
class LookupFontSizeRow extends ConsumerWidget {
  const LookupFontSizeRow({super.key, required this.onSettingChanged});

  /// Telemetry callback fired once per completed change.
  final void Function(String setting, Object value) onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(lookupFontSizeProvider);

    return SettingsSliderRow(
      icon: Icons.manage_search,
      label: context.l10n.settingsLookupFontSizeTitle,
      valueLabel: '${size.round()}',
      value: size,
      min: LookupFontSizeNotifier.minSize,
      max: LookupFontSizeNotifier.maxSize,
      divisions: LookupFontSizeNotifier.divisions,
      onChanged: ref.read(lookupFontSizeProvider.notifier).setFontSize,
      onChangeEnd: (value) =>
          onSettingChanged('lookup_font_size', value.round()),
    );
  }
}
