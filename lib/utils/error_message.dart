// lib/utils/error_message.dart

import '../services/api_service.dart';

String userMessageFrom(Object error, {String fallback = '操作失败，请稍后重试'}) {
  if (error is ApiException) {
    final msg = error.userMessage.trim();
    return msg.isNotEmpty ? msg : fallback;
  }

  var s = error.toString().trim();
  if (s.startsWith('Exception: ')) {
    s = s.replaceFirst('Exception: ', '').trim();
  }

  return s.isNotEmpty ? s : fallback;
}
