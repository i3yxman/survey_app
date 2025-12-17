// lib/screens/splash/splash_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';

import '../../providers/auth_provider.dart';
import '../../services/push_token_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/app_logo_header.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _localAuth = LocalAuthentication();

  // ✅ TPNS 从 dart-define 读取
  static const _tpnsAccessId = String.fromEnvironment('TPNS_ACCESS_ID');
  static const _tpnsAccessKey = String.fromEnvironment('TPNS_ACCESS_KEY');
  static const _tpnsClusterDomain = String.fromEnvironment(
    'TPNS_CLUSTER_DOMAIN',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _decideNextPage();
    });
  }

  Future<void> _decideNextPage() async {
    final auth = context.read<AuthProvider>();

    // ✅ 0) 初始化推送（不影响你原有流程）
    if (_tpnsAccessId.isNotEmpty && _tpnsAccessKey.isNotEmpty) {
      await PushTokenService().initOnce(
        accessId: _tpnsAccessId,
        accessKey: _tpnsAccessKey,
        enableDebug: true,
        clusterDomain: _tpnsClusterDomain.isEmpty ? null : _tpnsClusterDomain,
      );
    }

    // 1) 是否有 token
    final hasToken = await auth.hasToken();
    if (!hasToken) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    // 2) 若启用了生物识别，则在 Splash 弹
    final bioEnabled = await auth.biometricEnabled();
    if (bioEnabled) {
      try {
        final canCheck = await _localAuth.canCheckBiometrics;
        final supported = await _localAuth.isDeviceSupported();
        if (canCheck && supported) {
          final ok = await _localAuth.authenticate(
            localizedReason: '请验证指纹/面容以进入应用',
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
            ),
          );
          if (!ok) {
            if (!mounted) return;
            Navigator.of(context).pushReplacementNamed('/login');
            return;
          }
        }
      } catch (_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
    }

    // 3) 恢复登录态
    await auth.bootstrap();

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacementNamed(auth.currentUser != null ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF000000), Color(0xFF050506)]
                : const [Color(0xFFF2F2F7), Color(0xFFE5E5EA)],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: GlassCard(
                borderRadius: 32,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppLogoHeader(spacingAfter: 16),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Text(
                  '© ${DateTime.now().year} Souldigger',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
