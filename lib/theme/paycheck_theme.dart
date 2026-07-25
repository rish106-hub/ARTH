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
  static const pending = AppColors.warning;
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

  static TextStyle title({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 24,
        height: 1.15,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle heading({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle body({Color color = PaycheckColors.ink}) => TextStyle(
        fontFamily: 'Anek',
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w400,
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
