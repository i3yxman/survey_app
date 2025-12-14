// lib/widgets/glass_card.dart

import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 32,
    this.padding = const EdgeInsets.all(24),
    this.blurSigma = 18,
    this.darkBgOpacity = 0.08,
    this.lightBgOpacity = 0.9,
    this.darkBorderOpacity = 0.15,
    this.lightBorderOpacity = 0.06,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double blurSigma;

  final double darkBgOpacity;
  final double lightBgOpacity;

  final double darkBorderOpacity;
  final double lightBorderOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: isDark
                ? Colors.white.withValues(alpha: darkBgOpacity)
                : Colors.white.withValues(alpha: lightBgOpacity),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: darkBorderOpacity)
                  : Colors.black.withValues(alpha: lightBorderOpacity),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
