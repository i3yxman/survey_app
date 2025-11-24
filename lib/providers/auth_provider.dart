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

  /// 登录
  Future<void> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      _error = '用户名和密码不能为空';
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.login(username, password);
      _currentUser = result;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
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