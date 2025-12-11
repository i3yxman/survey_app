// lib/providers/auth_provider.dart

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../services/api_service.dart';
import '../utils/error_message.dart';

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
      _error = userMessageFrom(e, fallback: '登录失败，请稍后重试');
    } catch (e) {
      _currentUser = null;
      _error = userMessageFrom(e, fallback: '登录失败，请稍后重试');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 修改密码
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final oldTrim = oldPassword.trim();
    final newTrim = newPassword.trim();

    if (oldTrim.isEmpty || newTrim.isEmpty) {
      _error = '密码不能为空';
      notifyListeners();
      return;
    }

    // 防止和登录同时提交
    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.changePassword(oldPassword: oldTrim, newPassword: newTrim);
      // 修改成功后，清空错误
      _error = null;
    } on ApiException catch (e) {
      _error = userMessageFrom(e, fallback: '修改密码失败，请稍后重试');
    } catch (e) {
      _error = userMessageFrom(e, fallback: '修改密码失败，请稍后重试');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 忘记密码：让后端给出下一步提示（不改 loading / error，直接抛异常）
  Future<String> requestPasswordReset(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      // 直接抛 ApiException，外层用 showErrorSnackBar(e) 即可
      throw ApiException(userMessage: '请输入用户名或手机号');
    }

    try {
      final msg = await _api.requestPasswordReset(identifier: trimmed);
      return msg;
    } on ApiException catch (e) {
      // ApiService 已经封装成“人话”了，直接抛出去
      rethrow;
    } catch (e) {
      // 包一层 ApiException，保证外层永远拿到 ApiException
      throw ApiException(
        userMessage: userMessageFrom(e, fallback: '请求失败，请稍后重试'),
        body: e.toString(),
      );
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
