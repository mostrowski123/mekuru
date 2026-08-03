import 'package:flutter/material.dart';
import 'package:mekuru/shared/utils/system_gesture_padding.dart';

/// Bottom seek bar shared by the EPUB and manga readers: a black-to-
/// transparent gradient strip with a position label and a slider that
/// follows the reading direction.
///
/// Owns the drag state so per-tick updates rebuild only this bar — never the
/// reader tree behind it — and so position updates arriving mid-drag (page
/// relocations, animations) can't yank the thumb away from the finger.
/// [onChanged] still fires per change for live page preview; [value] is the
/// authoritative position shown whenever the user is not dragging.
class ReaderSeekBar extends StatefulWidget {
  const ReaderSeekBar({
    super.key,
    required this.value,
    required this.isRtl,
    required this.leadingLabel,
    this.trailingLabel,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.onChanged,
    this.onChangeEnd,
  });

  /// Current position when the user is not dragging.
  final double value;

  /// Mirrors the slider so progress runs right-to-left for RTL books.
  final bool isRtl;

  /// Builds the label before the slider from the displayed position (the
  /// drag position while dragging, [value] otherwise).
  final String Function(double value) leadingLabel;

  /// Static label after the slider (e.g. the manga page total).
  final String? trailingLabel;

  final double min;
  final double max;
  final int? divisions;

  /// Both null disables the slider.
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<ReaderSeekBar> createState() => _ReaderSeekBarState();
}

class _ReaderSeekBarState extends State<ReaderSeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = bottomControlPadding(MediaQuery.of(context));
    final enabled = widget.onChanged != null || widget.onChangeEnd != null;
    final shown = (_dragValue ?? widget.value).clamp(widget.min, widget.max);
    const labelStyle = TextStyle(color: Colors.white, fontSize: 14);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
          child: Row(
            children: [
              Text(widget.leadingLabel(shown), style: labelStyle),
              Expanded(
                child: Directionality(
                  textDirection: widget.isRtl
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Slider(
                    value: shown,
                    min: widget.min,
                    max: widget.max,
                    divisions: widget.divisions,
                    onChanged: enabled
                        ? (value) {
                            setState(() => _dragValue = value);
                            widget.onChanged?.call(value);
                          }
                        : null,
                    onChangeEnd: enabled
                        ? (value) {
                            setState(() => _dragValue = null);
                            widget.onChangeEnd?.call(value);
                          }
                        : null,
                  ),
                ),
              ),
              if (widget.trailingLabel != null)
                Text(widget.trailingLabel!, style: labelStyle),
            ],
          ),
        ),
      ),
    );
  }
}
