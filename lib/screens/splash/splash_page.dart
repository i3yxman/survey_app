// lib/screens/splash/splash_page.dart

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../providers/auth_provider.dart';

/// 启动页 / 冷启动页：
/// 1. 展示品牌 + 简单动画
/// 2. 判断是否已登录（以后也可以在这里做“自动登录”）
/// 3. 决定跳转到：登录页 / 首页
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _storage = const FlutterSecureStorage();
  @override
  void initState() {
    super.initState();
    // 下一帧再去做跳转，避免 build 还没完成就导航
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _decideNextPage();
    });
  }

  Future<void> _decideNextPage() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // ✅ 关键兜底：如果要求生物识别，就绝对不能自动进首页
    final requireBio =
        (await _storage.read(key: 'require_biometric')) == 'true';
    if (requireBio) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    try {
      // 冷启动恢复 token + /me 校验
      await auth.bootstrap();
    } catch (_) {
      await auth.logout();
    }

    await Future.delayed(const Duration(milliseconds: 800));
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
            // 中间的 Logo + 标题
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.9),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.04)),
                          ),
                          child: Icon(
                            Icons.checklist_rtl,
                            size: 36,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '神秘顾客调研平台',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Souldigger Technology Co., Ltd.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 底部版权
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
