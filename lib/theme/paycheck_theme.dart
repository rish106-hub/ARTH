import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Aliases [AppColors] under the names paycheck screens use. Two names for
/// one palette, kept as a single source of truth so the two design surfaces
/// (older app_theme screens, newer paycheck_theme screens) can never drift
/// apart in color even though their type scales still differ intentionally.
class PaycheckColors {
  static const canvas = AppColors.canvas;
  static const paper = AppColors.surface;
  static const ink = AppColors.ink;
  static const inkSoft = AppColors.inkSecondary;
  static const line = AppColors.divider;
  static const claim = AppColors.risk;
  static const claimSoft = AppColors.riskSoft;
  static const matched = AppColors.readiness;
  static const matchedSoft = AppColors.readinessSoft;
  static const contract = AppColors.primary;
  static const contractSoft = AppColors.primarySoft;
  static const contractDark = AppColors.primaryDark;
  static const pending = AppColors.warning;
  static const border = AppColors.border;
  static const inkMuted = AppColors.inkMuted;
  static const surfaceMuted = AppColors.surfaceMuted;

  // The names below exist purely so every AppColors.* call site could be
  // mechanically switched to PaycheckColors.* with zero behavior change
  // during the app-wide theme consolidation. Prefer the shorter names above
  // (canvas/paper/ink/...) in new code — these are kept for the screens that
  // were migrated verbatim from app_theme.dart's semantic aliases.
  static const surface = AppColors.surface;
  static const surfacePressed = AppColors.surfacePressed;
  static const inkSecondary = AppColors.inkSecondary;
  static const primary = AppColors.primary;
  static const primarySoft = AppColors.primarySoft;
  static const primaryDark = AppColors.primaryDark;
  static const readiness = AppColors.readiness;
  static const readinessSoft = AppColors.readinessSoft;
  static const risk = AppColors.risk;
  static const riskSoft = AppColors.riskSoft;
  static const warning = AppColors.warning;
  static const bgPrimary = AppColors.bgPrimary;
  static const bgCard = AppColors.bgCard;
  static const bgCardHover = AppColors.bgCardHover;
  static const bgSurface = AppColors.bgSurface;
  static const gold = AppColors.gold;
  static const goldLight = AppColors.goldLight;
  static const goldDim = AppColors.goldDim;
  static const success = AppColors.success;
  static const alert = AppColors.alert;
  static const amber = AppColors.amber;
  static const teal = AppColors.teal;
  static const digiLocker = AppColors.digiLocker;
  static const textPrimary = AppColors.textPrimary;
  static const textSecondary = AppColors.textSecondary;
  static const textMuted = AppColors.textMuted;
  static const textGold = AppColors.textGold;
  static const divider = AppColors.divider;
  static const gapSmall = AppColors.gapSmall;
  static const gapMedium = AppColors.gapMedium;
  static const gapLarge = AppColors.gapLarge;
  static const graphite = AppColors.graphite;
  static const glassStroke = AppColors.glassStroke;
  static const info = AppColors.info;
}

class PaycheckType {
  static TextStyle display({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 38,
        height: 1.05,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );

  static TextStyle displaySmall({Color color = PaycheckColors.ink}) =>
      TextStyle(
        fontFamily: 'Anek',
        fontSize: 32,
        height: 1.08,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );

  /// Largest section heading (page-level "Your pay is ready" style copy).
  static TextStyle h1({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 28,
        height: 1.2,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle title({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 24,
        height: 1.15,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Secondary section heading, between [title] and [heading].
  static TextStyle h2({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 22,
        height: 1.3,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Card and sub-section heading. The only 17/w600 tier — `h3` was a second
  /// name for this same style, kept while `AppTextStyles` still existed to
  /// mirror. That scale is gone, so the duplicate is too.
  static TextStyle heading({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Compatibility name for existing card headings.
  static TextStyle h3({Color color = PaycheckColors.ink}) =>
      heading(color: color);

  static TextStyle body({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle bodyMedium({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle bodyStrong({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle utility({Color color = PaycheckColors.inkSoft}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 12,
        height: 1.25,
        letterSpacing: 0,
        fontWeight: FontWeight.w500,
        color: color,
      );

  /// Small, functional label — for section eyebrows above a heading.
  static TextStyle sectionLabel({Color color = PaycheckColors.contract}) =>
      TextStyle(
        fontFamily: 'Anek',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: color,
      );

  /// Smallest microcopy (helper text, timestamps).
  static TextStyle micro({Color color = PaycheckColors.inkSoft}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle caption({Color color = PaycheckColors.inkSoft}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle button({Color color = PaycheckColors.canvas}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color,
      );

  static TextStyle money({
    Color color = PaycheckColors.ink,
    double size = 15,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontFamily: 'Anek',
        fontSize: size,
        height: 1.15,
        letterSpacing: 0,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );
}
