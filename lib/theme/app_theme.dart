import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF004D40);
  static const deepGreen = Color(0xFF1E4B3E);
  static const canvas = Color(0xFFF5F7F6);
  static const ink = Color(0xFF202522);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE1E8E4);
}

abstract final class AppTheme {
  static final light = _withAndroidTextMetrics(_base);

  /// Material 3 gives most text styles a letter spacing (bodyMedium 0.25,
  /// labelLarge 0.1, ...); Android TextViews in the native app use none, which
  /// made every Flutter string a few percent wider.
  static ThemeData _withAndroidTextMetrics(ThemeData theme) {
    TextTheme flat(TextTheme t) => t.apply().copyWith(
      displayLarge: t.displayLarge?.copyWith(letterSpacing: 0),
      displayMedium: t.displayMedium?.copyWith(letterSpacing: 0),
      displaySmall: t.displaySmall?.copyWith(letterSpacing: 0),
      headlineLarge: t.headlineLarge?.copyWith(letterSpacing: 0),
      headlineMedium: t.headlineMedium?.copyWith(letterSpacing: 0),
      headlineSmall: t.headlineSmall?.copyWith(letterSpacing: 0),
      titleLarge: t.titleLarge?.copyWith(letterSpacing: 0),
      titleMedium: t.titleMedium?.copyWith(letterSpacing: 0),
      titleSmall: t.titleSmall?.copyWith(letterSpacing: 0),
      bodyLarge: t.bodyLarge?.copyWith(letterSpacing: 0),
      bodyMedium: t.bodyMedium?.copyWith(letterSpacing: 0),
      bodySmall: t.bodySmall?.copyWith(letterSpacing: 0),
      labelLarge: t.labelLarge?.copyWith(letterSpacing: 0),
      labelMedium: t.labelMedium?.copyWith(letterSpacing: 0),
      labelSmall: t.labelSmall?.copyWith(letterSpacing: 0),
    );
    return theme.copyWith(
      textTheme: flat(theme.textTheme),
      primaryTextTheme: flat(theme.primaryTextTheme),
    );
  }

  static final _base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
  );
}
