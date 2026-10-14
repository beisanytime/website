import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Palette ported from `Theme.swift`, which in turn came from the website's CSS.
///
/// Forui's theme drives the components; this stays for the artwork and accents
/// Forui has no token for (speaker colours, playback bars, audio gradients).
class AppPalette {
  const AppPalette._();

  static const Color hartmanBlue = Color(0xFF063980);
  static const Color rosenfeldGreen = Color(0xFF0F6649);
  static const Color golkerOrange = Color(0xFF8C5507);
  static const Color guestsPurple = Color(0xFF4F11A6);

  static const Color accent = Color(0xFF0E2E8C);
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
}

/// Parses the `#rrggbb` strings the API and model layer hand around.
Color colorFromHex(String hex) {
  var value = hex.replaceAll('#', '').trim();
  if (value.length == 6) {
    value = 'ff$value';
  }
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) {
    return const Color(0xFF000000);
  }
  return Color(parsed);
}

/// The adaptive surface colours from `LightColors` / `DarkColors`.
@immutable
class AppColors {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.surfaceTertiary,
    required this.textMain,
    required this.textMuted,
    required this.textFaint,
    required this.borderLight,
  });

  final Color background;
  final Color surface;
  final Color surfaceSecondary;
  final Color surfaceTertiary;
  final Color textMain;
  final Color textMuted;
  final Color textFaint;
  final Color borderLight;

  static const AppColors light = AppColors(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF1F5F9),
    surfaceTertiary: Color(0xFFE2E8F0),
    textMain: Color(0xFF0F172A),
    textMuted: Color(0xFF64748B),
    textFaint: Color(0xFF94A3B8),
    borderLight: Color(0xFFE2E8F0),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF020617),
    surface: Color(0xFF0F172A),
    surfaceSecondary: Color(0xFF1E293B),
    surfaceTertiary: Color(0xFF334155),
    textMain: Color(0xFFF8FAFC),
    textMuted: Color(0xFF94A3B8),
    textFaint: Color(0xFF475569),
    borderLight: Color(0xFF1E293B),
  );
}

/// Palette accessor for the hand-painted parts of the UI.
extension AppColorsX on BuildContext {
  AppColors get palette => Theme.of(this).brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
}

/// The Forui theme for the chosen brightness.
///
/// Forui supplies the entire component design language, so there is no Material
/// [ThemeData] driving anything but the framework fallbacks (route animations).
FThemeData foruiThemeData({required bool dark}) {
  final data = dark ? FTheme.neutral.dark : FTheme.neutral.light;
  return data.touch;
}

/// The minimal host theme.
///
/// Forui owns every visible component, so this only has to give the framework a
/// brightness (which drives [AppColorsX.palette]) and sane page transitions.
ThemeData hostTheme({required bool dark}) => ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor:
          dark ? AppColors.dark.background : AppColors.light.background,
    );
