// lib/repositories/auth_repository.dart
import '../services/api_service.dart';
import '../services/token_store.dart';
import '../models/api_models.dart';

class AuthRepository {
  final ApiService _api;
  final TokenStore _store;

  AuthRepository({ApiService? api, TokenStore? store})
    : _api = api ?? ApiService(),
      _store = store ?? TokenStore();

  // ---------- login / me ----------
  Future<LoginResult> login(String identifier, String password) async {
    final res = await _api.login(identifier, password);
    await _store.saveToken(res.token);
    return res;
  }

  Future<Map<String, dynamic>> me() => _api.me();

  /// App 启动恢复 token，并注入 ApiService header
  Future<String?> restoreToken() async {
    final t = await _store.readToken();
    if (t != null && t.trim().isNotEmpty) {
      _api.setAuthToken(t.trim());
      return t.trim();
    }
    return null;
  }

  // ---------- account prefs ----------
  Future<void> setRememberAccount(bool v) => _store.setRememberAccount(v);
  Future<bool> rememberAccount() => _store.rememberAccount();

  Future<void> saveUsername(String username) => _store.saveUsername(username);
  Future<String?> readUsername() => _store.readUsername();
  Future<void> clearUsername() => _store.clearUsername();

  // ---------- biometric prefs ----------
  Future<void> setBiometricEnabled(bool v) => _store.setBiometricEnabled(v);
  Future<bool> biometricEnabled() => _store.biometricEnabled();

  Future<void> saveBiometricUsername(String username) =>
      _store.saveBiometricUsername(username);

  Future<String?> readBiometricUsername() => _store.readBiometricUsername();

  Future<void> clearBiometricUsername() => _store.clearBiometricUsername();

  Future<bool> hasToken() => _store.hasToken();

  // ---------- logout ----------
  Future<void> logout({bool keepUsernameIfRemembered = true}) async {
    _api.clearAuthToken();
    if (keepUsernameIfRemembered) {
      await _store.clearSessionButMaybeKeepUsername();
    } else {
      await _store.clearToken();
      await _store.setBiometricEnabled(false);
      await _store.clearBiometricUsername();
      await _store.clearUsername();
    }
  }

  // ---------- passthrough ----------
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) => _api.changePassword(oldPassword: oldPassword, newPassword: newPassword);

  Future<String> requestPasswordReset({required String identifier}) =>
      _api.requestPasswordReset(identifier: identifier);
}
