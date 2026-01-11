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

  String? _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  LoginResult? _applyMe(LoginResult? base, Map<String, dynamic> me) {
    if (base == null) return null;
    final fullName = _readString(me, ['full_name', 'fullName']) ??
        [
          _readString(me, ['first_name']) ?? '',
          _readString(me, ['last_name']) ?? '',
        ].where((s) => s.isNotEmpty).join(' ');
    return base.copyWith(
      email: _readString(me, ['email']),
      phone: _readString(me, ['phone', 'mobile', 'phone_number']),
      fullName: fullName.isNotEmpty ? fullName : null,
      gender: _readString(me, ['gender']),
      idNumber: _readString(me, ['id_number', 'idNumber']),
      province: _readString(me, ['province']),
      city: _readString(me, ['city']),
      address: _readString(me, ['address']),
      alipayAccount: _readString(me, ['alipay_account', 'alipayAccount']),
      notificationSettings: (me['notification_settings'] as Map?)?.cast<String, dynamic>(),
    );
  }

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
    double? lastLoginLat,
    double? lastLoginLng,
    String? lastLoginCity,
    String? lastLoginAddress,
  }) async {
    final u = identifier.trim();
    final p = password.trim();

    if (u.isEmpty || p.isEmpty) {
      _error = '账号和密码不能为空';
      notifyListeners();
      return;
    }
    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repo.login(
        u,
        p,
        lastLoginLat: lastLoginLat,
        lastLoginLng: lastLoginLng,
        lastLoginCity: lastLoginCity,
        lastLoginAddress: lastLoginAddress,
      );

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

      try {
        final me = await _repo.me();
        _currentUser = _applyMe(_currentUser, me);
      } catch (_) {}

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
        email: _readString(me, ['email']),
        phone: _readString(me, ['phone', 'mobile', 'phone_number']),
        fullName: _readString(me, ['full_name', 'fullName']),
        gender: _readString(me, ['gender']),
        idNumber: _readString(me, ['id_number', 'idNumber']),
        province: _readString(me, ['province']),
        city: _readString(me, ['city']),
        address: _readString(me, ['address']),
        alipayAccount: _readString(me, ['alipay_account', 'alipayAccount']),
        notificationSettings: (me['notification_settings'] as Map?)?.cast<String, dynamic>(),
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

  Future<void> refreshProfile() async {
    if (_currentUser == null) return;
    try {
      final me = await _repo.me();
      _currentUser = _applyMe(_currentUser, me);
      notifyListeners();
    } catch (_) {}
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

  Future<void> updateLastLoginLocation({
    double? lat,
    double? lng,
    String? city,
    String? address,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (lat != null) payload['last_login_lat'] = lat;
      if (lng != null) payload['last_login_lng'] = lng;
      if (city != null && city.trim().isNotEmpty) {
        payload['last_login_city'] = city.trim();
      }
      if (address != null && address.trim().isNotEmpty) {
        payload['last_login_address'] = address.trim();
      }
      if (payload.isEmpty) return;
      final me = await _repo.updateProfile(payload);
      _currentUser = _applyMe(_currentUser, me);
      notifyListeners();
    } catch (_) {}
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

  Future<void> updateProfile(Map<String, dynamic> payload) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _repo.updateProfile(payload);
      if (_currentUser != null) {
        _currentUser = _applyMe(_currentUser, data);
      }
      _error = null;
    } catch (e) {
      _error = userMessageFrom(e, fallback: '更新资料失败，请稍后重试');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
