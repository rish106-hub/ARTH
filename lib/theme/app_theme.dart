import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Core palette — Dhan Aesthetic
  static const Color bgPrimary = Color(0xFF141414);   // Deep Charcoal
  static const Color bgCard = Color(0xFF1E1E1E);       // Elevated Charcoal
  static const Color bgCardHover = Color(0xFF252525);
  static const Color bgSurface = Color(0xFF2A2A2A);

  static const Color gold = Color(0xFFF5C842);         // Tax Gold
  static const Color goldLight = Color(0xFFFDE98A);    // Highlight
  static const Color goldDim = Color(0xFFB8932E);

  static const Color success = Color(0xFF4CAF50);
  static const Color alert = Color(0xFFF44336);
  static const Color amber = Color(0xFFFF9800);
  static const Color teal = Color(0xFF26A69A);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFF616161);
  static const Color textGold = Color(0xFFF5C842);

  static const Color divider = Color(0xFF2C2C2C);
  static const Color border = Color(0xFF333333);

  // Gap card colors by size
  static const Color gapSmall = Color(0xFF26A69A);   // teal < 10k
  static const Color gapMedium = Color(0xFFFF9800);  // amber 10k-50k
  static const Color gapLarge = Color(0xFFF5C842);   // gold 50k+
}

class AppTextStyles {
  // Display — gap numbers
  static TextStyle display({Color color = AppColors.gold}) => GoogleFonts.inter(
    fontSize: 56,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: -1.5,
    height: 1.0,
  );

  static TextStyle displaySmall({Color color = AppColors.gold}) => GoogleFonts.inter(
    fontSize: 40,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: -1.0,
    height: 1.0,
  );

  // Headings
  static TextStyle h1({Color color = AppColors.textPrimary}) => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static TextStyle h2({Color color = AppColors.textPrimary}) => GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static TextStyle h3({Color color = AppColors.textPrimary}) => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: color,
    height: 1.3,
  );

  // Body
  static TextStyle body({Color color = AppColors.textPrimary}) => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.5,
  );

  static TextStyle bodyMedium({Color color = AppColors.textPrimary}) => GoogleFonts.inter(
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
  static TextStyle micro({Color color = AppColors.textSecondary}) => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w300,
    color: color,
    height: 1.4,
  );

  static TextStyle caption({Color color = AppColors.textSecondary}) => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.4,
  );

  // Button
  static TextStyle button({Color color = AppColors.bgPrimary}) => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: 0.2,
  );
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgPrimary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.goldLight,
        surface: AppColors.bgCard,
        error: AppColors.alert,
        onPrimary: AppColors.bgPrimary,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.gold,
        inactiveTrackColor: AppColors.bgSurface,
        thumbColor: AppColors.gold,
        overlayColor: AppColors.gold.withOpacity(0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        trackHeight: 4,
        valueIndicatorColor: AppColors.gold,
        valueIndicatorTextStyle: GoogleFonts.inter(
          color: AppColors.bgPrimary,
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
        checkColor: WidgetStateProperty.all(AppColors.bgPrimary),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      dividerColor: AppColors.divider,
      cardColor: AppColors.bgCard,
      useMaterial3: true,
    );
  }
}

// Reusable button styles
class AppButtons {
  static ButtonStyle primaryGold = ElevatedButton.styleFrom(
    backgroundColor: AppColors.gold,
    foregroundColor: AppColors.bgPrimary,
    elevation: 0,
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    textStyle: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
  );

  static ButtonStyle outlineGold = OutlinedButton.styleFrom(
    foregroundColor: AppColors.gold,
    side: const BorderSide(color: AppColors.gold, width: 1.5),
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    textStyle: GoogleFonts.inter(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
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
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(50));
}
