// lib/screens/account/account_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  Future<void> _onLogoutPressed(BuildContext context) async {
    // 提前拿到依赖，避免 async gap 的 context 问题
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);

    // 先弹确认对话框（这个是 Future<bool?>，可以 await）
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('确认退出'),
          content: const Text('确定要退出当前账号吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('退出登录'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // logout 定义成 Future<void>，这里正常 await
    await auth.logout();

    // 跳回登录页，清空路由栈，这里返回 Future<T?>，也可以 await
    await navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的账号'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前用户：${user?.username ?? "未登录"}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              // 注意：这里没有 await，只是传一个回调
              onPressed: () => _onLogoutPressed(context),
              child: const Text('退出登录'),
            ),
          ],
        ),
      ),
    );
  }
}