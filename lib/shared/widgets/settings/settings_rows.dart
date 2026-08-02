import 'package:flutter/material.dart';
import 'package:mekuru/shared/utils/haptics.dart';

/// Section header shared by the settings screens and reader settings sheets.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
  });

  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
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

/// A slider with an optional label row above it, optional icons flanking the
/// track, and optional helper text below. Fires a light haptic per change.
class SettingsSliderRow extends StatelessWidget {
  const SettingsSliderRow({
    super.key,
    this.icon,
    this.label,
    this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.sliderLabel,
    this.leadingSliderIcon,
    this.trailingSliderIcon,
    this.helperText,
    this.trailing,
    required this.onChanged,
    this.onChangeEnd,
  });

  /// Icon shown before [label] in the label row.
  final IconData? icon;

  /// Optional label row text; omit for a bare slider row.
  final String? label;

  /// Current value rendered at the end of the label row.
  final String? valueLabel;

  final double value;
  final double min;
  final double max;
  final int? divisions;

  /// Label shown on the slider thumb while dragging.
  final String? sliderLabel;

  /// Icons flanking the slider track (e.g. brightness low/high).
  final IconData? leadingSliderIcon;
  final IconData? trailingSliderIcon;

  /// Explanatory text below the slider.
  final String? helperText;

  /// Widget after the slider track (e.g. a follow-system button).
  final Widget? trailing;

  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slider = Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: sliderLabel,
      onChanged: (newValue) {
        AppHaptics.light();
        onChanged(newValue);
      },
      onChangeEnd: onChangeEnd,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Row(
            children: [
              if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
              Text(label!),
              const Spacer(),
              if (valueLabel != null) Text(valueLabel!),
            ],
          ),
        if (leadingSliderIcon != null ||
            trailingSliderIcon != null ||
            trailing != null)
          Row(
            children: [
              if (leadingSliderIcon != null) Icon(leadingSliderIcon),
              Expanded(child: slider),
              if (trailingSliderIcon != null) Icon(trailingSliderIcon),
              ?trailing,
            ],
          )
        else
          slider,
        if (helperText != null)
          Text(
            helperText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// A full-width segmented control with an optional label above and helper
/// text below. Fires a medium haptic per selection.
class SettingsSegmentedRow<T> extends StatelessWidget {
  const SettingsSegmentedRow({
    super.key,
    this.label,
    this.helperText,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.showSelectedIcon = false,
  });

  final String? label;
  final String? helperText;
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool showSelectedIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(label!, style: theme.textTheme.titleMedium),
          ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            segments: segments,
            selected: {selected},
            showSelectedIcon: showSelectedIcon,
            onSelectionChanged: (selection) {
              AppHaptics.medium();
              onSelected(selection.first);
            },
          ),
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A [SwitchListTile] that fires a medium haptic on toggle. Pass a null
/// [onChanged] to render it disabled.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final callback = onChanged;
    return SwitchListTile(
      secondary: icon != null ? Icon(icon) : null,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: callback == null
          ? null
          : (newValue) {
              AppHaptics.medium();
              callback(newValue);
            },
    );
  }
}
