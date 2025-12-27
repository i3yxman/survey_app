// lib/widgets/avoid_dates_chip.dart

import 'package:flutter/material.dart';

class AvoidDatesChip extends StatefulWidget {
  final List<String> rawDates; // 用于 fallback
  final List<Map<String, String>> ranges; // 后端的压缩区间
  final int foldThreshold; // 超过多少条就折叠

  const AvoidDatesChip({
    super.key,
    required this.rawDates,
    required this.ranges,
    this.foldThreshold = 6,
  });

  @override
  State<AvoidDatesChip> createState() => _AvoidDatesChipState();
}

class _AvoidDatesChipState extends State<AvoidDatesChip> {
  bool _expanded = false;

  String _fmtRange(Map<String, String> r) {
    final s = r['start'] ?? '';
    final e = r['end'] ?? '';
    if (s.isEmpty) return '';
    if (s == e || e.isEmpty) return s;
    return '$s–$e';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 优先用 ranges；没有就用 rawDates 兜底
    final items = widget.ranges.isNotEmpty
        ? widget.ranges.map(_fmtRange).where((x) => x.isNotEmpty).toList()
        : widget.rawDates;

    if (items.isEmpty) return const SizedBox.shrink();

    final shouldFold = items.length > widget.foldThreshold;
    final shown = (!_expanded && shouldFold)
        ? items.take(widget.foldThreshold).toList()
        : items;

    final suffix = shouldFold
        ? (_expanded ? ' 收起' : ' 等${items.length}段，展开')
        : '';

    final text = '避访日期：${shown.join('、')}$suffix';

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: shouldFold ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block_outlined,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.bodySmall,
                maxLines: _expanded ? 6 : 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
