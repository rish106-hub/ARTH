import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Clear Finance OS. Legacy color names remain to keep all screens stable.
  static const Color bgPrimary = Color(0xFFF7F8F5);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgCardHover = Color(0xFFF1F4EF);
  static const Color bgSurface = Color(0xFFE9EEE8);

  static const Color gold = Color(0xFF176B45);
  static const Color goldLight = Color(0xFFDDEDE4);
  static const Color goldDim = Color(0xFF0D4E31);

  static const Color success = Color(0xFF238653);
  static const Color alert = Color(0xFFC84C3A);
  static const Color amber = Color(0xFFE6A936);
  static const Color teal = Color(0xFF2C7180);

  static const Color textPrimary = Color(0xFF151815);
  static const Color textSecondary = Color(0xFF5F685F);
  static const Color textMuted = Color(0xFF8A938A);
  static const Color textGold = gold;

  static const Color divider = Color(0xFFE2E7E1);
  static const Color border = Color(0xFFD7DED6);

  // Gap card colors by size
  static const Color gapSmall = Color(0xFF2C7180);
  static const Color gapMedium = Color(0xFFE6A936);
  static const Color gapLarge = Color(0xFF176B45);

  static const Color ink = bgPrimary;
  static const Color graphite = Color(0xFFEDF1EC);
  static const Color glassStroke = border;
  static const Color info = Color(0xFF4267B2);
}

class AppTextStyles {
  // Display — gap numbers
  static TextStyle display({Color color = AppColors.gold}) => GoogleFonts.inter(
        fontSize: 56,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 0,
        height: 1.0,
      );

  static TextStyle displaySmall({Color color = AppColors.gold}) =>
      GoogleFonts.inter(
        fontSize: 40,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 0,
        height: 1.0,
      );

  // Headings
  static TextStyle h1({Color color = AppColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0,
        height: 1.2,
      );

  static TextStyle h2({Color color = AppColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0,
        height: 1.3,
      );

  static TextStyle h3({Color color = AppColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.3,
      );

  // Body
  static TextStyle body({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  static TextStyle bodyMedium({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.5,
      );

  // Section labels (80C, 80D etc.) — uses Space Grotesk via google_fonts
  static TextStyle sectionLabel({Color color = AppColors.gold}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
      );

  // Micro-copy
  static TextStyle micro({Color color = AppColors.textSecondary}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w300,
        color: color,
        height: 1.4,
      );

  static TextStyle caption({Color color = AppColors.textSecondary}) =>
      GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.4,
      );

  // Button
  static TextStyle button({Color color = AppColors.bgPrimary}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.2,
      );
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bgPrimary,
      colorScheme: const ColorScheme.light(
        primary: AppColors.gold,
        secondary: AppColors.goldLight,
        surface: AppColors.bgCard,
        error: AppColors.alert,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.gold,
        inactiveTrackColor: AppColors.bgSurface,
        thumbColor: AppColors.gold,
        overlayColor: AppColors.gold.withValues(alpha: 0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        trackHeight: 4,
        valueIndicatorColor: AppColors.gold,
        valueIndicatorTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.gold;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      dividerColor: AppColors.divider,
      cardColor: AppColors.bgCard,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: Color(0x33176B45),
        selectionHandleColor: AppColors.gold,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      useMaterial3: true,
    );
  }
}

// Reusable button styles
class AppButtons {
  static ButtonStyle primaryGold = ElevatedButton.styleFrom(
    backgroundColor: AppColors.gold,
    foregroundColor: Colors.white,
    elevation: 0,
    minimumSize: const Size(0, 52),
    maximumSize: const Size(double.infinity, 52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    textStyle: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
  );

  static ButtonStyle outlineGold = OutlinedButton.styleFrom(
    foregroundColor: AppColors.gold,
    side: const BorderSide(color: AppColors.gold, width: 1.5),
    minimumSize: const Size(0, 52),
    maximumSize: const Size(double.infinity, 52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
  );
}

// Spacing constants
class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// Border radius
class AppRadius {
  static const double sm = 8;
  static const double md = 8;
  static const double lg = 8;
  static const double xl = 8;
  static const BorderRadius card = BorderRadius.all(Radius.circular(8));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve standard = Curves.easeOutCubic;
}
