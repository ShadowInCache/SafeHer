import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'sa_bottom_sheet.dart';

class SaActionSheetItem {
  const SaActionSheetItem({required this.label, required this.onTap, this.icon, this.isDestructive = false});

  final String label;
  final VoidCallback onTap;
  final Widget? icon;
  final bool isDestructive;
}

/// Bottom-sheet list of actions, revealed with the standard modal-sheet
/// animation via [showSaActionSheet].
class SaActionSheetContent extends StatelessWidget {
  const SaActionSheetContent({required this.items, super.key, this.title});

  final List<SaActionSheetItem> items;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: AppTypography.headingS.copyWith(color: onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: AppSpacing.space3),
        ],
        for (final item in items)
          Semantics(
            label: item.label,
            button: true,
            child: InkWell(
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
                child: Row(
                  children: [
                    if (item.icon != null) ...[
                      IconTheme(
                        data: IconThemeData(color: item.isDestructive ? AppColors.coral500 : onSurface),
                        child: item.icon!,
                      ),
                      const SizedBox(width: AppSpacing.space3),
                    ],
                    Text(
                      item.label,
                      style: AppTypography.bodyL.copyWith(
                        color: item.isDestructive ? AppColors.coral500 : onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showSaActionSheet(BuildContext context, {required List<SaActionSheetItem> items, String? title}) {
  return showSaBottomSheet<void>(
    context,
    isScrollControlled: false,
    builder: (ctx) => SaActionSheetContent(items: items, title: title),
  );
}
