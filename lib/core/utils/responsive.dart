import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Responsive utility class for handling different screen sizes
class Responsive {
  /// Get screen width
  static double width(BuildContext context) => MediaQuery.of(context).size.width;
  
  /// Get screen height
  static double height(BuildContext context) => MediaQuery.of(context).size.height;

  /// Fraction of screen width (0.0–1.0), e.g. `pctWidth(context, 0.9)` → 90% width.
  static double pctWidth(BuildContext context, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    return width(context) * f;
  }

  /// Fraction of screen height (0.0–1.0).
  static double pctHeight(BuildContext context, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    return height(context) * f;
  }

  /// Size from shorter side (stable on rotation); good for icons and tiles.
  static double pctShortestSide(BuildContext context, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    final s = MediaQuery.of(context).size.shortestSide;
    return s * f;
  }
  
  /// Check if screen is mobile (< 600)
  static bool isMobile(BuildContext context) => width(context) < 600;
  
  /// Check if screen is tablet (600 - 1200)
  static bool isTablet(BuildContext context) => width(context) >= 600 && width(context) < 1200;
  
  /// Check if screen is desktop (> 1200)
  static bool isDesktop(BuildContext context) => width(context) >= 1200;
  
  /// Get responsive padding
  static EdgeInsets padding(BuildContext context) {
    if (isDesktop(context)) {
      return EdgeInsets.symmetric(horizontal: 40.w, vertical: 20.h);
    } else if (isTablet(context)) {
      return EdgeInsets.symmetric(horizontal: 30.w, vertical: 16.h);
    } else {
      return EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h);
    }
  }
  
  /// Get responsive font size
  static double fontSize(BuildContext context, double baseSize) {
    if (isDesktop(context)) {
      return baseSize * 1.2;
    } else if (isTablet(context)) {
      return baseSize * 1.1;
    } else {
      return baseSize;
    }
  }
  
  /// Get responsive column count for grids
  static int gridColumns(BuildContext context) {
    if (isDesktop(context)) {
      return 4;
    } else if (isTablet(context)) {
      return 3;
    } else {
      return 2;
    }
  }
}
