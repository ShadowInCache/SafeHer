import 'package:flutter/painting.dart';

/// Border radius scale. See design system spec §BORDER RADIUS.
abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xl2 = 24;
  static const double xl3 = 32;
  static const double full = 9999;

  static BorderRadius get xsRadius => BorderRadius.circular(xs);
  static BorderRadius get smRadius => BorderRadius.circular(sm);
  static BorderRadius get mdRadius => BorderRadius.circular(md);
  static BorderRadius get lgRadius => BorderRadius.circular(lg);
  static BorderRadius get xlRadius => BorderRadius.circular(xl);
  static BorderRadius get xl2Radius => BorderRadius.circular(xl2);
  static BorderRadius get xl3Radius => BorderRadius.circular(xl3);
  static BorderRadius get fullRadius => BorderRadius.circular(full);

  const AppRadius._();
}
