// lib/screens/login/login_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';

import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../utils/snackbar.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/app_logo_header.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  final _localAuth = LocalAuthentication();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _enableBiometric = false;

  bool _biometricAvailable = false;
  bool _hasStoredCredential = false;
  String _biometricLabel = '使用指纹 / 面容快速登录';

  String? _boundUsername;

  @override
  void initState() {
    super.initState();
    _loadStoredData();
  }

  Future<void> _loadStoredData() async {
    final auth = context.read<AuthProvider>();

    bool biometricAvailable = false;
    String label = '使用指纹 / 面容快速登录';

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      biometricAvailable = canCheck && supported;

      if (biometricAvailable) {
        final types = await _localAuth.getAvailableBiometrics();
        if (types.contains(BiometricType.face)) {
          label = '使用面容 ID 快速登录';
        } else if (types.contains(BiometricType.fingerprint)) {
          label = '使用指纹快速登录';
        }
      }
    } catch (_) {}

    final hasToken = await auth.hasToken();
    final bioEnabled = await auth.biometricEnabled();
    final remember = await auth.rememberAccount();
    final savedUser = await auth.savedUsername();
    final bioUser = await auth.biometricUsername();

    final bound = (bioUser?.trim().isNotEmpty ?? false)
        ? bioUser!.trim()
        : (savedUser?.trim().isNotEmpty ?? false)
        ? savedUser!.trim()
        : null;

    if (!mounted) return;
    setState(() {
      _biometricAvailable = biometricAvailable;
      _biometricLabel = label;
      _hasStoredCredential = hasToken;
      _enableBiometric = bioEnabled;
      _rememberMe = remember;
      _boundUsername = bound;

      if (_usernameCtrl.text.trim().isEmpty) {
        if (remember && savedUser != null && savedUser.trim().isNotEmpty) {
          _usernameCtrl.text = savedUser.trim();
        } else if (!remember && bound != null && bound.isNotEmpty) {
          _usernameCtrl.text = bound;
        }
      }
    });
  }

  Future<void> _handleLogin() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    final canUseBiometric =
        _biometricAvailable && _enableBiometric && _hasStoredCredential;

    if (password.trim().isEmpty && canUseBiometric) {
      await _biometricLogin();
      return;
    }

    final auth = context.read<AuthProvider>();
    final loc = context.read<LocationProvider>();
    await loc.ensureLocation();
    await auth.login(
      username,
      password,
      rememberAccount: _rememberMe,
      enableBiometric: _enableBiometric,
      lastLoginLat: loc.position?.latitude,
      lastLoginLng: loc.position?.longitude,
      lastLoginCity: loc.city,
      lastLoginAddress: loc.address,
    );

    if (!mounted) return;

    if (auth.error == null) {
      await _loadStoredData();
      if (!mounted) return;

      if (_biometricAvailable && _enableBiometric) {
        showSuccessSnackBar(context, '已开启生物识别登录');
      }

      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _biometricLogin() async {
    final canUseBiometric =
        _biometricAvailable && _enableBiometric && _hasStoredCredential;

    if (!canUseBiometric) {
      showErrorSnackBar(context, '未开启生物识别或尚未登录过');
      return;
    }

    final inputUsername = _usernameCtrl.text.trim();
    if (_boundUsername != null &&
        _boundUsername!.trim().isNotEmpty &&
        inputUsername.isNotEmpty &&
        inputUsername != _boundUsername) {
      showErrorSnackBar(context, '当前输入账号与已绑定账号不一致');
      return;
    }

    try {
      final ok = await _localAuth.authenticate(
        localizedReason: '请验证指纹 / 面容以快速登录',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!ok) return;

      final auth = context.read<AuthProvider>();
      await auth.bootstrap();

      if (!mounted) return;

      if (auth.currentUser != null) {
        final loc = context.read<LocationProvider>();
        await loc.ensureLocation();
        await auth.updateLastLoginLocation(
          lat: loc.position?.latitude,
          lng: loc.position?.longitude,
          city: loc.city,
          address: loc.address,
        );
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        showErrorSnackBar(context, '快速登录失败，请使用密码登录');
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '生物识别不可用');
    }
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  InputDecoration _iosFieldDecoration({
    required bool isDark,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Theme.of(
          context,
        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          width: 1,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();

    final canUseBiometric =
        _biometricAvailable && _enableBiometric && _hasStoredCredential;

    return Scaffold(
      body: GestureDetector(
        onTap: _dismissKeyboard,
        child: Container(
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

                return Stack(
                  children: [
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardWidth),
                          child: GlassCard(
                            borderRadius: 32,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppLogoHeader(spacingAfter: 18),

                                // 账号
                                TextField(
                                  controller: _usernameCtrl,
                                  focusNode: _usernameFocus,
                                  textInputAction: TextInputAction.next,
                                  keyboardType: TextInputType.text,
                                  onChanged: (_) =>
                                      context.read<AuthProvider>().clearError(),
                                  onSubmitted: (_) {
                                    FocusScope.of(
                                      context,
                                    ).requestFocus(_passwordFocus);
                                  },
                                  decoration: _iosFieldDecoration(
                                    isDark: isDark,
                                    hint: '账号 / 邮箱',
                                    icon: Icons.person_outline,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // 密码
                                TextField(
                                  controller: _passwordCtrl,
                                  focusNode: _passwordFocus,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (_) =>
                                      context.read<AuthProvider>().clearError(),
                                  onSubmitted: (_) => _handleLogin(),
                                  decoration: _iosFieldDecoration(
                                    isDark: isDark,
                                    hint: '密码',
                                    icon: Icons.lock_outline,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // 错误提示（iOS inline 风格）
                                if (auth.error != null) ...[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        auth.error!,
                                        style: TextStyle(
                                          color: Colors.redAccent.withValues(
                                            alpha: 0.95,
                                          ),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ],

                                // 记住账号 + 忘记密码（Switch.adaptive）
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Switch.adaptive(
                                          value: _rememberMe,
                                          onChanged: (v) async {
                                            setState(() => _rememberMe = v);

                                            await context
                                                .read<AuthProvider>()
                                                .setRememberAccount(
                                                  v,
                                                  username: _usernameCtrl.text,
                                                );

                                            await _loadStoredData();
                                          },
                                        ),
                                        const SizedBox(width: 6),
                                        const Text('记住账号'),
                                      ],
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pushNamed(
                                        context,
                                        '/forgot-password',
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                      ),
                                      child: Text(
                                        '忘记密码？',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // 生物识别开关（Switch.adaptive）
                                Row(
                                  children: [
                                    Switch.adaptive(
                                      value: _enableBiometric,
                                      onChanged: _biometricAvailable
                                          ? (v) async {
                                              if (v &&
                                                  _usernameCtrl.text
                                                      .trim()
                                                      .isEmpty) {
                                                showErrorSnackBar(
                                                  context,
                                                  '请先输入账号，再开启生物识别',
                                                );
                                                return;
                                              }

                                              setState(
                                                () => _enableBiometric = v,
                                              );

                                              await context
                                                  .read<AuthProvider>()
                                                  .setBiometricEnabled(
                                                    v,
                                                    username:
                                                        _usernameCtrl.text,
                                                  );

                                              if (v) {
                                                setState(() {
                                                  _boundUsername =
                                                      _usernameCtrl.text.trim();
                                                });
                                              }
                                            }
                                          : null,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _biometricAvailable
                                            ? '下次使用面容/指纹识别登录'
                                            : '未开启面容/指纹识别',
                                        style: TextStyle(
                                          color: _biometricAvailable
                                              ? theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                              : theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                // 登录按钮（大圆角 iOS 风格）
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: auth.loading
                                        ? null
                                        : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: auth.loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child:
                                                CircularProgressIndicator.adaptive(
                                                  strokeWidth: 2,
                                                ),
                                          )
                                        : const Text(
                                            '登录',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // 生物识别快速登录（次要按钮）
                                if (canUseBiometric)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: OutlinedButton.icon(
                                      onPressed: auth.loading
                                          ? null
                                          : _biometricLogin,
                                      icon: const Icon(Icons.fingerprint),
                                      label: Text(_biometricLabel),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 底部 © 不动
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
