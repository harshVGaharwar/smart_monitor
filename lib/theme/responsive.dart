import 'package:flutter/material.dart';

/// Breakpoint-based helpers driven by [MediaQuery], so layouts adapt to the
/// actual device size instead of relying on hard-coded dimensions.
extension Responsive on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;

  /// Phones / very narrow windows — sidebar moves into a drawer.
  bool get isMobile => screenWidth < 720;

  /// Tablets / small laptops — sidebar shown as an icon rail.
  bool get isTablet => screenWidth >= 720 && screenWidth < 1100;

  bool get isDesktop => screenWidth >= 1100;

  /// Outer padding around page content, scaled to the viewport.
  double get gutter => isMobile ? 14 : (isTablet ? 20 : 15);

  /// Clamp a value between a min and max fraction of the screen width,
  /// useful for giving fields a flexible but bounded width.
  double widthClamp(double fraction, double min, double max) =>
      (screenWidth * fraction).clamp(min, max);
}
