import 'package:flutter/material.dart';
import 'app_colors.dart'; 
class AppTextStyles {
  static const String fontName = 'Flame';
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );
  static TextStyle get flameChunky => const TextStyle(
        fontFamily: 'Flame',
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
  );
  static TextStyle get displayLarge => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.w900,
        color: AppColors.bkBrown,
        fontSize: 56,
      );
  static TextStyle get displayMedium => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.w800,
        color: AppColors.bkBrown,
        fontSize: 44,
      );
  static TextStyle get headlineLarge => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.w700,
        color: AppColors.bkBrown,
        fontSize: 32,
      );
  static TextStyle get headlineMedium => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.w700,
        color: AppColors.bkBrown,
        fontSize: 28,
      );
  static TextStyle get headlineSmall => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.w700,
        color: AppColors.darkText,
        fontSize: 24,
      );
  static TextStyle get bodyLarge => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.w500,
        color: AppColors.darkText,
        fontSize: 20,
      );
  static TextStyle get bodyMedium => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.normal,
        color: AppColors.darkText,
        fontSize: 18,
      );
  static TextStyle get labelLarge => const TextStyle(
        fontFamily: fontName,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
        fontSize: 22,
      );
}
