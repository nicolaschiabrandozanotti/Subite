import 'package:flutter/material.dart';

class AppColors {
  // Brand & Palette from Stitch Design System
  static const Color primary = Color(0xFF0B1C30);
  static const Color secondary = Color(0xFF006398); // Azul Tránsito Córdoba
  static const Color secondaryContainer = Color(0xFF5BB8FE);
  static const Color onSecondaryContainer = Color(0xFF00476E);

  // Live indicators
  static const Color liveGreen = Color(0xFF009668); // Verde En Vivo
  static const Color liveGreenLight = Color(0xFF4EDEA3);
  static const Color liveGreenContainer = Color(0xFFE6F7F0);
  static const Color delayAmber = Color(0xFFB45309);
  static const Color delayAmberLight = Color(0xFFFDE68A);

  // Backgrounds & Surfaces (Dark & Clean)
  static const Color bgDark = Color(0xFF0B0F19);
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color surfaceCardDark = Color(0xFF161E2E);
  static const Color surfaceCardLight = Color(0xFFFFFFFF);
  static const Color borderDark = Color(0xFF243048);

  // Light surfaces
  static const Color bgLight = Color(0xFFF8F9FF);
  static const Color surfaceLight = Color(0xFFEFF4FF);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color surfaceContainerHigh = Color(0xFFDCE9FF);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.secondary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.secondary,
        secondary: AppColors.secondaryContainer,
        surface: AppColors.surfaceDark,
        onSurface: Colors.white,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
