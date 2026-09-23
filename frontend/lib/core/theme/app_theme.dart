
import 'package:flutter/material.dart';

class AppColors {
  // Main colors of our AidTrack system
  static const Color primaryGreen = Color(0xFF185C37);
  static const Color accentYellow = Color(0xFFFFCA28);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGreen = Color(0xFFF1F8F3);

  // Additional colors for text and input fields
  static const Color darkText = Color(0xFF263238);
  static const Color greyText = Color(0xFF6B7280);
  static const Color borderColor = Color(0xFFE0E5E2);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,

      // Main application colors
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryGreen,
        primary: AppColors.primaryGreen,
        surface: AppColors.white,
      ),

      scaffoldBackgroundColor: AppColors.white,

      // Default font color
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          color: AppColors.darkText,
        ),
      ),

      // Default button style
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: AppColors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      // Default input field style
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.borderColor,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.borderColor,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 2,
          ),
        ),
      ),
    );
  }
}