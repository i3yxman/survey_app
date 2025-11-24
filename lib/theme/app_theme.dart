// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static const _primaryColor = Color(0xFF2563EB); // 高级一点的蓝
  static const _accentColor  = Color(0xFF22C55E); // 绿色点缀
  static const _errorColor   = Color(0xFFEF4444);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        primary: _primaryColor,
        secondary: _accentColor,
        error: _errorColor,
        brightness: Brightness.light,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF3F4F6), // 更浅一点的灰白

      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 2,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      textTheme: _buildTextTheme(base.textTheme),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base) {
    return base.copyWith(
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        color: Colors.grey[600],
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
    );
  }
}