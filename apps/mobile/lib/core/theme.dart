import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One set of theme-dependent "neutral" colors.
///
/// Brand + accent colors are identical in both modes and stay compile-time
/// consts on [AppColors]; only these neutrals swap between light and dark.
class AppPalette {
  const AppPalette({
    required this.ink,
    required this.inkSoft,
    required this.canvas,
    required this.card,
    required this.line,
    required this.primarySoft,
    required this.redSoft,
    required this.orangeSoft,
    required this.greenSoft,
    required this.hint,
  });

  final Color ink;
  final Color inkSoft;
  final Color canvas;
  final Color card;
  final Color line;
  final Color primarySoft;
  final Color redSoft;
  final Color orangeSoft;
  final Color greenSoft;
  final Color hint;

  static const light = AppPalette(
    ink: Color(0xFF17223B),
    inkSoft: Color(0xFF6B7280),
    canvas: Color(0xFFF4F6FB),
    card: Colors.white,
    line: Color(0xFFE8ECF4),
    primarySoft: Color(0xFFF3E8FD),
    redSoft: Color(0xFFFDEDF0),
    orangeSoft: Color(0xFFFFF7E6),
    greenSoft: Color(0xFFE9F9EF),
    hint: Color(0xFF9AA3B2),
  );

  static const dark = AppPalette(
    ink: Color(0xFFECEEF8),
    inkSoft: Color(0xFF9AA3B8),
    canvas: Color(0xFF101223),
    card: Color(0xFF1A1D33),
    line: Color(0xFF2A2E47),
    primarySoft: Color(0xFF2E2352),
    redSoft: Color(0xFF3B2030),
    orangeSoft: Color(0xFF3A2F1C),
    greenSoft: Color(0xFF16321F),
    hint: Color(0xFF6F7690),
  );
}

/// Design system — Vyapar-inspired: violet brand, ink-navy text,
/// soft grey-blue canvas, white rounded cards, pastel accent chips.
///
/// Dark mode (desktop-only feature) works by reassigning the *neutral*
/// fields below via [setMode] and rebuilding the whole widget tree.
/// Because the neutrals are mutable statics they must NEVER appear in
/// `const` expressions or default parameter values — the accents and
/// brand colors (still `static const`) are fine anywhere.
class AppColors {
  // ---- identical in both modes (safe in const expressions) ----
  static const primary = Color(0xFF7C3AED); // violet
  static const primaryDark = Color(0xFF6D28D9);

  // accent family for stat tiles, icon chips, avatars
  static const green = Color(0xFF12A150);
  static const teal = Color(0xFF0D9488);
  static const indigo = Color(0xFF4F63E6);
  static const orange = Color(0xFFF08C00);
  static const purple = Color(0xFF8B5CF6);
  static const pink = Color(0xFFDB2777);
  static const red = Color(0xFFDC2626);

  // ---- mode-dependent neutrals (NOT const — do not use in const) ----
  static Color ink = AppPalette.light.ink; // headings / primary text
  static Color inkSoft = AppPalette.light.inkSoft; // secondary text
  static Color canvas = AppPalette.light.canvas; // scaffold background
  static Color card = AppPalette.light.card;
  static Color line = AppPalette.light.line; // borders / dividers
  static Color primarySoft = AppPalette.light.primarySoft;
  static Color redSoft = AppPalette.light.redSoft;
  static Color orangeSoft = AppPalette.light.orangeSoft;
  static Color greenSoft = AppPalette.light.greenSoft;
  static Color hint = AppPalette.light.hint;

  static bool _dark = false;
  static bool get isDark => _dark;

  /// Swap the neutral palette. Callers must rebuild the whole tree
  /// afterwards (see `darkModeProvider` / the KeyedSubtree in main.dart)
  /// because static field changes don't notify any widget.
  static void setMode({required bool dark}) {
    _dark = dark;
    final p = dark ? AppPalette.dark : AppPalette.light;
    ink = p.ink;
    inkSoft = p.inkSoft;
    canvas = p.canvas;
    card = p.card;
    line = p.line;
    primarySoft = p.primarySoft;
    redSoft = p.redSoft;
    orangeSoft = p.orangeSoft;
    greenSoft = p.greenSoft;
    hint = p.hint;
  }

  /// Deterministic accent for avatars/initials.
  static Color accentFor(String seed) {
    const accents = [green, teal, indigo, orange, purple, pink, primary];
    return accents[seed.hashCode.abs() % accents.length];
  }
}

/// Soft elevated shadow used on cards and the bottom bar.
/// Shadows stay dark in both modes (a light "shadow" reads as a glow).
List<BoxShadow> softShadow([double blur = 16]) => [
      BoxShadow(
        color: AppColors.isDark
            ? Colors.black.withValues(alpha: 0.35)
            : const Color(0xFF17223B).withValues(alpha: 0.06),
        blurRadius: blur,
        offset: const Offset(0, 4),
      ),
    ];

const seedColor = AppColors.primary;

ThemeData buildTheme({bool dark = false}) {
  final base = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  final scheme = base.copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.indigo,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    error: dark ? const Color(0xFFF87171) : AppColors.red,
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
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: AppColors.hint, fontSize: 14),
      labelStyle: TextStyle(color: AppColors.inkSoft, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.line),
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
        side: BorderSide(color: AppColors.line),
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
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      iconColor: AppColors.inkSoft,
    ),
    dividerTheme: DividerThemeData(color: AppColors.line, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.primarySoft,
      checkmarkColor: AppColors.primary,
      labelStyle: GoogleFonts.manrope(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
      side: BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primarySoft,
        selectedForegroundColor:
            dark ? const Color(0xFFCBB6F6) : AppColors.primary,
        side: BorderSide(color: AppColors.line),
        textStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.manrope(
          fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.inkSoft,
      indicatorColor: AppColors.primary,
    ),
  );
}
