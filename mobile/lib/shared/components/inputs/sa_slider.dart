import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';

/// Styled slider whose thumb grows slightly while being dragged.
class SaSlider extends StatefulWidget {
  const SaSlider({
    required this.value,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.semanticsLabel,
    this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? semanticsLabel;

  @override
  State<SaSlider> createState() => _SaSliderState();
}

class _SaSliderState extends State<SaSlider> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return Semantics(
      label: widget.semanticsLabel,
      slider: true,
      child: SliderTheme(
        data: SliderThemeData(
          activeTrackColor: AppColors.violet500,
          inactiveTrackColor: saColors.surfaceHighest,
          thumbColor: AppColors.violet500,
          overlayColor: AppColors.violet500.withValues(alpha: 0.15),
          trackHeight: 4,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: _dragging ? 12 : 9),
        ),
        child: Slider(
          value: widget.value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          onChangeStart: (_) => setState(() => _dragging = true),
          onChangeEnd: (v) {
            setState(() => _dragging = false);
            widget.onChangeEnd?.call(v);
          },
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
