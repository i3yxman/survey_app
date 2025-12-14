// lib/widgets/app_logo_header.dart

import 'package:flutter/material.dart';

class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({
    super.key,
    this.title = '神秘顾客调研平台',
    this.subtitle = 'Souldigger Technology Co., Ltd.',
    this.icon = Icons.checklist_rtl,
    this.iconSize = 36,
    this.circleSize = 72,
    this.spacingAfter = 24,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final double iconSize;
  final double circleSize;
  final double spacingAfter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
          ),
          child: Icon(icon, size: iconSize, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: spacingAfter),
      ],
    );
  }
}
