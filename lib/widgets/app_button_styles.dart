// lib/widgets/app_button_styles.dart

import 'package:flutter/material.dart';

class AppButtonStyles {
  static ButtonStyle compactElevated(BuildContext context) {
    return ElevatedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle compactOutlined(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle blockText(BuildContext context) {
    return TextButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      textStyle: Theme.of(context).textTheme.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  static ButtonStyle secondaryOutlined(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      textStyle: Theme.of(context).textTheme.labelLarge,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      foregroundColor: scheme.onSurface,
    );
  }

  static ButtonStyle dangerFilled(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ElevatedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      textStyle: Theme.of(context).textTheme.labelLarge,
      backgroundColor: scheme.error,
      foregroundColor: scheme.onError,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}
