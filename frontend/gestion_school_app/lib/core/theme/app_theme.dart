import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF6366F1);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF4F46E5),
    onPrimary: Colors.white,
    secondary: Color(0xFF8B5CF6),
    onSecondary: Colors.white,
    error: Color(0xFFB42318),
    onError: Colors.white,
    surface: Color(0xFFF6F8FC),
    onSurface: Color(0xFF121826),
    tertiary: Color(0xFF0EA5E9),
    onTertiary: Colors.white,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF4F6FB),
    surfaceContainer: Color(0xFFEFF3FA),
    surfaceContainerHigh: Color(0xFFE7EDF7),
    surfaceContainerHighest: Color(0xFFDCE5F3),
    onSurfaceVariant: Color(0xFF556174),
    outline: Color(0xFFACB7C8),
    outlineVariant: Color(0xFFD0D8E5),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF1E2431),
    onInverseSurface: Color(0xFFF5F7FC),
    inversePrimary: Color(0xFFB3B8FF),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8B5CF6),
    onPrimary: Colors.white,
    secondary: Color(0xFF6366F1),
    onSecondary: Colors.white,
    error: Color(0xFFFDA29B),
    onError: Color(0xFF4C0519),
    surface: Color(0xFF0F172A),
    onSurface: Color(0xFFE7ECF9),
    tertiary: Color(0xFF38BDF8),
    onTertiary: Color(0xFF042F4A),
    surfaceContainerLowest: Color(0xFF0D1426),
    surfaceContainerLow: Color(0xFF131D33),
    surfaceContainer: Color(0xFF18233B),
    surfaceContainerHigh: Color(0xFF1B2742),
    surfaceContainerHighest: Color(0xFF22304F),
    onSurfaceVariant: Color(0xFF9BA9C3),
    outline: Color(0xFF5C6E8A),
    outlineVariant: Color(0xFF33445F),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE7ECF9),
    onInverseSurface: Color(0xFF121A2F),
    inversePrimary: Color(0xFF5B60F0),
  );

  static TextTheme _textTheme(Color textColor) {
    final base = Typography.material2021().white;
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textColor,
        letterSpacing: -0.3,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: textColor.withValues(alpha: 0.82),
      ),
    );
  }

  static ThemeData light = ThemeData(
    colorScheme: _lightScheme,
    textTheme: _textTheme(_lightScheme.onSurface),
    scaffoldBackgroundColor: _lightScheme.surface,
    useMaterial3: true,
    brightness: Brightness.light,
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _seed, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: _seed,
        foregroundColor: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );

  static ThemeData dark = ThemeData(
    colorScheme: _darkScheme,
    textTheme: _textTheme(_darkScheme.onSurface),
    scaffoldBackgroundColor: _darkScheme.surface,
    useMaterial3: true,
    brightness: Brightness.dark,
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _seed, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: _seed,
        foregroundColor: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
