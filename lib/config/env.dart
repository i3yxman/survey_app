// lib/config/env.dart

/// 可选环境：开发 / 预发布 / 生产
enum AppEnv { dev, stg, prod }

class Env {
  /// 从命令行 --dart-define 读取环境变量：
  ///   APP_ENV=dev / stg / prod
  static const String _envString =
      String.fromEnvironment('APP_ENV', defaultValue: 'prod');

  /// 当前环境枚举
  static const AppEnv env = _envString == 'dev'
      ? AppEnv.dev
      : _envString == 'stg'
          ? AppEnv.stg
          : AppEnv.prod;

  /// ====== 开发环境下的几种后端地址 ======

  /// 本机跑后端，Mac/Chrome 调试用
  static const String _devBaseUrlMacWeb = 'http://127.0.0.1:8000';

  /// Android 模拟器访问宿主机
  static const String _devBaseUrlAndroidEmu = 'http://10.0.2.2:8000';

  /// 真机（iOS / Android）访问你电脑的局域网 IP
  static const String _devBaseUrlLan = 'http://192.168.3.29:8000';

  /// 你当前想在【开发环境】下使用哪一个后端
  /// 可选：'mac' / 'emu' / 'lan'
  static const String _devTarget = 'lan';

  /// ====== 预发布 & 生产环境后端地址 ======

  /// 预发布（现在先跟 prod 用同一个）
  static const String _stgBaseUrl = 'http://129.211.169.81';

  /// 生产环境 —— 以后备案 + HTTPS 后改成 https://survey.souldigger.cn
  static const String _prodBaseUrl = 'http://129.211.169.81';

  /// 对外暴露的统一 baseUrl
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

  static bool get isDev => env == AppEnv.dev;
  static bool get isStg => env == AppEnv.stg;
  static bool get isProd => env == AppEnv.prod;
}