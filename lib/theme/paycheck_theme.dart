import 'package:flutter/material.dart';

class PaycheckColors {
  static const canvas = Color(0xFFF3F5F8);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF11263D);
  static const inkSoft = Color(0xFF5F6F7E);
  static const line = Color(0xFFD9E0E6);
  static const claim = Color(0xFFD95746);
  static const claimSoft = Color(0xFFFBE9E6);
  static const matched = Color(0xFF0A6B63);
  static const matchedSoft = Color(0xFFE2F2EF);
  static const contract = Color(0xFF315C78);
  static const contractSoft = Color(0xFFE6EEF3);
  static const pending = Color(0xFFB9821F);
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
