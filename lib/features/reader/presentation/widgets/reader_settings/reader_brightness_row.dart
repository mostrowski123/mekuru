import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/features/reader/presentation/providers/reader_providers.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';

/// Brightness slider row shared by the EPUB and manga quick-settings sheets:
/// drag to override the screen brightness, or tap the trailing auto button to
/// follow the system brightness again.
class ReaderBrightnessRow extends ConsumerWidget {
  const ReaderBrightnessRow({super.key, required this.onSettingChanged});

  /// Telemetry callback fired once per completed change.
  final void Function(String setting, Object value) onSettingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = ref.watch(readerBrightnessProvider);
    final brightnessNotifier = ref.read(readerBrightnessProvider.notifier);

    return SettingsSliderRow(
      icon: Icons.brightness_6_outlined,
      label: l10n.readerBrightnessTitle,
      value: brightness.sliderValue,
      min: 0.0,
      max: 1.0,
      leadingSliderIcon: Icons.brightness_low,
      trailingSliderIcon: Icons.brightness_high,
      trailing: IconButton(
        tooltip: l10n.readerBrightnessFollowSystem,
        icon: Icon(
          Icons.brightness_auto,
          color: brightness.followsSystem ? theme.colorScheme.primary : null,
        ),
        onPressed: () {
          AppHaptics.light();
          brightnessNotifier.followSystemBrightness();
          onSettingChanged('brightness', 'system');
        },
      ),
      onChanged: brightnessNotifier.setBrightness,
      onChangeEnd: (value) =>
          onSettingChanged('brightness', (value * 100).round()),
    );
  }
}
