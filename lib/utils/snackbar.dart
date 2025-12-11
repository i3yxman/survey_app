// lib/utils/snackbar.dart
import 'package:flutter/material.dart';
import 'error_message.dart';

void showErrorSnackBar(
  BuildContext context,
  Object error, {
  String fallback = '操作失败，请稍后重试',
}) {
  final msg = userMessageFrom(error, fallback: fallback);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars(); // ✅ 避免叠加
  messenger.showSnackBar(
    SnackBar(content: Text(msg)),
  );
}

void showSuccessSnackBar(
  BuildContext context,
  String message,
) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(content: Text(message)),
  );
}