// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../repositories/auth_repository.dart';
import '../services/push_token_service.dart';
import '../utils/error_message.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repo;

  AuthProvider({AuthRepository? repo}) : _repo = repo ?? AuthRepository();

  bool _loading = false;
  String? _error;
  LoginResult? _currentUser;

  bool get loading => _loading;
  String? get error => _error;
  LoginResult? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  Future<void> login(
    String identifier,
    String password, {
    bool rememberAccount = false,
    bool enableBiometric = false,
  }) async {
    final u = identifier.trim();
    final p = password.trim();

    if (u.isEmpty || p.isEmpty) {
      _error = '用户名和密码不能为空';
      notifyListeners();
      return;
    }
    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repo.login(u, p);

      await _repo.setRememberAccount(rememberAccount);
      if (rememberAccount) {
        await _repo.saveUsername(u);
      } else {
        await _repo.clearUsername();
      }

      // 生物识别：开关 + 绑定账号（开启时绑定当前用户名）
      await _repo.setBiometricEnabled(enableBiometric);
      if (enableBiometric) {
        await _repo.saveBiometricUsername(u);
      } else {
        await _repo.clearBiometricUsername();
      }

      _currentUser = result;
      _error = null;

      await PushTokenService().syncIfNeeded();
    } catch (e) {
      _currentUser = null;
      _error = userMessageFrom(e, fallback: '登录失败，请稍后重试');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> bootstrap() async {
    final token = await _repo.restoreToken();
    if (token == null || token.isEmpty) return;

    try {
      final me = await _repo.me();
      _currentUser = LoginResult(
        id: (me['id'] as int?) ?? 0,
        username: (me['username'] as String?) ?? '',
        role: (me['role'] as String?) ?? '',
        status: (me['status'] as String?) ?? '',
        applicationStatus: (me['application_status'] as String?),
        token: token,
      );

      _error = null;

      await PushTokenService().syncIfNeeded();
      notifyListeners();
    } catch (_) {
      await _repo.logout();
      _currentUser = null;
      _error = null;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    _error = null;
    notifyListeners();

    // 退出时会清 token，并自动关闭生物识别（见 TokenStore.clearSessionButMaybeKeepUsername）
    await _repo.logout(keepUsernameIfRemembered: true);
  }

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
    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _repo.changePassword(oldPassword: oldTrim, newPassword: newTrim);
      _error = null;
    } catch (e) {
      _error = userMessageFrom(e, fallback: '修改密码失败，请稍后重试');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> requestPasswordReset(String identifier) {
    return _repo.requestPasswordReset(identifier: identifier.trim());
  }

  // ------- 给 UI 用的一些查询 -------
  Future<bool> biometricEnabled() => _repo.biometricEnabled();
  Future<bool> rememberAccount() => _repo.rememberAccount();
  Future<String?> savedUsername() => _repo.readUsername();
  Future<String?> biometricUsername() => _repo.readBiometricUsername();
  Future<bool> hasToken() => _repo.hasToken();

  Future<void> setRememberAccount(bool v, {String? username}) async {
    await _repo.setRememberAccount(v);
    if (v && username != null && username.trim().isNotEmpty) {
      await _repo.saveUsername(username.trim());
    }
    if (!v) {
      await _repo.clearUsername();
    }
  }

  /// ✅ 登录页会调用：setBiometricEnabled(nv, username: xxx)
  /// - 开启：必须绑定用户名
  /// - 关闭：清绑定账号
  Future<void> setBiometricEnabled(bool v, {String? username}) async {
    await _repo.setBiometricEnabled(v);
    if (v) {
      final u = (username ?? '').trim();
      if (u.isNotEmpty) {
        await _repo.saveBiometricUsername(u);
      }
    } else {
      await _repo.clearBiometricUsername();
    }
  }
}
