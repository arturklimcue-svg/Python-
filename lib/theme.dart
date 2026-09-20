import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF6C4DF6);
  static const primaryDark = Color(0xFF4A2BC9);
  static const accent = Color(0xFFFF7A45);
  static const background = Color(0xFFF4F5FB);
  static const card = Colors.white;
  static const textDark = Color(0xFF1E1B35);
  static const textMuted = Color(0xFF7A7891);
  static const gold = Color(0xFFFFB300);
  static const streak = Color(0xFFFF6B35);
  static const success = Color(0xFF2EBD85);
  static const warning = Color(0xFFF5A623);
  static const danger = Color(0xFFF0445C);
  static const codeBg = Color(0xFF201F33);
  static const codeText = Color(0xFFE6E4F2);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
    ),
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textDark,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textDark,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
  );
}