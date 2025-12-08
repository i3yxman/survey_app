// lib/config/env.dart

enum AppEnv { dev, stg, prod }

class Env {
  static const String _envString =
      String.fromEnvironment('APP_ENV', defaultValue: 'prod');

  static const AppEnv env = _envString == 'dev'
      ? AppEnv.dev
      : _envString == 'stg'
          ? AppEnv.stg
          : AppEnv.prod;

  static const String _devBaseUrlMacWeb = 'http://127.0.0.1:8000';
  static const String _devBaseUrlAndroidEmu = 'http://10.0.2.2:8000';
  static const String _devBaseUrlLan = 'http://Klans-MacBook-Pro-Black.local:8000';

  static const String _devTarget = 'lan';

  static const String _stgBaseUrl = 'http://129.211.169.81';
  static const String _prodBaseUrl = 'http://129.211.169.81';

  /// 供 ApiService 使用
  static String get apiBaseUrl => baseUrl;

  static String get baseUrl {
    switch (env) {
      case AppEnv.dev:
        switch (_devTarget) {
          case 'mac':
            return _devBaseUrlMacWeb;
          case 'emu':
            return _devBaseUrlAndroidEmu;
          case 'lan':
          default:
            return _devBaseUrlLan;
        }
      case AppEnv.stg:
        return _stgBaseUrl;
      case AppEnv.prod:
        return _prodBaseUrl;
    }
  }
}