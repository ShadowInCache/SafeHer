import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';

/// A rule, a mono eyebrow, and an optional action.
///
/// This is how every screen says "a new section starts here". It replaces the
/// 18-22px bold headings the app used to open sections with, which gave a
/// section *label* the same weight as the content underneath it -- so a page
/// of five sections read as ten things of equal importance.
///
/// A hairline plus a small label separates without competing. It is the same
/// device the dispatched emergency screen uses for "ALERT SENT" and the home
/// greeting uses for "GOOD MORNING", so the pattern means one thing
/// everywhere: this names what follows.
class SaSectionHeader extends StatelessWidget {
  const SaSectionHeader({
    required this.label,
    super.key,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  /// Sentence case. The widget uppercases it for display and keeps this
  /// string as the accessible name -- TalkBack and VoiceOver spell an
  /// all-caps word out letter by letter.
  final String label;

  final String? actionLabel;
  final VoidCallback? onAction;

  /// Right-hand slot for something that is not a link -- a live status, a
  /// count. Ignored when [actionLabel] is supplied; a section head has room
  /// for one thing on the right, and a tappable one wins.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: saColors.line),
        const SizedBox(height: AppSpacing.space3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                semanticsLabel: label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.eyebrow.copyWith(color: saColors.inkMuted),
              ),
            ),
            if (actionLabel != null && onAction != null)
              Semantics(
                button: true,
                label: actionLabel,
                child: GestureDetector(
                  onTap: onAction,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    actionLabel!,
                    style: AppTypography.labelM.copyWith(color: saColors.interactive),
                  ),
                ),
              )
            else if (trailing != null)
              trailing!,
          ],
        ),
      ],
    );
  }
}
