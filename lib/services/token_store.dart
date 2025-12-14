// lib/services/token_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static const _tokenKey = 'auth_token';

  // 生物识别开关 + 绑定账号
  static const _bioKey = 'biometric_enabled';
  static const _bioUsernameKey = 'biometric_username';

  // 记住账号（username only）
  static const _rememberAccountKey = 'remember_account';
  static const _usernameKey = 'saved_username';

  final _s = const FlutterSecureStorage();

  // ---------- token ----------
  Future<void> saveToken(String token) =>
      _s.write(key: _tokenKey, value: token);

  Future<String?> readToken() => _s.read(key: _tokenKey);

  Future<void> clearToken() => _s.delete(key: _tokenKey);

  Future<bool> hasToken() async {
    final t = await readToken();
    return t != null && t.trim().isNotEmpty;
  }

  // ---------- biometric ----------
  Future<void> setBiometricEnabled(bool v) =>
      _s.write(key: _bioKey, value: v ? 'true' : 'false');

  Future<bool> biometricEnabled() async =>
      (await _s.read(key: _bioKey)) == 'true';

  Future<void> saveBiometricUsername(String username) =>
      _s.write(key: _bioUsernameKey, value: username);

  Future<String?> readBiometricUsername() => _s.read(key: _bioUsernameKey);

  Future<void> clearBiometricUsername() => _s.delete(key: _bioUsernameKey);

  // ---------- remember account (username only) ----------
  Future<void> setRememberAccount(bool v) =>
      _s.write(key: _rememberAccountKey, value: v ? 'true' : 'false');

  Future<bool> rememberAccount() async =>
      (await _s.read(key: _rememberAccountKey)) == 'true';

  Future<void> saveUsername(String username) =>
      _s.write(key: _usernameKey, value: username);

  Future<String?> readUsername() => _s.read(key: _usernameKey);

  Future<void> clearUsername() => _s.delete(key: _usernameKey);

  /// ✅ 退出登录时的策略（你现在的问题主要出在这里）
  /// - token：必须清掉
  /// - 生物识别：必须关掉 + 清绑定账号（否则会出现“勾着但没 token”的假状态）
  /// - username：只有 rememberAccount=true 才保留
  Future<void> clearSessionButMaybeKeepUsername() async {
    await clearToken();

    // 关键：退出后关闭生物识别，避免 UI 勾选残留
    await setBiometricEnabled(false);
    await clearBiometricUsername();

    final keep = await rememberAccount();
    if (!keep) {
      await clearUsername();
    }
  }
}
