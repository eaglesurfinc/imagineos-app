import 'package:flutter/material.dart';

/// A sunny workspace with clear contrast and quiet surfaces for artwork.
ThemeData imagineOsTheme() {
  const ink = Color(0xff203c46);
  const teal = Color(0xff006b65);
  const sunshine = Color(0xffffd56a);
  final colors = ColorScheme.fromSeed(
    seedColor: teal,
    primary: teal,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xffb7f0df),
    onPrimaryContainer: const Color(0xff073e38),
    secondary: const Color(0xffac402d),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xffffd6c8),
    onSecondaryContainer: const Color(0xff672718),
    tertiary: const Color(0xff6c48a3),
    tertiaryContainer: const Color(0xffeaddff),
    surface: const Color(0xfffffbf2),
    onSurface: ink,
    onSurfaceVariant: const Color(0xff405960),
    outline: const Color(0xff668086),
    outlineVariant: const Color(0xffc8ddda),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: colors);
  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium
          ?.copyWith(color: teal, fontWeight: FontWeight.w700),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(color: teal, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
        backgroundColor: sunshine,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle:
            TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800)),
    navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xffe1f3f7),
        indicatorColor: sunshine,
        surfaceTintColor: Colors.transparent),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)))),
    inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
    cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xfffffbf2),
        surfaceTintColor: Colors.transparent),
  );
}
