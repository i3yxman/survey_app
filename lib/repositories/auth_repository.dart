// lib/repositories/auth_repository.dart

import '../services/api_service.dart';
import '../models/api_models.dart';

/// AuthRepository —— 登录/登出/改密/忘记密码/恢复登录
class AuthRepository {
  final ApiService _api;

  AuthRepository({ApiService? api}) : _api = api ?? ApiService();

  Future<LoginResult> login(String identifier, String password) {
    return _api.login(identifier, password);
  }

  Future<Map<String, dynamic>> me() {
    return _api.me();
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _api.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  Future<String> requestPasswordReset({required String identifier}) {
    return _api.requestPasswordReset(identifier: identifier);
  }

  void setAuthToken(String token) {
    _api.setAuthToken(token);
  }

  void clearAuthToken() {
    _api.clearAuthToken();
  }
}
