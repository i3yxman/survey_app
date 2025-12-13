// lib/providers/auth_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/api_models.dart';
import '../services/api_service.dart';
import '../repositories/auth_repository.dart';
import '../utils/error_message.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repo;
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  AuthProvider({AuthRepository? repo}) : _repo = repo ?? AuthRepository();

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
  Future<void> login(
    String identifier,
    String password, {
    bool rememberMe = false, // ✅ 新增：是否把 token 持久化到本地
  }) async {
    final trimmedUser = identifier.trim();
    final trimmedPass = password.trim();

    if (trimmedUser.isEmpty || trimmedPass.isEmpty) {
      _error = '用户名和密码不能为空';
      notifyListeners();
      return;
    }

    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repo.login(trimmedUser, trimmedPass);

      final token = result.token.trim();

      // ✅ 关键补丁：确保全局 ApiService 已经 setAuthToken
      if (token.isNotEmpty) {
        _repo.setAuthToken(token);
      }

      if (rememberMe && token.isNotEmpty) {
        await _storage.write(key: _tokenKey, value: token);
      } else {
        await _storage.delete(key: _tokenKey);
      }

      _currentUser = result;
      _error = null;
    } catch (e) {
      _currentUser = null;
      _error = userMessageFrom(e, fallback: '登录失败，请稍后重试');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// App 启动时：尝试从本地恢复 token，并用 /me 校验是否有效
  Future<void> bootstrap({bool force = false}) async {
    // ⛔️ 只有非 force 情况下，才拦 require_biometric
    if (!force) {
      final requireBio =
          (await _storage.read(key: 'require_biometric')) == 'true';
      if (requireBio) return;
    }

    final savedRaw = await _storage.read(key: _tokenKey);
    final saved = savedRaw?.trim();
    if (saved == null || saved.isEmpty) return;

    _repo.setAuthToken(saved);

    try {
      final me = await _repo.me();

      _currentUser = LoginResult(
        id: (me['id'] as int?) ?? 0,
        username: (me['username'] as String?) ?? '',
        role: (me['role'] as String?) ?? '',
        status: (me['status'] as String?) ?? '',
        applicationStatus: (me['application_status'] as String?),
        token: saved,
      );

      _error = null;
      notifyListeners();
    } catch (_) {
      await _storage.delete(key: _tokenKey);
      _repo.clearAuthToken();
      _currentUser = null;
      _error = null;
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
      await _repo.changePassword(oldPassword: oldTrim, newPassword: newTrim);
      // 修改成功后，清空错误
      _error = null;
    } catch (e) {
      _error = userMessageFrom(e, fallback: '修改密码失败，请稍后重试');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> requestPasswordReset(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      throw ApiException(userMessage: '请输入用户名或手机号');
    }

    try {
      return await _repo.requestPasswordReset(identifier: trimmed);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        userMessage: userMessageFrom(e, fallback: '请求失败，请稍后重试'),
        body: e.toString(),
      );
    }
  }

  /// 退出登录：必须阻止下次自动进入首页；只能生物识别/重新输入密码
  Future<void> logout() async {
    _currentUser = null;
    _error = null;

    // 退出时，永远清掉内存里的 Authorization
    _repo.clearAuthToken();

    // 如果用户勾了“记住账号”，我们保留 token 但强制下次必须生物识别才能恢复
    final remember = (await _storage.read(key: 'remember_me')) == 'true';

    if (remember) {
      await _storage.write(key: 'require_biometric', value: 'true');
      // 注意：这里不删 token，留给生物识别后 bootstrap 使用
    } else {
      // 没记住账号：直接清掉 token，必须重新输入密码登录
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: 'require_biometric');
    }

    notifyListeners();
  }
}
