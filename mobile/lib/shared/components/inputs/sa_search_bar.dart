import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../buttons/sa_icon_button.dart';
import '../icons/sa_icon.dart';

/// Pill-shaped search field. The trailing icon morphs between mic (empty)
/// and clear/search (has text). Voice input itself is a screen-level
/// concern — [onMicTap] is the hook the Search screen uses to open its
/// full-screen voice overlay.
class SaSearchBar extends StatefulWidget {
  const SaSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onMicTap,
    this.hintText = 'Search',
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onMicTap;
  final String hintText;
  final bool autofocus;

  @override
  State<SaSearchBar> createState() => _SaSearchBarState();
}

class _SaSearchBarState extends State<SaSearchBar> {
  late final TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_handleTextChange);
  }

  void _handleTextChange() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Semantics(
      label: 'Search',
      textField: true,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
        decoration: BoxDecoration(
          color: saColors.surfaceElevated,
          borderRadius: AppRadius.fullRadius,
          border: Border.all(color: saColors.glassBorder),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.space2),
            const SaIcon(SaIconGlyph.search, size: 18),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: widget.autofocus,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                style: AppTypography.bodyL.copyWith(color: onSurface),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: _hasText
                  ? SaIconButton(
                      key: const ValueKey('clear'),
                      icon: const SaIcon(SaIconGlyph.close, size: 16),
                      semanticsLabel: 'Clear search',
                      size: SaIconButtonSize.small,
                      onPressed: () => _controller.clear(),
                    )
                  : SaIconButton(
                      key: const ValueKey('mic'),
                      icon: const SaIcon(SaIconGlyph.mic, size: 18),
                      semanticsLabel: 'Voice search',
                      size: SaIconButtonSize.small,
                      onPressed: widget.onMicTap,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
