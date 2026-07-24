import 'package:flutter/material.dart';
import 'package:safeher_app/core/theme/app_theme.dart';

/// Wraps [child] in a themed MaterialApp for component/screen tests.
Widget wrapWithTheme(
  Widget child, {
  Brightness brightness = Brightness.dark,
  Size surfaceSize = const Size(400, 800),
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: MediaQueryData(size: surfaceSize),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
