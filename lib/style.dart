import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Спільна дизайн-система застосунку: темна тема (у стилі картки дня),
/// два шрифти (serif для "голосу" бренду, sans для функціонального UI).
/// Глибина на темному тлі передається тоном поверхні, а не тінями.
class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceRaised = Color(0xFF272727);
  static const ink = Colors.white;
  static const inkMuted = Color(0xFF9B9B9B);
  static const divider = Color(0x1FFFFFFF);
}

class AppShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> subtle = [];
}

/// Serif — для моментів "голосу" бренду: заголовки, назва оцінки, назва застосунку.
TextStyle appSerif({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color color = AppColors.ink,
  double? height,
}) {
  return GoogleFonts.lora(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );
}
