import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PaycheckColors {
  static const canvas = Color(0xFFF3F6FB);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF14213D);
  static const inkSoft = Color(0xFF657087);
  static const line = Color(0xFFDCE3ED);
  static const claim = Color(0xFFFF6B4A);
  static const claimSoft = Color(0xFFFFE4DC);
  static const matched = Color(0xFF12A875);
  static const matchedSoft = Color(0xFFDDF5EC);
  static const contract = Color(0xFF4A66F0);
  static const contractSoft = Color(0xFFE4E9FF);
  static const pending = Color(0xFFF2B84B);
}

class PaycheckType {
  static TextStyle display({Color color = PaycheckColors.ink}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 46,
        height: 0.98,
        letterSpacing: -2,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle title({Color color = PaycheckColors.ink}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 28,
        height: 1.08,
        letterSpacing: -0.8,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle heading({Color color = PaycheckColors.ink}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 18,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle body({Color color = PaycheckColors.ink}) =>
      GoogleFonts.inter(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle bodyStrong({Color color = PaycheckColors.ink}) =>
      GoogleFonts.inter(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle utility({Color color = PaycheckColors.inkSoft}) =>
      GoogleFonts.ibmPlexMono(
        fontSize: 11,
        height: 1.3,
        letterSpacing: 0.45,
        fontWeight: FontWeight.w500,
        color: color,
      );
}
