import 'package:flutter/material.dart';

class AppColors {
  // Primary Brand Colors (Vibrant Royal Blue)
  static const Color primary =
      Color.fromARGB(255, 26, 16, 168); // Deep Royal Blue
  static const Color primaryLight =
      Color(0xff4437D1); // Harmonious lighter blue
  static const Color primaryDark =
      Color(0xff120B75); // Deeper variant for contrast
  static const Color accent = Color(0xff00E5FF); // Bright Cyan (Secondary)
  static const Color accentLight =
      Color(0xff6EFFFF); // Light cyan for subtle highlights

  // Neutral Colors (Light Mode)
  static const Color background =
      Color(0xffF4F7FA); // Tertiary / Very Light Grey
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xff1A1C1E); // Neutral - Near Black
  static const Color textSecondary = Color(0xff5A5E66); // Medium Grey

  // Dark Mode Colors (Premium Navy Palette)
  static const Color darkBackground = Color(0xff0D0F1A); // Deep Midnight Navy
  static const Color darkSurface = Color(0xff181B2E); // Dark Indigo Surface
  static const Color darkSurfaceLight = Color(0xff242842); // Elevated Surface
  static const Color darkBorder = Color(0xff33375A); // Subtle Dark Border
  static const Color darkTextPrimary =
      Color(0xffEEF0F8); // Off-White with blue tint
  static const Color darkTextSecondary =
      Color(0xff9498B8); // Muted Slate/Lavender

  // Status Colors
  static const Color success = Color(0xff10B981);
  static const Color error = Color(0xffEF4444);
  static const Color warning = Color(0xffF59E0B);

  // Folder Colors (Default Set)
  static const List<Color> folderColors = [
    Color(0xff2E3A8C), // Indigo (primary)
    Color(0xffEF4444), // Red
    Color(0xff10B981), // Green
    Color(0xffF59E0B), // Amber
    Color(0xff8B5CF6), // Purple
  ];
}
