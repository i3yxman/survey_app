// lib/widgets/avoid_dates_chip.dart

import 'package:flutter/material.dart';
import '../utils/date_format.dart';

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
  String _fmtRange(Map<String, String> r) {
    final s = r['start'] ?? '';
    final e = r['end'] ?? '';
    if (s.isEmpty) return '';
    final sText = formatDateZh(parseDate(s));
    if (s == e || e.isEmpty) return sText;
    final eText = formatDateZh(parseDate(e));
    return '$sText–$eText';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 优先用 ranges；没有就用 rawDates 兜底
    final items = widget.ranges.isNotEmpty
        ? widget.ranges.map(_fmtRange).where((x) => x.isNotEmpty).toList()
        : widget.rawDates
            .map((d) => formatDateZh(parseDate(d)))
            .where((x) => x.isNotEmpty && x != '-')
            .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    final text = '避访日期：${items.join('、')}';

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
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
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall,
                maxLines: null,
                overflow: TextOverflow.visible,
                softWrap: true,
              ),
            ),
          ],
        ),
      );
  }
}
