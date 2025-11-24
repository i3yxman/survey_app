// lib/screens/login/login_page.dart

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    final auth = Provider.of<AuthProvider>(context, listen: false);

    await auth.login(username, password);

    if (!mounted) return;

    if (auth.error == null) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // 整体浅色 / 深色背景，偏系统设置页风格
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [
                    Color(0xFF000000),
                    Color(0xFF050506),
                  ]
                : const [
                    Color(0xFFF2F2F7),
                    Color(0xFFE5E5EA),
                  ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              final cardWidth = isWide ? 480.0 : double.infinity;

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部小图标 + 文案
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.04)),
                        ),
                        child: Icon(
                          Icons.checklist_rtl,
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '评估员登录',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '登录后即可查看当前任务和任务大厅',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.65),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // 中间玻璃质感卡片
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: cardWidth,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                color: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : Colors.white.withOpacity(0.82),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.10)
                                      : Colors.black.withOpacity(0.04),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 用户名
                                  TextField(
                                    controller: _usernameCtrl,
                                    decoration: InputDecoration(
                                      labelText: '用户名',
                                      prefixIcon:
                                          const Icon(Icons.person_outline),
                                      filled: true,
                                      fillColor: isDark
                                          ? Colors.white.withOpacity(0.02)
                                          : Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // 密码
                                  TextField(
                                    controller: _passwordCtrl,
                                    decoration: InputDecoration(
                                      labelText: '密码',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      filled: true,
                                      fillColor: isDark
                                          ? Colors.white.withOpacity(0.02)
                                          : Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                    obscureText: true,
                                  ),

                                  const SizedBox(height: 12),

                                  // 错误提示
                                  if (auth.error != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${auth.error}',
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 20),

                                  // 登录按钮
                                  auth.loading
                                      ? const SizedBox(
                                          height: 44,
                                          width: 44,
                                          child: CircularProgressIndicator
                                              .adaptive(),
                                        )
                                      : SizedBox(
                                          width: double.infinity,
                                          height: 44,
                                          child: ElevatedButton(
                                            onPressed: _handleLogin,
                                            style: ElevatedButton.styleFrom(
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: const Text('登录'),
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        'Powered by 神秘顾客调研平台',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}