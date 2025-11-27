// lib/screens/login/login_page.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../providers/auth_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  bool _obscurePassword = true;
  bool _rememberMe = false;

  bool _biometricAvailable = false;   // 设备是否支持生物识别
  bool _hasStoredCredential = false;  // 是否存过账号密码

  String _biometricLabel = '使用指纹 / 面容快速登录';

  @override
  void initState() {
    super.initState();
    _loadStoredData();
  }

  /// 读取本地存储 & 检查设备是否支持面容/指纹
  Future<void> _loadStoredData() async {
    // 1. 检查生物识别支持情况
    final canCheck = await _localAuth.canCheckBiometrics;
    final supported = await _localAuth.isDeviceSupported();
    final biometricAvailable = canCheck && supported;

    // 2. 获取设备支持的具体生物识别类型
    String label = '使用指纹 / 面容快速登录';
    if (biometricAvailable) {
      final types = await _localAuth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) {
        label = '使用面容 ID 快速登录';
      } else if (types.contains(BiometricType.fingerprint)) {
        label = '使用指纹快速登录';
      }
    }

    // 3. 从 secure storage 读取账号密码 + 记住密码标志
    final savedUser = await _storage.read(key: 'username');
    final savedPass = await _storage.read(key: 'password');
    final savedRemember = await _storage.read(key: 'remember_me');
    final remember = savedRemember == 'true';
    final hasStored = savedUser != null && savedPass != null;

    if (!mounted) return;

    setState(() {
      _biometricAvailable = biometricAvailable;
      _hasStoredCredential = hasStored;
      _rememberMe = remember;
      _biometricLabel = label;

      if (remember && hasStored) {
        _usernameCtrl.text = savedUser!;
        _passwordCtrl.text = savedPass!;
      }
    });

  }

  /// 普通密码登录
  Future<void> _handleLogin() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    final auth = Provider.of<AuthProvider>(context, listen: false);

    await auth.login(username, password);

    if (!mounted) return;

    if (auth.error == null) {
      // 登录成功后根据“记住密码”状态存/删账号密码
      if (_rememberMe) {
        await _storage.write(key: 'username', value: username);
        await _storage.write(key: 'password', value: password);
        await _storage.write(key: 'remember_me', value: 'true');
      } else {
        // 只清除自己的 key，避免误删其它数据
        await _storage.delete(key: 'username');
        await _storage.delete(key: 'password');
        await _storage.write(key: 'remember_me', value: 'false');
      }

      // 提示一下：下次可以用生物识别
      if (_biometricAvailable && _rememberMe) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已记住密码，下次可以$_biometricLabel')),
        );
      }

      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  /// 生物识别快速登录（使用已保存的账号密码）
  Future<void> _biometricLogin() async {
    if (!_hasStoredCredential) return;

    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: '请验证指纹 / 面容以快速登录',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!didAuth) return;

      final savedUser = await _storage.read(key: 'username');
      final savedPass = await _storage.read(key: 'password');

      if (savedUser == null || savedPass == null) return;

      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.login(savedUser, savedPass);

      if (!mounted) return;

      if (auth.error == null) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // 例如密码在后台被改了
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生物识别登录失败，请重新输入密码')),
        );
      }
    } catch (e) {
      // 生物识别出错（未设置面容/指纹等）
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生物识别不可用：$e')),
      );
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // 整体渐变背景
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
                      // 顶部图标 + 文案
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
                        constraints: BoxConstraints(maxWidth: cardWidth),
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
                                    onChanged: (_) {
                                      // 输入时清掉错误
                                      Provider.of<AuthProvider>(
                                        context,
                                        listen: false,
                                      ).clearError();
                                    },
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

                                  // 密码 + 显示/隐藏
                                  TextField(
                                    controller: _passwordCtrl,
                                    obscureText: _obscurePassword,
                                    onChanged: (_) {
                                      Provider.of<AuthProvider>(
                                        context,
                                        listen: false,
                                      ).clearError();
                                    },
                                    decoration: InputDecoration(
                                      labelText: '密码',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
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

                                  const SizedBox(height: 8),

                                  // 记住密码 +（预留）忘记密码
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _rememberMe,
                                            onChanged: (v) {
                                              setState(() {
                                                _rememberMe = v ?? false;
                                              });
                                            },
                                          ),
                                          const Text('记住密码'),
                                        ],
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          // TODO: 接入重置密码页面
                                        },
                                        child: const Text(
                                          '忘记密码？',
                                          style:
                                              TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // 错误提示
                                  if (auth.error != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        auth.error!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 16),

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

                                  const SizedBox(height: 16),

                                  // 生物识别按钮（仅当设备支持且有存储时显示）
                                  if (_biometricAvailable &&
                                      _hasStoredCredential)
                                    OutlinedButton.icon(
                                      onPressed: _biometricLogin,
                                      icon: const Icon(Icons.fingerprint),
                                      label: Text(_biometricLabel),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        'Powered by Souldigger Technology Co., Ltd.',
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