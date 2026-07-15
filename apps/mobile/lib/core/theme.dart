import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system — Vyapar-inspired: violet brand, ink-navy text,
/// soft grey-blue canvas, white rounded cards, pastel accent chips.
class AppColors {
  static const primary = Color(0xFF7C3AED); // violet
  static const primaryDark = Color(0xFF6D28D9);
  static const primarySoft = Color(0xFFF3E8FD);

  static const ink = Color(0xFF17223B); // headings / primary text
  static const inkSoft = Color(0xFF6B7280); // secondary text
  static const canvas = Color(0xFFF4F6FB); // scaffold background
  static const card = Colors.white;
  static const line = Color(0xFFE8ECF4); // borders / dividers

  // accent family for stat tiles, icon chips, avatars
  static const green = Color(0xFF12A150);
  static const teal = Color(0xFF0D9488);
  static const indigo = Color(0xFF4F63E6);
  static const orange = Color(0xFFF08C00);
  static const purple = Color(0xFF8B5CF6);
  static const pink = Color(0xFFDB2777);
  static const red = Color(0xFFDC2626);

  // soft tint backgrounds for banners/callouts
  static const redSoft = Color(0xFFFDEDF0);
  static const orangeSoft = Color(0xFFFFF7E6);
  static const greenSoft = Color(0xFFE9F9EF);

  /// Deterministic accent for avatars/initials.
  static Color accentFor(String seed) {
    const accents = [green, teal, indigo, orange, purple, pink, primary];
    return accents[seed.hashCode.abs() % accents.length];
  }
}

/// Soft elevated shadow used on cards and the bottom bar.
List<BoxShadow> softShadow([double blur = 16]) => [
      BoxShadow(
        color: AppColors.ink.withValues(alpha: 0.06),
        blurRadius: blur,
        offset: const Offset(0, 4),
      ),
    ];

const seedColor = AppColors.primary;

ThemeData buildTheme() {
  final base = ColorScheme.fromSeed(seedColor: AppColors.primary);
  final scheme = base.copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.indigo,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    error: AppColors.red,
    outlineVariant: AppColors.line,
  );

  final textTheme = GoogleFonts.manropeTextTheme().apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge: textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        letterSpacing: -0.3,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFF9AA3B2), fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        textStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      iconColor: AppColors.inkSoft,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.primarySoft,
      checkmarkColor: AppColors.primary,
      labelStyle: GoogleFonts.manrope(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primarySoft,
        selectedForegroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.line),
        textStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.manrope(
          fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.inkSoft,
      indicatorColor: AppColors.primary,
    ),
  );
}
