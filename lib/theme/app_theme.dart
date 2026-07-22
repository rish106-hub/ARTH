import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // Shared ARTH palette. Tax tools inherit the paycheck product skin so they
  // feel like a contained capability, not a second application.
  static const Color canvas = Color(0xFFF3F6FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFE8EDF5);
  static const Color surfacePressed = Color(0xFFDCE3ED);
  static const Color ink = Color(0xFF14213D);
  static const Color inkSecondary = Color(0xFF657087);
  static const Color inkMuted = Color(0xFF8A94A7);
  static const Color primary = Color(0xFF4A66F0);
  static const Color primarySoft = Color(0xFFE4E9FF);
  static const Color primaryDark = Color(0xFF3149C7);
  static const Color readiness = Color(0xFF12A875);
  static const Color readinessSoft = Color(0xFFDDF5EC);
  static const Color risk = Color(0xFFFF6B4A);
  static const Color warning = Color(0xFFF2B84B);

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

  static const Color divider = Color(0xFFDCE3ED);
  static const Color border = Color(0xFFD3DCE9);

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
        fontFamily: 'PlusJakartaSans',
        fontSize: 56,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 0,
        height: 1.0,
      );

  static TextStyle displaySmall({Color color = AppColors.gold}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 40,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 0,
        height: 1.0,
      );

  // Headings
  static TextStyle h1({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 34,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.2,
      );

  static TextStyle h2({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.3,
      );

  static TextStyle h3({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.3,
      );

  // Body
  static TextStyle body({Color color = AppColors.textPrimary}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  static TextStyle bodyMedium({Color color = AppColors.textPrimary}) =>
      TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.5,
      );

  static TextStyle bodyStrong({Color color = AppColors.textPrimary}) =>
      TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.5,
      );

  // Section labels are functional, not decorative.
  static TextStyle sectionLabel({Color color = AppColors.gold}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0,
      );

  // Micro-copy
  static TextStyle micro({Color color = AppColors.textSecondary}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 12,
        fontWeight: FontWeight.w300,
        color: color,
        height: 1.4,
      );

  static TextStyle caption({Color color = AppColors.textSecondary}) =>
      TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.4,
      );

  // Button
  static TextStyle button({Color color = AppColors.bgPrimary}) => TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.2,
      );
}

class AppTheme {
  static ThemeData get light {
    final baseTextTheme =
        ThemeData.light().textTheme.apply(fontFamily: 'PlusJakartaSans');

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
          fontFamily: 'PlusJakartaSans',
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
            fontFamily: 'PlusJakartaSans',
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
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
        hintStyle: TextStyle(
            fontFamily: 'PlusJakartaSans', color: AppColors.textMuted),
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
            const TextStyle(fontFamily: 'PlusJakartaSans', color: Colors.white),
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
      fontFamily: 'PlusJakartaSans',
      fontSize: 16,
      fontWeight: FontWeight.w700,
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
        fontFamily: 'PlusJakartaSans',
        fontSize: 15,
        fontWeight: FontWeight.w600),
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
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const BorderRadius card = BorderRadius.all(Radius.circular(12));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve standard = Curves.easeOutCubic;
}
