import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // Shared ARTH palette. Tax tools inherit the paycheck product skin so they
  // feel like a contained capability, not a second application.
  static const Color canvas = Color(0xFFF3F5F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFE8EDF1);
  static const Color surfacePressed = Color(0xFFD9E0E6);
  static const Color ink = Color(0xFF11263D);
  static const Color inkSecondary = Color(0xFF5F6F7E);
  static const Color inkMuted = Color(0xFF7D8A96);
  static const Color primary = Color(0xFF315C78);
  static const Color primarySoft = Color(0xFFE6EEF3);
  static const Color primaryDark = Color(0xFF21455D);
  static const Color readiness = Color(0xFF0A6B63);
  static const Color readinessSoft = Color(0xFFE2F2EF);
  static const Color risk = Color(0xFFD95746);
  static const Color riskSoft = Color(0xFFFBE9E6);
  static const Color warning = Color(0xFFB9821F);

  static const Color bgPrimary = canvas;
  static const Color bgCard = surface;
  static const Color bgCardHover = surfaceMuted;
  static const Color bgSurface = surfaceMuted;

  static const Color gold = primary;
  static const Color goldLight = primarySoft;
  static const Color goldDim = primaryDark;

  static const Color success = readiness;
  static const Color alert = risk;
  static const Color amber = warning;
  static const Color teal = readiness;
  static const Color digiLocker = Color(0xFF355AA8);

  static const Color textPrimary = ink;
  static const Color textSecondary = inkSecondary;
  static const Color textMuted = inkMuted;
  static const Color textGold = gold;

  static const Color divider = Color(0xFFD9E0E6);
  static const Color border = Color(0xFFCDD6DD);

  // Gap card colors by size
  static const Color gapSmall = readiness;
  static const Color gapMedium = warning;
  static const Color gapLarge = risk;

  static const Color graphite = surfaceMuted;
  static const Color glassStroke = border;
  static const Color info = primary;
}

class AppTextStyles {
  // Numbers remain neutral. Green is reserved for action and positive state.
  static TextStyle display({Color color = AppColors.gold}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 38,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.05,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle displaySmall({Color color = AppColors.gold}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.08,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // Headings
  static TextStyle h1({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.2,
      );

  static TextStyle h2({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.3,
      );

  static TextStyle h3({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.3,
      );

  // Body
  static TextStyle body({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  static TextStyle bodyMedium({Color color = AppColors.textPrimary}) =>
      TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.5,
      );

  static TextStyle bodyStrong({Color color = AppColors.textPrimary}) =>
      TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.5,
      );

  // Section labels are functional, not decorative.
  static TextStyle sectionLabel({Color color = AppColors.gold}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
      );

  // Micro-copy
  static TextStyle micro({Color color = AppColors.textSecondary}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.4,
      );

  static TextStyle caption({Color color = AppColors.textSecondary}) =>
      TextStyle(
        fontFamily: 'Anek',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.4,
      );

  static TextStyle money({
    Color color = AppColors.textPrimary,
    double size = 15,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontFamily: 'Anek',
        fontSize: size,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
        height: 1.15,
      );

  // Button
  static TextStyle button({Color color = AppColors.bgPrimary}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.2,
      );
}

class AppTheme {
  static ThemeData get light {
    final baseTextTheme = ThemeData.light().textTheme.apply(fontFamily: 'Anek');

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bgPrimary,
      textTheme: baseTextTheme,
      primaryTextTheme: baseTextTheme,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.readiness,
        surface: AppColors.bgCard,
        error: AppColors.alert,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle:
            baseTextTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.gold,
        inactiveTrackColor: AppColors.bgSurface,
        thumbColor: AppColors.gold,
        overlayColor: AppColors.gold.withValues(alpha: 0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        trackHeight: 4,
        valueIndicatorColor: AppColors.gold,
        valueIndicatorTextStyle: const TextStyle(
          fontFamily: 'Anek',
          color: Colors.white,
          fontWeight: FontWeight.w600,
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
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      cardColor: AppColors.bgCard,
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontFamily: 'Anek',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          );
        }),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: Color(0x334A66F0),
        selectionHandleColor: AppColors.gold,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCard,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(fontFamily: 'Anek', color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.card,
          borderSide: BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle:
            const TextStyle(fontFamily: 'Anek', color: Colors.white),
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
    textStyle: const TextStyle(
      fontFamily: 'Anek',
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
  );

  static ButtonStyle outlineGold = OutlinedButton.styleFrom(
    foregroundColor: AppColors.gold,
    side: const BorderSide(color: AppColors.gold, width: 1.5),
    minimumSize: const Size(0, 52),
    maximumSize: const Size(double.infinity, 52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    textStyle: const TextStyle(
        fontFamily: 'Anek', fontSize: 15, fontWeight: FontWeight.w600),
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
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve standard = Curves.easeOutCubic;
}
