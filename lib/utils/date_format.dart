// lib/utils/date_format.dart

import 'package:intl/intl.dart';

final DateFormat _ymd = DateFormat('yyyy-MM-dd');
final DateFormat _ymdHm = DateFormat('yyyy-MM-dd HH:mm');

String formatDate(DateTime? dt) {
  if (dt == null) return '-';
  return _ymd.format(dt.toLocal());
}

String formatDateZh(DateTime? dt) {
  if (dt == null) return '-';
  return DateFormat('yyyy年MM月dd日').format(dt.toLocal());
}

String formatDateTime(DateTime? dt) {
  if (dt == null) return '-';
  return _ymdHm.format(dt.toLocal());
}

DateTime? parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}
