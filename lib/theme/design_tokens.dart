import 'package:flutter/material.dart';

/// Design tokens for consistent spacing, dimensions, and styling throughout the app.
///
/// Usage:
/// ```dart
/// Padding(padding: Spacing.paddingAll16)
/// SizedBox(height: Spacing.md)
/// BorderRadius.circular(Radii.md)
/// ```
class Spacing {
  Spacing._();

  // Base spacing scale (follows 4px grid)
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  // Pre-built EdgeInsets for common padding patterns
  static const EdgeInsets paddingAll4 = EdgeInsets.all(xs);
  static const EdgeInsets paddingAll8 = EdgeInsets.all(sm);
  static const EdgeInsets paddingAll12 = EdgeInsets.all(md);
  static const EdgeInsets paddingAll16 = EdgeInsets.all(lg);
  static const EdgeInsets paddingAll24 = EdgeInsets.all(xl);
  static const EdgeInsets paddingAll32 = EdgeInsets.all(xxl);

  // Horizontal padding
  static const EdgeInsets paddingH8 = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingH12 = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingH16 = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingH24 = EdgeInsets.symmetric(horizontal: xl);

  // Vertical padding
  static const EdgeInsets paddingV8 = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingV12 = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingV16 = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets paddingV24 = EdgeInsets.symmetric(vertical: xl);

  // Pre-built SizedBox widgets for gaps
  static const SizedBox vGap4 = SizedBox(height: xs);
  static const SizedBox vGap8 = SizedBox(height: sm);
  static const SizedBox vGap12 = SizedBox(height: md);
  static const SizedBox vGap16 = SizedBox(height: lg);
  static const SizedBox vGap24 = SizedBox(height: xl);
  static const SizedBox vGap32 = SizedBox(height: xxl);

  static const SizedBox hGap4 = SizedBox(width: xs);
  static const SizedBox hGap8 = SizedBox(width: sm);
  static const SizedBox hGap12 = SizedBox(width: md);
  static const SizedBox hGap16 = SizedBox(width: lg);
}

/// Border radius tokens
class Radii {
  Radii._();

  static const double xs = 2.0;
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double xl = 16.0;
  static const double xxl = 24.0;
  static const double pill = 999.0;

  // Pre-built BorderRadius for common patterns
  static final BorderRadius borderRadiusSm = BorderRadius.circular(sm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(md);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(lg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(xl);
  static final BorderRadius borderRadiusXxl = BorderRadius.circular(xxl);
}

/// Icon size tokens
class IconSizes {
  IconSizes._();

  static const double xs = 16.0;
  static const double sm = 20.0;
  static const double md = 24.0;
  static const double lg = 32.0;
  static const double xl = 48.0;
  static const double xxl = 64.0;
  static const double xxxl = 80.0;
}

/// Common dimension tokens
class Dimensions {
  Dimensions._();

  // Album art / thumbnail sizes
  static const double thumbnailSm = 48.0;
  static const double thumbnailMd = 80.0;
  static const double thumbnailLg = 128.0;
  static const double thumbnailXl = 200.0;

  // Avatar sizes
  static const double avatarSm = 32.0;
  static const double avatarMd = 48.0;
  static const double avatarLg = 64.0;

  // List tile heights
  static const double listTileHeight = 56.0;
  static const double listTileHeightDense = 48.0;

  // Mini player height
  static const double miniPlayerHeight = 64.0;

  // App bar heights
  static const double appBarHeight = 56.0;
  static const double expandedAppBarHeight = 200.0;
}

/// Duration tokens for animations
class Durations {
  Durations._();

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
}

/// Button size tokens
class ButtonSizes {
  ButtonSizes._();

  // Touch target sizes (Material Design minimum: 48x48)
  static const double sm = 32.0;
  static const double md = 36.0;
  static const double lg = 44.0;
  static const double xl = 48.0;
  static const double xxl = 56.0;

  // Icon sizes within buttons
  static const double iconSm = 16.0;
  static const double iconMd = 18.0;
  static const double iconLg = 20.0;
  static const double iconXl = 24.0;
}

/// Semantic status colors for consistent feedback
/// Use with Theme brightness for proper contrast
class StatusColors {
  StatusColors._();

  // Success states
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFF81C784);
  static const Color successDark = Color(0xFF388E3C);

  // Error states
  static const Color error = Color(0xFFF44336);
  static const Color errorLight = Color(0xFFE57373);
  static const Color errorDark = Color(0xFFD32F2F);

  // Warning states
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFB74D);
  static const Color warningDark = Color(0xFFF57C00);

  // Info states
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFF64B5F6);
  static const Color infoDark = Color(0xFF1976D2);

  // Favorites (heart icon)
  static const Color favorite = Color(0xFFF44336);
  static const Color favoriteActive = Color(0xFFE53935);
}
