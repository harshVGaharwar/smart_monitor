import 'package:flutter/material.dart';

/// Central design system for the SMART application.
///
/// A restrained, professional palette suited to an internal banking tool:
/// a deep navy primary, a single warm red accent (used sparingly for alerts
/// and the brand mark) and a cool neutral surface stack.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF1B3A6B); // deep navy
  static const Color primaryDark = Color(0xFF13294B);
  static const Color primaryLight = Color(0xFF2E5AA0);
  static const Color accent = Color(0xFFE01A2B); // brand red

  // Neutrals
  static const Color canvas = Color(0xFFEFF2F7); // app background
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF7F9FC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  // Text
  static const Color textPrimary = Color(0xFF0F1B2D);
  static const Color textSecondary = Color(0xFF5A6B85);
  static const Color textMuted = Color(0xFF94A3B8);

  // Semantic
  static const Color success = Color(0xFF12805C);
  static const Color successBg = Color(0xFFDFF3EC);
  static const Color warning = Color(0xFFB77400);
  static const Color warningBg = Color(0xFFFDF0DA);
  static const Color info = Color(0xFF2E5AA0);
  static const Color infoBg = Color(0xFFE4ECFA);
  static const Color danger = Color(0xFFC0303B);
  static const Color dangerBg = Color(0xFFFBE6E8);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
      ),
      textTheme: _textTheme(base.textTheme),
      dividerColor: AppColors.border,
      splashFactory: InkRipple.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        enabledBorder: _border(AppColors.border),
        focusedBorder: _border(AppColors.primaryLight, width: 1.6),
        border: _border(AppColors.border),
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
          fontFamily: 'Inter',
        )
        .copyWith(
          titleLarge: const TextStyle(fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600),
        );
  }

  /// Soft elevation used across cards and panels.
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF1B3A6B).withValues(alpha: 0.06),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}
