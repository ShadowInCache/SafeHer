import 'package:flutter/material.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

/// Wraps [child] in a themed MaterialApp for component/screen tests.
Widget wrapWithTheme(
  Widget child, {
  Brightness brightness = Brightness.dark,
  Size surfaceSize = const Size(400, 800),
}) {
  return MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: MediaQueryData(size: surfaceSize),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
