String formatCurrency(double? amount, String? currency) {
  if (amount == null) return '';
  final code = (currency ?? 'CNY').toUpperCase();
  final fixed = amount.toStringAsFixed(2);
  if (code == 'CNY' || code == 'RMB') {
    return '$fixed 元';
  }
  return '$code $fixed';
}
