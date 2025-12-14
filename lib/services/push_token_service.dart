// lib/services/push_token_service.dart
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tpns_flutter_plugin/tpns_flutter_plugin.dart';

import 'api_service.dart';

class PushTokenService {
  static final PushTokenService _instance = PushTokenService._internal();
  factory PushTokenService() => _instance;
  PushTokenService._internal();

  final _storage = const FlutterSecureStorage();
  static const _lastPushedKey = 'last_pushed_device_token_v1';

  bool _inited = false;

  /// ✅ 官方插件里 XgFlutterPlugin 是“实例方法 startXg”，不是静态
  final XgFlutterPlugin _tpns = XgFlutterPlugin();

  /// 在 app 启动时尽早调用（main/initState）
  /// accessId/accessKey：用“腾讯云 TPNS 控制台”给你的那一对（不是 Apple Key）
  Future<void> initOnce({
    required String accessId,
    required String accessKey,
    bool enableDebug = false,
    String?
    clusterDomain, // 非广州集群才需要：tpns.sh.tencent.com / tpns.hk.tencent.com / tpns.sgp.tencent.com
  }) async {
    if (_inited) return;
    _inited = true;

    if (enableDebug) {
      _tpns.setEnableDebug(true);
    }

    // 非广州集群：要在 startXg 前配置域名（官方说明）
    if (clusterDomain != null && clusterDomain.trim().isNotEmpty) {
      _tpns.configureClusterDomainName(clusterDomain.trim());
    }

    // 绑定回调（官方插件的 EventHandler 是 (String res)）
    _tpns.addEventHandler(
      onRegisteredDeviceToken: (String res) async {
        await _reportTokenIfNeeded(res);
      },
      onRegisteredDone: (String res) async {
        await _reportTokenIfNeeded(res);
      },
    );

    // 启动
    _tpns.startXg(accessId, accessKey);

    // 兜底：主动读一次 token（官方插件提供 static getter）
    try {
      final t = await XgFlutterPlugin.xgToken;
      if (t != null && t.trim().isNotEmpty) {
        await _reportTokenIfNeeded(t);
      }
    } catch (_) {}
  }

  /// ✅ 你 auth_provider.dart 在调用它，所以必须保留这个方法
  /// 登录成功后调用：尝试把当前 token 再上报一遍（会去重）
  Future<void> syncIfNeeded() async {
    try {
      final t = await XgFlutterPlugin.xgToken;
      if (t != null && t.trim().isNotEmpty) {
        await _reportTokenIfNeeded(t);
      }
    } catch (_) {}
  }

  Future<void> _reportTokenIfNeeded(String raw) async {
    final api = ApiService();
    if (!api.hasToken) return;

    final token = raw.trim();
    if (token.isEmpty) return;

    final last = (await _storage.read(key: _lastPushedKey))?.trim();
    if (last == token) return;

    final platform = Platform.isIOS ? 'ios' : 'android';
    await api.registerDeviceToken(platform: platform, token: token);

    await _storage.write(key: _lastPushedKey, value: token);
  }
}
