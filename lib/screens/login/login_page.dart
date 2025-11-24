// lib/screens/login/login_page.dart

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
      // 登录成功 → 跳转到 /home
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("评估员登录")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(labelText: "用户名"),
            ),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(labelText: "密码"),
              obscureText: true,
            ),
            const SizedBox(height: 20),

            // 显示错误
            if (auth.error != null)
              Text(
                "${auth.error}",
                style: const TextStyle(color: Colors.red),
              ),

            const SizedBox(height: 20),

            // 登录按钮
            auth.loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleLogin,
                    child: const Text("登录"),
                  ),
          ],
        ),
      ),
    );
  }
}