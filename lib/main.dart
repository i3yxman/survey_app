// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';

void main() {
  // 确保 binding 初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 关闭 Provider 的类型检查断言（可选，只是为了避免某些 debug 警告）
  Provider.debugCheckInvalidValueType = null;

  // 启动 App
  runApp(const MyApp());
}