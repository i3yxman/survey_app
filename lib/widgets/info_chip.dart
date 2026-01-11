// lib/widgets/info_chip.dart

import 'package:flutter/material.dart';

class InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  const InfoChip({
    super.key,
    required this.icon,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final chipTextStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
      fontWeight: FontWeight.w500,
    );

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        // ✅ 关键：让 Row 吃满可用宽度，给文本一个“可约束的空间”
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 4),

          // ✅ 关键：用 Expanded 让文本拿到剩余宽度，自动换行/截断都不会炸
          Expanded(
            child: Text(
              text,
              style: chipTextStyle,
              maxLines: 2, // 你想一行就改成 1
              overflow: TextOverflow.ellipsis, // 不会溢出
              softWrap: true,
            ),
          ),
        ],
      ),
    );

    // ✅ 关键：Wrap 里每个 child 默认“无宽度约束”，这里强行给一个最大宽度
    // 你可以按 UI 需要调 320/360
    final constrained = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: child,
    );

    if (onTap == null) return constrained;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: constrained,
    );
  }
}
