// lib/providers/auth_provider.dart

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api;

  AuthProvider({ApiService? api}) : _api = api ?? ApiService();

  bool _loading = false;
  String? _error;
  LoginResult? _currentUser;

  bool get loading => _loading;
  String? get error => _error;
  LoginResult? get currentUser => _currentUser;

  /// 是否已经登录
  bool get isLoggedIn => _currentUser != null;

  /// 主动清空错误（比如在用户开始重新输入账号密码时调用）
  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  /// 登录
  Future<void> login(String username, String password) async {
    final trimmedUser = username.trim();
    final trimmedPass = password.trim();

    if (trimmedUser.isEmpty || trimmedPass.isEmpty) {
      _error = '用户名和密码不能为空';
      notifyListeners();
      return;
    }

    // 防止重复点击“登录”按钮导致多次请求
    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.login(trimmedUser, trimmedPass);
      _currentUser = result;
      _error = null; // 登录成功时确保错误清空
    } on ApiException catch (e) {
      _currentUser = null;
      _error = e.message;
    } catch (e) {
      _currentUser = null;
      _error = '未知错误: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 退出登录
  Future<void> logout() async {
    _currentUser = null;
    _error = null;

    // 清掉 Basic Auth（设为空字符串即可）
    _api.setAuthBasic('');

    notifyListeners();
  }
}