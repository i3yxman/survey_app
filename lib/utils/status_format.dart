String formatStatusLabel(String? status) {
  if (status == null || status.trim().isEmpty) return '-';
  final normalized = status.trim().toLowerCase();
  const mapping = {
    'pending': '开放（Open）',
    'open': '开放（Open）',
    'new': '新建（New）',
    'incomplete': '未完成（Incomplete）',
    'submitted': '待审核（Submitted）',
    'needs_revision': '待修改（Needs Revision）',
    'approved': '已通过（Approved）',
    'cancelled': '已作废（Cancelled）',
    'draft': '草稿（Draft）',
    'resubmitted': '已重新提交（Resubmitted）',
    'in_progress': '进行中（In Progress）',
    'reviewed': '已审核（Reviewed）',
  };
  if (mapping.containsKey(normalized)) return mapping[normalized]!;
  final english = normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
  return english;
}
