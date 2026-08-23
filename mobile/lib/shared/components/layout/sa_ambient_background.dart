import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';

/// Paints the ground behind every screen.
///
/// This used to be an aurora field: four overlapping radial gradients in
/// violet and rose, there so that glassmorphic cards would have a light source
/// to refract. That was the right widget for the old direction and the wrong
/// one for this: the palette is warm stone and ink, hierarchy now comes from
/// hairlines and space rather than from depth, and a violet wash behind it
/// fought every semantic colour on the page -- a green "safe" dot and an ochre
/// "caution" label both picked up the same cast.
///
/// It stays a widget rather than folding into `scaffoldBackgroundColor`
/// because `AppTheme` deliberately leaves the scaffold transparent and mounts
/// this above the router in `main.dart`, so one ground covers every route
/// including the gaps between them. The public API is unchanged.
class SaAmbientBackground extends StatelessWidget {
  const SaAmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Read through the extension when it is there, and fall back to the raw
    // token otherwise. The old painter only needed `Theme.of(context)
    // .brightness`, which is always present, so it could not throw however it
    // was mounted; a bare `context.saColors` here would swap that for a null
    // assertion on any host that forgot the extension. Not worth the risk for
    // the widget that paints every screen's ground.
    final theme = Theme.of(context);
    final ground =
        theme.extension<SafeHerColors>()?.surfaceBase ??
        (theme.brightness == Brightness.dark ? AppColors.dark900 : AppColors.light50);

    return DecoratedBox(decoration: BoxDecoration(color: ground), child: child);
  }
}
