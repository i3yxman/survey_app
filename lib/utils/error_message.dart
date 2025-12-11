// lib/utils/error_message.dart

import '../services/api_service.dart';

String userMessageFrom(Object error, {String fallback = '操作失败，请稍后重试'}) {
  // 1) 你的 ApiException：直接拿 userMessage（已经是人话）
  if (error is ApiException) return error.userMessage;

  // 2) 其他 Exception：尽量 toString，但避免把 "Exception: xxx" 原样给用户
  final s = error.toString();
  if (s.startsWith('Exception: ')) return s.replaceFirst('Exception: ', '').trim();

  // 3) 兜底
  return s.isNotEmpty ? s : fallback;
}