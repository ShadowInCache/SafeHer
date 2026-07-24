/// 4dp-base spacing scale. See design system spec §SPACING.
abstract final class AppSpacing {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;

  /// Screen horizontal margin on phones.
  static const double screenMarginPhone = 20;

  /// Screen horizontal margin on tablets.
  static const double screenMarginTablet = 32;

  /// Minimum interactive touch target, both axes.
  static const double minTouchTarget = 48;

  const AppSpacing._();
}
